//
//  WakeGuardModels.swift
//  LunaUpNow
//
//  Data model for the core differentiator: ONE user-created alarm starts ONE
//  persistent, multi-stage Wake Guard session. The session — not any sound —
//  is what stays unresolved for up to the configured maximum window (3h cap).
//

import Foundation

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6, saturday = 7, sunday = 1

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.sortIndex < rhs.sortIndex }

    /// Monday-first ordering for display, matching the mockups.
    var sortIndex: Int { rawValue == 1 ? 7 : rawValue - 1 }

    var shortName: String {
        switch self {
        case .monday: "Mon"; case .tuesday: "Tue"; case .wednesday: "Wed"
        case .thursday: "Thu"; case .friday: "Fri"; case .saturday: "Sat"; case .sunday: "Sun"
        }
    }

    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday; case .tuesday: .tuesday; case .wednesday: .wednesday
        case .thursday: .thursday; case .friday: .friday; case .saturday: .saturday; case .sunday: .sunday
        }
    }
}

// MARK: - Question

enum QuestionDifficulty: String, Codable, CaseIterable, Sendable {
    case gentle, balanced, hard

    var displayName: String {
        switch self {
        case .gentle: "Gentle"; case .balanced: "Balanced"; case .hard: "Hard"
        }
    }
}

struct Question: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var prompt: String
    var answer: Int
}

// MARK: - Stages

enum StageKind: String, Codable, CaseIterable, Sendable {
    case mainChallenge
    case stayAwakeCheck
    case finalConfirmation

    var title: String {
        switch self {
        case .mainChallenge: "Main Challenge"
        case .stayAwakeCheck: "Stay-Awake Check"
        case .finalConfirmation: "Final Wake Confirmation"
        }
    }
}

struct StagePlan: Codable, Hashable, Sendable {
    var kind: StageKind
    var questionCount: Int
    /// Delay after the previous stage completes before this stage unlocks.
    /// Ignored (treated as 0) for the first stage.
    var delayAfterPreviousStage: TimeInterval
    /// Once unlocked, if the stage is not completed within this window it is
    /// marked ignored (recorded + triggers escalation). The stage can still be
    /// completed afterwards, until the session's maximum window expires.
    var responseWindow: TimeInterval
}

// MARK: - Mode configuration

enum WakeGuardModePreset: String, Codable, CaseIterable, Sendable {
    case standard, heavySleeper, nuclear

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .heavySleeper: "Heavy Sleeper"
        case .nuclear: "Nuclear"
        }
    }
}

struct WakeGuardConfiguration: Codable, Hashable, Sendable {
    /// Absolute cap on any Wake Guard session, per product spec.
    static let absoluteMaxWindow: TimeInterval = 3 * 3600

    var preset: WakeGuardModePreset?
    var stages: [StagePlan]
    /// The session stays unresolved for at most this long after it starts.
    var maxWindow: TimeInterval
    /// Finishing all stages after this offset from session start is `completedLate`.
    var lateThreshold: TimeInterval
    /// Offsets (from session start) at which follow-up AlarmKit alerts fire if
    /// the session is still unresolved. Kept deliberately sparse — AlarmKit has
    /// a system alarm limit (`AlarmError.maximumLimitReached`).
    var escalationAlertOffsets: [TimeInterval]
    /// Offsets for optional supporting local notifications (reminders only —
    /// never a replacement for the primary AlarmKit alarm).
    var supportingReminderOffsets: [TimeInterval]
    var difficulty: QuestionDifficulty

    init(preset: WakeGuardModePreset?,
         stages: [StagePlan],
         maxWindow: TimeInterval,
         lateThreshold: TimeInterval,
         escalationAlertOffsets: [TimeInterval],
         supportingReminderOffsets: [TimeInterval],
         difficulty: QuestionDifficulty) {
        self.preset = preset
        self.stages = stages
        self.maxWindow = min(maxWindow, Self.absoluteMaxWindow)
        self.lateThreshold = lateThreshold
        self.escalationAlertOffsets = escalationAlertOffsets
        self.supportingReminderOffsets = supportingReminderOffsets
        self.difficulty = difficulty
    }

    static func preset(_ preset: WakeGuardModePreset, difficulty: QuestionDifficulty = .balanced) -> WakeGuardConfiguration {
        let min = 60.0
        switch preset {
        case .standard:
            return WakeGuardConfiguration(
                preset: .standard,
                stages: [
                    StagePlan(kind: .mainChallenge, questionCount: 5, delayAfterPreviousStage: 0, responseWindow: 10 * min),
                    StagePlan(kind: .stayAwakeCheck, questionCount: 2, delayAfterPreviousStage: 2 * min, responseWindow: 10 * min),
                ],
                maxWindow: 30 * min,
                lateThreshold: 15 * min,
                escalationAlertOffsets: [10 * min],
                supportingReminderOffsets: [5 * min],
                difficulty: difficulty)
        case .heavySleeper:
            return WakeGuardConfiguration(
                preset: .heavySleeper,
                stages: [
                    StagePlan(kind: .mainChallenge, questionCount: 5, delayAfterPreviousStage: 0, responseWindow: 10 * min),
                    StagePlan(kind: .stayAwakeCheck, questionCount: 2, delayAfterPreviousStage: 2 * min, responseWindow: 10 * min),
                    StagePlan(kind: .finalConfirmation, questionCount: 1, delayAfterPreviousStage: 5 * min, responseWindow: 10 * min),
                ],
                maxWindow: 90 * min,
                lateThreshold: 30 * min,
                escalationAlertOffsets: [10 * min, 25 * min, 60 * min],
                supportingReminderOffsets: [5 * min, 15 * min],
                difficulty: difficulty)
        case .nuclear:
            return WakeGuardConfiguration(
                preset: .nuclear,
                stages: [
                    StagePlan(kind: .mainChallenge, questionCount: 7, delayAfterPreviousStage: 0, responseWindow: 10 * min),
                    StagePlan(kind: .stayAwakeCheck, questionCount: 3, delayAfterPreviousStage: 2 * min, responseWindow: 10 * min),
                    StagePlan(kind: .finalConfirmation, questionCount: 2, delayAfterPreviousStage: 5 * min, responseWindow: 10 * min),
                ],
                maxWindow: 180 * min,
                lateThreshold: 45 * min,
                escalationAlertOffsets: [10 * min, 25 * min, 60 * min, 120 * min],
                supportingReminderOffsets: [5 * min, 15 * min, 40 * min],
                difficulty: difficulty)
        }
    }
}

// MARK: - Alarm

struct AlarmConfig: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var repeatDays: Set<Weekday> = []
    var isEnabled: Bool = true
    var preset: WakeGuardModePreset = .heavySleeper
    var difficulty: QuestionDifficulty = .balanced
    var label: String = ""

    var configuration: WakeGuardConfiguration {
        .preset(preset, difficulty: difficulty)
    }

    var timeText: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The next moment this alarm is scheduled to fire, strictly after `date`.
    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        guard !repeatDays.isEmpty else {
            return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
        }
        var best: Date?
        for day in repeatDays {
            comps.weekday = day.rawValue
            if let candidate = calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) {
                if best == nil || candidate < best! { best = candidate }
            }
        }
        return best
    }

    /// The most recent moment this alarm should have fired, at or before `date`.
    func lastFireDate(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let dayCandidates: [Int?] = repeatDays.isEmpty ? [nil] : repeatDays.map { $0.rawValue }
        var best: Date?
        for weekday in dayCandidates {
            comps.weekday = weekday
            var probe = date
            // Walk back day by day until the matching time is <= date.
            for _ in 0..<8 {
                guard let candidate = calendar.nextDate(after: probe.addingTimeInterval(-86_400 - 60),
                                                        matching: comps,
                                                        matchingPolicy: .nextTime) else { break }
                if candidate <= date {
                    if best == nil || candidate > best! { best = candidate }
                    break
                }
                probe = probe.addingTimeInterval(-86_400)
            }
        }
        return best
    }
}

// MARK: - Session

enum WakeGuardOutcome: String, Codable, CaseIterable, Sendable {
    /// All required stages passed within the late threshold.
    case completed
    /// All required stages passed, but after the mode's late threshold.
    case completedLate
    /// The main challenge (and possibly more) was passed, but the session
    /// expired before every required stage was completed.
    case followUpFailed
    /// The maximum window expired with no stage ever completed.
    case missed
    /// The session was aborted (alarm deleted/disabled mid-session, user
    /// cancelled from settings, etc.).
    case interrupted

    var displayName: String {
        switch self {
        case .completed: "Completed"
        case .completedLate: "Completed Late"
        case .followUpFailed: "Follow-up Failed"
        case .missed: "Missed"
        case .interrupted: "Interrupted"
        }
    }

    var isSuccess: Bool { self == .completed || self == .completedLate }
}

struct StageRecord: Codable, Hashable, Sendable {
    var plan: StagePlan
    /// Questions generated when the stage unlocked (persisted per spec).
    var questions: [Question] = []
    var correctAnswers: Int = 0
    var failedAttempts: Int = 0
    var availableAt: Date?
    var completedAt: Date?
    /// Set when the response window elapsed without completion. The stage can
    /// still be completed afterwards; this records the ignored check.
    var ignoredAt: Date?

    var isComplete: Bool { completedAt != nil }
    var isAvailable: Bool { availableAt != nil && completedAt == nil }
}

struct WakeGuardSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let alarmID: UUID
    let scheduledWakeTime: Date
    let sessionStart: Date
    let maxExpiration: Date
    var configuration: WakeGuardConfiguration
    var stages: [StageRecord]
    var currentStageIndex: Int = 0
    /// Ignored/failed checks + escalation alerts actually surfaced.
    var escalationCount: Int = 0
    /// AlarmKit IDs of follow-up alerts scheduled for this session, so they can
    /// be cancelled and reconciled. Derived deterministically — see Escalation.
    var scheduledEscalationIDs: [UUID] = []
    var outcome: WakeGuardOutcome?
    var completedAt: Date?

    var isResolved: Bool { outcome != nil }

    init(id: UUID = UUID(),
         alarmID: UUID,
         scheduledWakeTime: Date,
         sessionStart: Date,
         configuration: WakeGuardConfiguration) {
        self.id = id
        self.alarmID = alarmID
        self.scheduledWakeTime = scheduledWakeTime
        self.sessionStart = sessionStart
        self.maxExpiration = sessionStart.addingTimeInterval(configuration.maxWindow)
        self.configuration = configuration
        self.stages = configuration.stages.map { StageRecord(plan: $0) }
    }

    var completedStageCount: Int { stages.filter(\.isComplete).count }

    var currentStage: StageRecord? {
        stages.indices.contains(currentStageIndex) ? stages[currentStageIndex] : nil
    }

    /// When the next locked stage will unlock, if the current stage is complete.
    func nextStageUnlockDate() -> Date? {
        guard let lastCompleted = stages.last(where: { $0.isComplete })?.completedAt,
              stages.indices.contains(currentStageIndex),
              stages[currentStageIndex].availableAt == nil else { return nil }
        return lastCompleted.addingTimeInterval(stages[currentStageIndex].plan.delayAfterPreviousStage)
    }
}
