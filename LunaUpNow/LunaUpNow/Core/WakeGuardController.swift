//
//  WakeGuardController.swift
//  LunaUpNow
//
//  App-level orchestrator: owns alarms + sessions, drives the pure engine
//  with a clock, delegates alarm scheduling to the escalation coordinator,
//  persists every mutation, and restores unresolved Wake Guard sessions on
//  relaunch. Also hosts the simulator test controls (virtual time, forced
//  stages, simulated failures).
//

import Foundation
import Observation

@Observable
@MainActor
final class WakeGuardController {

    // MARK: State

    private(set) var alarms: [AlarmConfig] = []
    private(set) var sessions: [WakeGuardSession] = []
    private(set) var lastError: String?
    private(set) var simulationMode = false

    /// Monotonic counter bumped every engine tick so SwiftUI re-renders
    /// countdowns even when session equality doesn't change.
    private(set) var tickCount = 0

    private let store: WakeGuardPersisting
    private(set) var clock: ClockProviding
    private(set) var coordinator: AlarmEscalationCoordinating
    private let reminders: SupportingNotifications?

    private var liveClock: ClockProviding
    private var liveCoordinator: AlarmEscalationCoordinating
    private var tickTask: Task<Void, Never>?
    private var lastReconcile: Date?

    // MARK: Init

    init(store: WakeGuardPersisting,
         clock: ClockProviding,
         coordinator: AlarmEscalationCoordinating,
         reminders: SupportingNotifications? = nil) {
        self.store = store
        self.clock = clock
        self.coordinator = coordinator
        self.reminders = reminders
        self.liveClock = clock
        self.liveCoordinator = coordinator

        let state = store.load()
        self.alarms = state.alarms
        self.sessions = state.sessions
        restoreUnresolvedSessions()

        NotificationCenter.default.addObserver(forName: .wakeGuardAlarmActioned,
                                               object: nil,
                                               queue: .main) { [weak self] note in
            guard let idString = note.userInfo?["alarmID"] as? String,
                  let id = UUID(uuidString: idString) else { return }
            Task { @MainActor in self?.handleAlarmActioned(alarmID: id) }
        }
    }

    static func live() -> WakeGuardController {
        let store = JSONFileStore()
        let clock = SystemClock()
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        let coordinator = AlarmKitEscalationCoordinator()
        #else
        let coordinator = SimulatedEscalationCoordinator()
        #endif
        return WakeGuardController(store: store, clock: clock, coordinator: coordinator,
                                   reminders: SupportingNotifications())
    }

    // MARK: Derived

    var activeSession: WakeGuardSession? {
        sessions.first { !$0.isResolved }
    }

    var resolvedSessions: [WakeGuardSession] {
        sessions.filter(\.isResolved).sorted { $0.sessionStart > $1.sessionStart }
    }

    var nextAlarm: (alarm: AlarmConfig, fireDate: Date)? {
        let now = clock.now
        return alarms.filter(\.isEnabled)
            .compactMap { alarm in alarm.nextFireDate(after: now).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: Alarm CRUD (the user only ever creates ONE alarm per wake time)

    func addAlarm(_ alarm: AlarmConfig) {
        alarms.append(alarm)
        persist()
        if alarm.isEnabled { armInBackground(alarm) }
    }

    func updateAlarm(_ alarm: AlarmConfig) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[idx] = alarm
        persist()
        if alarm.isEnabled {
            armInBackground(alarm)
        } else {
            let coordinator = coordinator
            Task { await coordinator.disarmPrimary(alarm) }
        }
    }

    func deleteAlarm(_ alarm: AlarmConfig) {
        alarms.removeAll { $0.id == alarm.id }
        // An in-flight Wake Guard for a deleted alarm is interrupted, not lost.
        if var session = activeSession, session.alarmID == alarm.id {
            apply(events: WakeGuardEngine.interrupt(&session), to: session)
        }
        persist()
        let coordinator = coordinator
        Task { await coordinator.disarmPrimary(alarm) }
    }

    func setAlarmEnabled(_ alarm: AlarmConfig, enabled: Bool) {
        var updated = alarm
        updated.isEnabled = enabled
        updateAlarm(updated)
    }

    private func armInBackground(_ alarm: AlarmConfig) {
        let coordinator = coordinator
        Task {
            do {
                try await coordinator.armPrimary(alarm)
                lastError = nil
            } catch {
                lastError = "Couldn't schedule the alarm: \(describe(error))"
            }
        }
    }

    // MARK: Session lifecycle

    /// Called when the AlarmKit alert's custom action opens the app.
    func handleAlarmActioned(alarmID: UUID) {
        guard let alarm = alarms.first(where: { $0.id == alarmID }) else {
            // Escalation alerts carry the original alarm ID; if the alarm was
            // deleted mid-session there is nothing to start.
            tickActiveSession()
            return
        }
        let now = clock.now
        let wakeTime = alarm.lastFireDate(onOrBefore: now) ?? now
        startSessionIfNeeded(alarm: alarm, scheduledWakeTime: wakeTime)
    }

    /// Idempotent: one alarm firing produces exactly one session.
    @discardableResult
    func startSessionIfNeeded(alarm: AlarmConfig, scheduledWakeTime: Date) -> WakeGuardSession? {
        if let existing = activeSession { // never two concurrent sessions
            tickActiveSession()
            return existing
        }
        if sessions.contains(where: { $0.alarmID == alarm.id && $0.scheduledWakeTime == scheduledWakeTime }) {
            return nil // this firing already produced a session (possibly resolved)
        }
        let now = clock.now
        // Session start is the scheduled wake time even if the app opens later:
        // the guard window began when the alarm rang, not when the user showed up.
        let start = min(max(scheduledWakeTime, now.addingTimeInterval(-WakeGuardConfiguration.absoluteMaxWindow)), now)
        var (session, events) = WakeGuardEngine.startSession(alarm: alarm,
                                                             scheduledWakeTime: scheduledWakeTime,
                                                             now: start)
        events.append(contentsOf: WakeGuardEngine.tick(&session, now: now))
        sessions.append(session)
        apply(events: events, to: session)
        scheduleEscalations(for: session)
        startTickLoop()
        return session
    }

    func submitAnswer(_ answer: Int, questionID: UUID) -> Bool {
        guard let idx = sessions.firstIndex(where: { !$0.isResolved }) else { return false }
        var session = sessions[idx]
        let (correct, events) = WakeGuardEngine.submitAnswer(answer, to: questionID,
                                                             session: &session, now: clock.now)
        sessions[idx] = session
        apply(events: events, to: session)
        return correct
    }

    func tickActiveSession() {
        guard let idx = sessions.firstIndex(where: { !$0.isResolved }) else {
            tickTask?.cancel(); tickTask = nil
            return
        }
        var session = sessions[idx]
        let events = WakeGuardEngine.tick(&session, now: clock.now)
        sessions[idx] = session
        tickCount += 1
        if !events.isEmpty { apply(events: events, to: session) }
    }

    private func apply(events: [WakeGuardEvent], to session: WakeGuardSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        for event in events {
            switch event {
            case .sessionResolved:
                // Whatever the outcome, pending escalations must not fire.
                cancelEscalations(for: session)
                tickTask?.cancel(); tickTask = nil
            case .stageIgnored, .stageUnlocked, .stageCompleted:
                break
            }
        }
        persist()
    }

    // MARK: Escalation plumbing

    private func scheduleEscalations(for session: WakeGuardSession) {
        let coordinator = coordinator
        let reminders = reminders
        let now = clock.now
        Task {
            do {
                let ids = try await coordinator.scheduleEscalations(for: session, now: now)
                if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                    self.sessions[idx].scheduledEscalationIDs = ids
                    self.persist()
                }
            } catch {
                self.lastError = "Couldn't schedule follow-up alerts: \(self.describe(error))"
            }
            await reminders?.scheduleReminders(for: session, now: now)
        }
    }

    private func cancelEscalations(for session: WakeGuardSession) {
        let coordinator = coordinator
        let reminders = reminders
        Task {
            await coordinator.cancelEscalations(for: session)
            reminders?.cancelReminders(for: session)
            if let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                self.sessions[idx].scheduledEscalationIDs = []
                self.persist()
            }
        }
    }

    // MARK: App lifecycle

    /// Call whenever the app becomes active: restore, backfill missed
    /// firings, and reconcile system alarms against expected state.
    func handleBecameActive() {
        restoreUnresolvedSessions()
        backfillMissedFirings()
        let coordinator = coordinator
        let active = sessions.filter { !$0.isResolved }
        let armed = alarms.filter(\.isEnabled)
        Task { await coordinator.reconcile(activeSessions: active, armedAlarms: armed) }
        startTickLoop()
    }

    private func restoreUnresolvedSessions() {
        let now = clock.now
        for idx in sessions.indices where !sessions[idx].isResolved {
            var session = sessions[idx]
            let events = WakeGuardEngine.tick(&session, now: now)
            sessions[idx] = session
            if !events.isEmpty { apply(events: events, to: session) }
        }
        startTickLoop()
    }

    /// If an armed alarm fired while the app was dead and the user never
    /// engaged, the session still exists conceptually — represent it.
    private func backfillMissedFirings() {
        let now = clock.now
        let horizon = lastReconcile ?? now.addingTimeInterval(-24 * 3600)
        for alarm in alarms.filter(\.isEnabled) {
            guard let fired = alarm.lastFireDate(onOrBefore: now), fired > horizon else { continue }
            guard !sessions.contains(where: { $0.alarmID == alarm.id && $0.scheduledWakeTime == fired }) else { continue }
            if now < fired.addingTimeInterval(alarm.configuration.maxWindow) {
                // Still inside the window — the Wake Guard resumes right now.
                startSessionIfNeeded(alarm: alarm, scheduledWakeTime: fired)
            } else {
                // Window fully elapsed with no interaction: record a Missed session.
                var (session, _) = WakeGuardEngine.startSession(alarm: alarm,
                                                                scheduledWakeTime: fired,
                                                                now: fired)
                _ = WakeGuardEngine.tick(&session, now: now)
                sessions.append(session)
                persist()
            }
        }
        lastReconcile = now
    }

    private func startTickLoop() {
        guard activeSession != nil, tickTask == nil, !simulationMode else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tickActiveSession()
                if self.activeSession == nil { return }
            }
        }
    }

    // MARK: Persistence

    private func persist() {
        store.save(PersistedState(alarms: alarms, sessions: sessions))
    }

    private func describe(_ error: Error) -> String {
        if case EscalationError.notAuthorized = error {
            return "Alarm permission was denied. Enable alarms for LunaUpNow in Settings."
        }
        if case let EscalationError.schedulingFailed(reason) = error { return reason }
        return error.localizedDescription
    }

    // MARK: - Simulator test controls

    var virtualClock: VirtualClock? { clock as? VirtualClock }
    var simulatedCoordinator: SimulatedEscalationCoordinator? { coordinator as? SimulatedEscalationCoordinator }

    func enableSimulationMode() {
        guard !simulationMode else { return }
        simulationMode = true
        tickTask?.cancel(); tickTask = nil
        clock = VirtualClock(now: liveClock.now)
        coordinator = SimulatedEscalationCoordinator()
    }

    func disableSimulationMode() {
        guard simulationMode else { return }
        simulationMode = false
        clock = liveClock
        coordinator = liveCoordinator
        startTickLoop()
    }

    /// Start a Wake Guard right now (uses the first enabled alarm's settings,
    /// or a throwaway Heavy Sleeper alarm if none exist).
    func devStartSessionNow(preset: WakeGuardModePreset? = nil) {
        var alarm = alarms.first(where: \.isEnabled)
            ?? AlarmConfig(hour: 7, minute: 0, preset: .heavySleeper)
        if let preset { alarm.preset = preset }
        if !alarms.contains(where: { $0.id == alarm.id }) { alarms.append(alarm); persist() }
        startSessionIfNeeded(alarm: alarm, scheduledWakeTime: clock.now)
    }

    func devAdvanceTime(by interval: TimeInterval) {
        virtualClock?.advance(by: interval)
        tickActiveSession()
    }

    /// Answer every remaining question of the current stage correctly.
    func devCompleteCurrentStage() {
        guard let session = activeSession else { return }
        var guard_ = 0
        while let question = WakeGuardEngine.activeQuestion(in: activeSession ?? session), guard_ < 50 {
            _ = submitAnswer(question.answer, questionID: question.id)
            guard_ += 1
            if activeSession == nil { break }
        }
    }

    /// Jump virtual time past the current stage's response window.
    func devSimulateIgnoredCheck() {
        guard let session = activeSession,
              let stage = session.stages.first(where: { $0.isAvailable }),
              let availableAt = stage.availableAt else { return }
        let target = availableAt.addingTimeInterval(stage.plan.responseWindow + 1)
        let delta = target.timeIntervalSince(clock.now)
        if delta > 0 { devAdvanceTime(by: delta) } else { tickActiveSession() }
    }

    /// Jump virtual time to the session's maximum expiration.
    func devSimulateExpiration() {
        guard let session = activeSession else { return }
        let delta = session.maxExpiration.timeIntervalSince(clock.now) + 1
        if delta > 0 { devAdvanceTime(by: delta) }
    }

    func devSetSchedulingFailure(_ failing: Bool) {
        simulatedCoordinator?.simulateSchedulingFailure = failing
        if failing, let session = activeSession {
            // Exercise the failure path immediately so the UI surfaces it.
            scheduleEscalations(for: session)
        }
    }

    // MARK: - Stats (Home / History)

    struct WakeStats {
        var onTimeRate: Double?          // completed ÷ finished sessions
        var averageTimeToComplete: TimeInterval?
        var streakDays: Int
        var totalAlarms: Int
    }

    var stats: WakeStats {
        let finished = resolvedSessions
        let successes = finished.filter { $0.outcome?.isSuccess == true }
        let onTime = finished.filter { $0.outcome == .completed }
        let durations = successes.compactMap { s in s.completedAt.map { $0.timeIntervalSince(s.sessionStart) } }

        var streak = 0
        for session in finished {
            if session.outcome?.isSuccess == true { streak += 1 } else { break }
        }
        return WakeStats(
            onTimeRate: finished.isEmpty ? nil : Double(onTime.count) / Double(finished.count),
            averageTimeToComplete: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count),
            streakDays: streak,
            totalAlarms: alarms.count)
    }
}
