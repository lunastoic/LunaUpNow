//
//  Escalation.swift
//  LunaUpNow
//
//  Escalation strategy behind a protocol. The primary AlarmKit alarm is the
//  only alarm the user ever creates. While a Wake Guard session is unresolved,
//  the coordinator may schedule a SMALL number of follow-up AlarmKit alerts
//  (fixed-date, one-shot) plus optional supporting local notifications.
//
//  Honesty notes (verified against the installed AlarmKit 26.5 SDK):
//  - Nothing in AlarmKit promises that one alert sounds continuously for
//    hours. The persistence of Wake Guard is SESSION STATE, not sound.
//  - AlarmManager.AlarmError.maximumLimitReached exists, so follow-up alerts
//    are sparse, deduplicated, and reconciled — never spammed.
//  - Follow-up alerts use deterministic IDs derived from the session UUID, so
//    they are linkable, idempotent to reschedule, and removable.
//

import Foundation
import CryptoKit

// MARK: - Derived identifiers

enum LinkedAlarmID {
    /// Deterministic UUIDv5-style derivation: same session + slot always maps
    /// to the same alarm ID. This is what makes dedupe and reconciliation safe.
    static func escalationID(sessionID: UUID, slot: Int) -> UUID {
        var data = withUnsafeBytes(of: sessionID.uuid) { Data($0) }
        data.append(Data("wakeguard.escalation.\(slot)".utf8))
        let digest = Insecure.SHA1.hash(data: data)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - Plan

struct EscalationStep: Equatable, Sendable {
    let slot: Int
    let alarmID: UUID
    let fireDate: Date
}

enum EscalationPlanner {
    /// Hard cap on secondary alerts per session, independent of configuration,
    /// because AlarmKit enforces a system-wide alarm limit.
    static let maxSecondaryAlerts = 4

    /// Follow-up AlarmKit alert steps still in the future for an unresolved
    /// session. Steps at/after maxExpiration are dropped.
    static func steps(for session: WakeGuardSession, now: Date) -> [EscalationStep] {
        guard !session.isResolved else { return [] }
        return session.configuration.escalationAlertOffsets
            .prefix(maxSecondaryAlerts)
            .enumerated()
            .compactMap { slot, offset in
                let fireDate = session.sessionStart.addingTimeInterval(offset)
                guard fireDate > now, fireDate < session.maxExpiration else { return nil }
                return EscalationStep(slot: slot,
                                      alarmID: LinkedAlarmID.escalationID(sessionID: session.id, slot: slot),
                                      fireDate: fireDate)
            }
    }

    /// Every ID this session could ever have scheduled — used for cleanup.
    static func allPossibleEscalationIDs(for session: WakeGuardSession) -> [UUID] {
        (0..<min(session.configuration.escalationAlertOffsets.count, maxSecondaryAlerts))
            .map { LinkedAlarmID.escalationID(sessionID: session.id, slot: $0) }
    }
}

// MARK: - Coordinator protocol

enum EscalationError: Error, Equatable {
    case schedulingFailed(String)
    case notAuthorized
}

@MainActor
protocol AlarmEscalationCoordinating: AnyObject {
    /// Schedule (or replace) the single user-created primary alarm.
    func armPrimary(_ alarm: AlarmConfig) async throws
    /// Remove the primary alarm from the system.
    func disarmPrimary(_ alarm: AlarmConfig) async

    /// Schedule the session's still-future follow-up alerts. Must be
    /// idempotent: already-scheduled IDs are skipped, never duplicated.
    /// Returns the IDs now scheduled for this session.
    @discardableResult
    func scheduleEscalations(for session: WakeGuardSession, now: Date) async throws -> [UUID]

    /// Cancel every follow-up alert belonging to this session (on completion,
    /// interruption, or expiry). The primary alarm is not touched.
    func cancelEscalations(for session: WakeGuardSession) async

    /// Compare system alarms against expected state whenever the app becomes
    /// active: remove orphaned escalation alerts of resolved/unknown sessions.
    func reconcile(activeSessions: [WakeGuardSession], armedAlarms: [AlarmConfig]) async
}
