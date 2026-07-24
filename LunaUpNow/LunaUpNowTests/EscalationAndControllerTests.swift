//
//  EscalationAndControllerTests.swift
//  LunaUpNowTests
//
//  Escalation planning/dedup, cancellation on completion, relaunch restore,
//  and controller-level behavior with the simulated coordinator.
//

import Foundation
import Testing
@testable import LunaUpNow

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
private func makeController(store: WakeGuardPersisting = InMemoryStore(),
                            clock: VirtualClock = VirtualClock(now: t0))
    -> (WakeGuardController, SimulatedEscalationCoordinator, VirtualClock) {
    let coordinator = SimulatedEscalationCoordinator()
    let controller = WakeGuardController(store: store, clock: clock, coordinator: coordinator)
    return (controller, coordinator, clock)
}

/// The controller fires coordinator work in Tasks; give them a chance to run.
@MainActor
private func drainMainQueue() async {
    for _ in 0..<20 { await Task.yield() }
}

@MainActor
private func passCurrentStage(_ controller: WakeGuardController) {
    while let session = controller.activeSession,
          let q = WakeGuardEngine.activeQuestion(in: session) {
        _ = controller.submitAnswer(q.answer, questionID: q.id)
    }
}

// MARK: - Planner

struct EscalationPlannerTests {

    @Test func stepsUseStableLinkedIdentifiers() {
        let alarm = AlarmConfig(hour: 7, minute: 0, preset: .nuclear)
        let (session, _) = WakeGuardEngine.startSession(alarm: alarm, scheduledWakeTime: t0, now: t0)
        let a = EscalationPlanner.steps(for: session, now: t0)
        let b = EscalationPlanner.steps(for: session, now: t0)
        #expect(a == b)
        #expect(a.map(\.alarmID) == EscalationPlanner.allPossibleEscalationIDs(for: session))
        // Derived IDs are unique per slot and reproducible.
        #expect(Set(a.map(\.alarmID)).count == a.count)
        #expect(LinkedAlarmID.escalationID(sessionID: session.id, slot: 0)
                == LinkedAlarmID.escalationID(sessionID: session.id, slot: 0))
    }

    @Test func stepsExcludePastAndPostExpirationTimes() {
        let alarm = AlarmConfig(hour: 7, minute: 0, preset: .nuclear) // offsets 10/25/60/120 min
        let (session, _) = WakeGuardEngine.startSession(alarm: alarm, scheduledWakeTime: t0, now: t0)
        let later = t0.addingTimeInterval(26 * 60) // 10- and 25-minute steps already past
        let steps = EscalationPlanner.steps(for: session, now: later)
        #expect(steps.map(\.slot) == [2, 3])
    }

    @Test func resolvedSessionsPlanNoEscalations() {
        let alarm = AlarmConfig(hour: 7, minute: 0, preset: .standard)
        var (session, _) = WakeGuardEngine.startSession(alarm: alarm, scheduledWakeTime: t0, now: t0)
        _ = WakeGuardEngine.interrupt(&session)
        #expect(EscalationPlanner.steps(for: session, now: t0).isEmpty)
    }

    @Test func secondaryAlertCountIsHardCapped() {
        let config = WakeGuardConfiguration(preset: nil,
                                            stages: [StagePlan(kind: .mainChallenge, questionCount: 1,
                                                               delayAfterPreviousStage: 0, responseWindow: 600)],
                                            maxWindow: 3 * 3600,
                                            lateThreshold: 600,
                                            escalationAlertOffsets: [60, 120, 180, 240, 300, 360, 420], // 7 asked
                                            supportingReminderOffsets: [],
                                            difficulty: .balanced)
        var alarm = AlarmConfig(hour: 7, minute: 0)
        alarm.preset = .nuclear
        var (session, _) = WakeGuardEngine.startSession(alarm: alarm, scheduledWakeTime: t0, now: t0)
        session.configuration = config
        #expect(EscalationPlanner.steps(for: session, now: t0).count == EscalationPlanner.maxSecondaryAlerts)
    }
}

// MARK: - Coordinator behavior

@MainActor
struct EscalationCoordinatorTests {

    @Test func duplicateSchedulingIsPrevented() async throws {
        let (controller, coordinator, _) = makeController()
        controller.devStartSessionNow(preset: .nuclear)
        await drainMainQueue()
        let session = try #require(controller.activeSession)

        let countAfterFirst = coordinator.scheduledEscalations.count
        #expect(countAfterFirst > 0)

        // Re-scheduling the same session must not create duplicates.
        _ = try await coordinator.scheduleEscalations(for: session, now: controller.clock.now)
        _ = try await coordinator.scheduleEscalations(for: session, now: controller.clock.now)
        #expect(coordinator.scheduledEscalations.count == countAfterFirst)
    }

    @Test func escalationsAreCancelledAfterSuccessfulCompletion() async throws {
        let (controller, coordinator, clock) = makeController()
        controller.devStartSessionNow(preset: .heavySleeper)
        await drainMainQueue()
        let sessionID = try #require(controller.activeSession?.id)
        #expect(!coordinator.scheduledEscalations.isEmpty)

        passCurrentStage(controller)               // stage 1
        clock.advance(by: 120); controller.tickActiveSession()
        passCurrentStage(controller)               // stage 2
        clock.advance(by: 300); controller.tickActiveSession()
        passCurrentStage(controller)               // stage 3 → resolved

        #expect(controller.activeSession == nil)
        #expect(controller.resolvedSessions.first?.outcome == .completed)

        await drainMainQueue()
        #expect(coordinator.cancelledSessionIDs.contains(sessionID))
        #expect(coordinator.scheduledEscalations.isEmpty)
    }

    @Test func reconcileRemovesOrphanedEscalations() async throws {
        let (controller, coordinator, clock) = makeController()
        controller.devStartSessionNow(preset: .nuclear)
        await drainMainQueue()
        #expect(!coordinator.scheduledEscalations.isEmpty)

        // Session expires -> resolved; simulate an orphan left behind by
        // reconciling with no active sessions.
        clock.advance(by: 3 * 3600 + 1)
        controller.tickActiveSession()
        #expect(controller.activeSession == nil)
        await coordinator.reconcile(activeSessions: [], armedAlarms: [])
        #expect(coordinator.scheduledEscalations.isEmpty)
    }

    @Test func schedulingFailureIsSurfacedNotFatal() async throws {
        let (controller, coordinator, _) = makeController()
        coordinator.simulateSchedulingFailure = true
        controller.devStartSessionNow(preset: .standard)
        await drainMainQueue()
        // Session still runs (the guard is state, not alerts)…
        #expect(controller.activeSession != nil)
        // …but the failure is reported.
        #expect(controller.lastError?.contains("follow-up") == true)
        #expect(coordinator.scheduledEscalations.isEmpty)
    }
}

// MARK: - Persistence / relaunch

@MainActor
struct RelaunchRestoreTests {

    @Test func unresolvedSessionSurvivesRelaunchWithFullState() async throws {
        let store = InMemoryStore()
        let clock = VirtualClock(now: t0)
        let (controller, _, _) = makeController(store: store, clock: clock)

        controller.devStartSessionNow(preset: .heavySleeper)
        await drainMainQueue()
        passCurrentStage(controller) // finish main challenge
        let original = try #require(controller.sessions.first)
        #expect(original.stages[0].isComplete)
        #expect(original.outcome == nil)

        // "Relaunch": brand-new controller over the same store & clock.
        clock.advance(by: 60)
        let (relaunched, _, _) = makeController(store: store, clock: clock)
        let restored = try #require(relaunched.activeSession)

        #expect(restored.id == original.id)
        #expect(restored.alarmID == original.alarmID)
        #expect(restored.scheduledWakeTime == original.scheduledWakeTime)
        #expect(restored.maxExpiration == original.maxExpiration)
        #expect(restored.currentStageIndex == 1)
        #expect(restored.stages[0].questions == original.stages[0].questions)
    }

    @Test func expiredSessionIsMarkedMissedOnRelaunch() async throws {
        let store = InMemoryStore()
        let clock = VirtualClock(now: t0)
        let (controller, _, _) = makeController(store: store, clock: clock)
        controller.devStartSessionNow(preset: .nuclear)
        await drainMainQueue()

        // App "terminates"; user sleeps through everything; relaunch after 4h.
        clock.advance(by: 4 * 3600)
        let (relaunched, _, _) = makeController(store: store, clock: clock)

        #expect(relaunched.activeSession == nil)
        #expect(relaunched.resolvedSessions.first?.outcome == .missed)
    }

    @Test func persistedStateRoundTripsThroughJSON() throws {
        let alarm = AlarmConfig(hour: 6, minute: 45, repeatDays: [.monday, .friday], preset: .nuclear)
        var (session, _) = WakeGuardEngine.startSession(alarm: alarm, scheduledWakeTime: t0, now: t0)
        session.scheduledEscalationIDs = EscalationPlanner.allPossibleEscalationIDs(for: session)
        session.escalationCount = 2

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wakeguard-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = JSONFileStore(url: url)
        store.save(PersistedState(alarms: [alarm], sessions: [session]))
        let loaded = store.load()

        #expect(loaded.alarms == [alarm])
        #expect(loaded.sessions == [session])
        #expect(loaded.sessions[0].scheduledEscalationIDs.count == 4)
    }
}

// MARK: - Controller session semantics

@MainActor
struct ControllerSessionTests {

    @Test func oneAlarmFiringProducesExactlyOneSession() async throws {
        let (controller, _, _) = makeController()
        let alarm = AlarmConfig(hour: 7, minute: 0, preset: .standard)
        controller.addAlarm(alarm)
        let first = controller.startSessionIfNeeded(alarm: alarm, scheduledWakeTime: t0)
        let second = controller.startSessionIfNeeded(alarm: alarm, scheduledWakeTime: t0)
        #expect(first?.id == second?.id)
        #expect(controller.sessions.count == 1)
    }

    @Test func deletingAlarmInterruptsItsActiveSession() async throws {
        let (controller, _, _) = makeController()
        let alarm = AlarmConfig(hour: 7, minute: 0, preset: .standard)
        controller.addAlarm(alarm)
        _ = controller.startSessionIfNeeded(alarm: alarm, scheduledWakeTime: t0)
        #expect(controller.activeSession != nil)

        controller.deleteAlarm(alarm)
        #expect(controller.activeSession == nil)
        #expect(controller.resolvedSessions.first?.outcome == .interrupted)
    }
}
