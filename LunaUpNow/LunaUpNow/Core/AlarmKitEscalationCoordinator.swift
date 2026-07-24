//
//  AlarmKitEscalationCoordinator.swift
//  LunaUpNow
//
//  Real AlarmKit-backed coordinator. Behavior grounded in the AlarmKit
//  interface shipped with the iOS 26.5 SDK:
//
//  - `AlarmManager.schedule(id:configuration:)` takes an app-supplied UUID, so
//    the primary alarm uses the AlarmConfig's UUID and follow-up alerts use
//    IDs deterministically derived from the session UUID (stable, linked).
//  - `.fixed(Date)` one-shot schedules are used for follow-up alerts; they are
//    created only while a session is unresolved and removed on resolution.
//  - `AlarmError.maximumLimitReached` is a real error case — the planner caps
//    secondary alerts and this class dedupes against `manager.alarms`.
//  - `stopButton` is deprecated as of iOS 26.1 (the system renders stop). The
//    secondary button uses `.custom` + a LiveActivityIntent to open the app
//    into the Wake Guard flow.
//
//  REQUIRES PHYSICAL-DEVICE TESTING. Alert duration, Silent Mode/Focus
//  behavior, and terminated-app delivery cannot be verified in the simulator.
//

import Foundation
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit

struct WakeGuardAlarmMetadata: AlarmMetadata {
    /// Session this alert belongs to (nil for the primary alarm, which exists
    /// before any session does).
    var sessionID: UUID?
    var alarmConfigID: UUID
    /// "primary" or "escalation-<slot>" — for debugging and reconciliation.
    var role: String
}

@MainActor
final class AlarmKitEscalationCoordinator: AlarmEscalationCoordinating {
    private let manager = AlarmManager.shared

    // MARK: Authorization

    private func ensureAuthorized() async throws {
        switch manager.authorizationState {
        case .authorized:
            return
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else { throw EscalationError.notAuthorized }
        case .denied:
            throw EscalationError.notAuthorized
        @unknown default:
            throw EscalationError.notAuthorized
        }
    }

    // MARK: Primary alarm

    func armPrimary(_ alarm: AlarmConfig) async throws {
        try await ensureAuthorized()

        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence = alarm.repeatDays.isEmpty
            ? .never
            : .weekly(alarm.repeatDays.sorted().map(\.localeWeekday))
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))

        let alert = AlarmPresentation.Alert(
            title: "Wake Guard — time to get up",
            secondaryButton: AlarmButton(text: "I'm Up — Start Challenge",
                                         textColor: .white,
                                         systemImageName: "shield.checkered"),
            secondaryButtonBehavior: .custom)

        let attributes = AlarmAttributes<WakeGuardAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeGuardAlarmMetadata(sessionID: nil, alarmConfigID: alarm.id, role: "primary"),
            tintColor: Theme.accent)

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: StartWakeGuardIntent(alarmID: alarm.id))

        do {
            _ = try await manager.schedule(id: alarm.id, configuration: configuration)
        } catch {
            throw Self.friendlyScheduleError(error, authorizationState: manager.authorizationState)
        }
    }

    /// The daemon can reject a schedule with an opaque NSError (e.g.
    /// "com.apple.AlarmKit.Alarm error 1") even after the app-side
    /// authorization check passed — most commonly because alarm permission is
    /// off. Re-check authorization and translate to something actionable.
    static func friendlyScheduleError(_ error: Error,
                                      authorizationState: AlarmManager.AuthorizationState) -> EscalationError {
        if case AlarmManager.AlarmError.maximumLimitReached = error {
            return .schedulingFailed("iOS's alarm limit was reached. Remove some alarms and try again.")
        }
        guard authorizationState == .authorized else { return .notAuthorized }
        let ns = error as NSError
        return .schedulingFailed(
            "iOS rejected the alarm (\(ns.domain) \(ns.code)). "
            + "Check that alarms are allowed for LunaUpNow in the Settings app, then toggle the alarm off and on.")
    }

    func disarmPrimary(_ alarm: AlarmConfig) async {
        try? manager.cancel(id: alarm.id)
    }

    // MARK: Follow-up alerts

    @discardableResult
    func scheduleEscalations(for session: WakeGuardSession, now: Date) async throws -> [UUID] {
        try await ensureAuthorized()
        let steps = EscalationPlanner.steps(for: session, now: now)
        guard !steps.isEmpty else { return [] }

        let existingIDs = Set((try? manager.alarms)?.map(\.id) ?? [])
        var scheduled: [UUID] = []

        for step in steps {
            // Dedupe: deterministic IDs mean "already in the system" is exact.
            if existingIDs.contains(step.alarmID) {
                scheduled.append(step.alarmID)
                continue
            }
            let alert = AlarmPresentation.Alert(
                title: "Wake Guard is still active — finish your checks",
                secondaryButton: AlarmButton(text: "Continue Wake Guard",
                                             textColor: .white,
                                             systemImageName: "shield.checkered"),
                secondaryButtonBehavior: .custom)
            let attributes = AlarmAttributes<WakeGuardAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: WakeGuardAlarmMetadata(sessionID: session.id,
                                                 alarmConfigID: session.alarmID,
                                                 role: "escalation-\(step.slot)"),
                tintColor: Theme.accent)
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(step.fireDate),
                attributes: attributes,
                secondaryIntent: StartWakeGuardIntent(alarmID: session.alarmID))
            do {
                _ = try await manager.schedule(id: step.alarmID, configuration: configuration)
                scheduled.append(step.alarmID)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                // System alarm limit hit — stop adding, keep what we have.
                break
            } catch {
                throw Self.friendlyScheduleError(error, authorizationState: manager.authorizationState)
            }
        }
        return scheduled
    }

    func cancelEscalations(for session: WakeGuardSession) async {
        for id in EscalationPlanner.allPossibleEscalationIDs(for: session) {
            try? manager.cancel(id: id)
        }
    }

    // MARK: Reconciliation

    func reconcile(activeSessions: [WakeGuardSession], armedAlarms: [AlarmConfig]) async {
        guard let systemAlarms = try? manager.alarms else { return }
        var expected = Set(armedAlarms.map(\.id))
        for session in activeSessions {
            expected.formUnion(EscalationPlanner.allPossibleEscalationIDs(for: session))
        }
        // Any alarm of ours the model doesn't expect is an orphan (e.g. an
        // escalation alert for a session resolved while the app was dead).
        for alarm in systemAlarms where !expected.contains(alarm.id) {
            try? manager.cancel(id: alarm.id)
        }
    }
}
#endif
