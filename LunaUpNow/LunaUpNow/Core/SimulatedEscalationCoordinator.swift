//
//  SimulatedEscalationCoordinator.swift
//  LunaUpNow
//
//  In-memory coordinator used by unit tests and the simulator dev controls.
//  Mirrors the contract of the AlarmKit coordinator, including the ability to
//  simulate an AlarmKit scheduling failure.
//

import Foundation

@MainActor
final class SimulatedEscalationCoordinator: AlarmEscalationCoordinating {
    private(set) var armedPrimaryIDs: Set<UUID> = []
    private(set) var scheduledEscalations: [UUID: EscalationStep] = [:]
    private(set) var cancelledSessionIDs: [UUID] = []
    private(set) var scheduleCallCount = 0

    /// Dev control: simulate AlarmKit refusing to schedule.
    var simulateSchedulingFailure = false

    func armPrimary(_ alarm: AlarmConfig) async throws {
        if simulateSchedulingFailure { throw EscalationError.schedulingFailed("Simulated AlarmKit failure") }
        armedPrimaryIDs.insert(alarm.id)
    }

    func disarmPrimary(_ alarm: AlarmConfig) async {
        armedPrimaryIDs.remove(alarm.id)
    }

    @discardableResult
    func scheduleEscalations(for session: WakeGuardSession, now: Date) async throws -> [UUID] {
        scheduleCallCount += 1
        if simulateSchedulingFailure { throw EscalationError.schedulingFailed("Simulated AlarmKit failure") }
        let steps = EscalationPlanner.steps(for: session, now: now)
        for step in steps where scheduledEscalations[step.alarmID] == nil {
            scheduledEscalations[step.alarmID] = step
        }
        return steps.map(\.alarmID)
    }

    func cancelEscalations(for session: WakeGuardSession) async {
        cancelledSessionIDs.append(session.id)
        for id in EscalationPlanner.allPossibleEscalationIDs(for: session) {
            scheduledEscalations.removeValue(forKey: id)
        }
    }

    func reconcile(activeSessions: [WakeGuardSession], armedAlarms: [AlarmConfig]) async {
        let expected = Set(activeSessions.flatMap { EscalationPlanner.allPossibleEscalationIDs(for: $0) })
        for id in scheduledEscalations.keys where !expected.contains(id) {
            scheduledEscalations.removeValue(forKey: id)
        }
    }
}
