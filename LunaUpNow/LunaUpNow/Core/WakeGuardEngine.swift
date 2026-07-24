//
//  WakeGuardEngine.swift
//  LunaUpNow
//
//  Pure state machine for a Wake Guard session. No timers, no AlarmKit, no
//  I/O — callers feed it "now" and apply the returned events. This is what the
//  unit tests exercise and what the simulator dev controls drive with a
//  VirtualClock.
//

import Foundation

enum WakeGuardEvent: Equatable, Sendable {
    case stageUnlocked(index: Int)
    case stageIgnored(index: Int)
    case stageCompleted(index: Int)
    case sessionResolved(WakeGuardOutcome)
}

enum WakeGuardEngine {

    /// Create and start a session for an alarm firing.
    static func startSession(alarm: AlarmConfig,
                             scheduledWakeTime: Date,
                             now: Date,
                             sessionID: UUID = UUID()) -> (WakeGuardSession, [WakeGuardEvent]) {
        var session = WakeGuardSession(id: sessionID,
                                       alarmID: alarm.id,
                                       scheduledWakeTime: scheduledWakeTime,
                                       sessionStart: now,
                                       configuration: alarm.configuration)
        let events = unlockStageIfDue(&session, now: now)
        return (session, events)
    }

    /// Advance the session to `now`. Idempotent: safe to call repeatedly.
    @discardableResult
    static func tick(_ session: inout WakeGuardSession, now: Date) -> [WakeGuardEvent] {
        guard !session.isResolved else { return [] }
        var events: [WakeGuardEvent] = []

        // Expiration always wins.
        if now >= session.maxExpiration {
            let outcome: WakeGuardOutcome = session.completedStageCount == 0 ? .missed : .followUpFailed
            session.outcome = outcome
            events.append(.sessionResolved(outcome))
            return events
        }

        events.append(contentsOf: unlockStageIfDue(&session, now: now))

        // Ignored-check detection on the current stage.
        if let idx = session.stages.firstIndex(where: { $0.isAvailable }),
           session.stages[idx].ignoredAt == nil,
           let availableAt = session.stages[idx].availableAt,
           now >= availableAt.addingTimeInterval(session.stages[idx].plan.responseWindow) {
            session.stages[idx].ignoredAt = now
            session.escalationCount += 1
            events.append(.stageIgnored(index: idx))
        }
        return events
    }

    /// Submit one answer for the current stage. Returns whether it was correct.
    /// Progress within a stage counts only correct answers; wrong answers are
    /// recorded as failed attempts.
    static func submitAnswer(_ answer: Int,
                             to questionID: UUID,
                             session: inout WakeGuardSession,
                             now: Date) -> (correct: Bool, events: [WakeGuardEvent]) {
        var events = tick(&session, now: now)
        guard !session.isResolved,
              session.stages.indices.contains(session.currentStageIndex) else { return (false, events) }
        let idx = session.currentStageIndex
        guard session.stages[idx].isAvailable,
              let question = session.stages[idx].questions.first(where: { $0.id == questionID }) else {
            return (false, events)
        }

        if question.answer == answer {
            session.stages[idx].correctAnswers += 1
            if session.stages[idx].correctAnswers >= session.stages[idx].plan.questionCount {
                events.append(contentsOf: completeCurrentStage(&session, now: now))
            }
            return (true, events)
        } else {
            session.stages[idx].failedAttempts += 1
            return (false, events)
        }
    }

    /// The question the user should currently be answering, if any.
    static func activeQuestion(in session: WakeGuardSession) -> Question? {
        guard session.stages.indices.contains(session.currentStageIndex) else { return nil }
        let stage = session.stages[session.currentStageIndex]
        guard stage.isAvailable, stage.correctAnswers < stage.questions.count else { return nil }
        return stage.questions[stage.correctAnswers]
    }

    /// Abort an unresolved session (alarm deleted, user cancelled, …).
    @discardableResult
    static func interrupt(_ session: inout WakeGuardSession) -> [WakeGuardEvent] {
        guard !session.isResolved else { return [] }
        session.outcome = .interrupted
        return [.sessionResolved(.interrupted)]
    }

    // MARK: - Internals

    private static func unlockStageIfDue(_ session: inout WakeGuardSession, now: Date) -> [WakeGuardEvent] {
        guard session.stages.indices.contains(session.currentStageIndex),
              session.stages[session.currentStageIndex].availableAt == nil else { return [] }

        let idx = session.currentStageIndex
        let unlockDate: Date
        if idx == 0 {
            unlockDate = session.sessionStart
        } else if let previousCompleted = session.stages[idx - 1].completedAt {
            unlockDate = previousCompleted.addingTimeInterval(session.stages[idx].plan.delayAfterPreviousStage)
        } else {
            return [] // previous stage not done — nothing to unlock
        }

        guard now >= unlockDate else { return [] }
        session.stages[idx].availableAt = unlockDate
        if session.stages[idx].questions.isEmpty {
            session.stages[idx].questions = QuestionGenerator.questions(
                count: session.stages[idx].plan.questionCount,
                difficulty: session.configuration.difficulty,
                seed: QuestionGenerator.seed(sessionID: session.id, stageIndex: idx))
        }
        return [.stageUnlocked(index: idx)]
    }

    private static func completeCurrentStage(_ session: inout WakeGuardSession, now: Date) -> [WakeGuardEvent] {
        let idx = session.currentStageIndex
        session.stages[idx].completedAt = now
        var events: [WakeGuardEvent] = [.stageCompleted(index: idx)]

        if idx == session.stages.count - 1 {
            // All required stages passed — only now is the session a success.
            let late = now > session.sessionStart.addingTimeInterval(session.configuration.lateThreshold)
            let outcome: WakeGuardOutcome = late ? .completedLate : .completed
            session.outcome = outcome
            session.completedAt = now
            events.append(.sessionResolved(outcome))
        } else {
            session.currentStageIndex += 1
            // A zero-delay next stage unlocks immediately.
            events.append(contentsOf: unlockStageIfDue(&session, now: now))
        }
        return events
    }
}
