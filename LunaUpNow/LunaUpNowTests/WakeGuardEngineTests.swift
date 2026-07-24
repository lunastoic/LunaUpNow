//
//  WakeGuardEngineTests.swift
//  LunaUpNowTests
//
//  Pure state-machine tests: stage transitions, expiration, ignored checks,
//  completion gating, late completion, missed marking.
//

import Foundation
import Testing
@testable import LunaUpNow

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func makeAlarm(preset: WakeGuardModePreset = .heavySleeper) -> AlarmConfig {
    AlarmConfig(hour: 7, minute: 25, preset: preset)
}

private func startSession(preset: WakeGuardModePreset = .heavySleeper) -> WakeGuardSession {
    WakeGuardEngine.startSession(alarm: makeAlarm(preset: preset), scheduledWakeTime: t0, now: t0).0
}

/// Answer every remaining question of the currently available stage correctly.
private func passCurrentStage(_ session: inout WakeGuardSession, at now: Date) {
    while let q = WakeGuardEngine.activeQuestion(in: session) {
        let (correct, _) = WakeGuardEngine.submitAnswer(q.answer, to: q.id, session: &session, now: now)
        #expect(correct)
    }
}

struct StageTransitionTests {

    @Test func firstStageUnlocksImmediatelyWithGeneratedQuestions() {
        let session = startSession()
        #expect(session.currentStageIndex == 0)
        #expect(session.stages[0].isAvailable)
        #expect(session.stages[0].questions.count == 5)
        #expect(session.stages[1].availableAt == nil)
    }

    @Test func stageTwoUnlocksOnlyAfterConfiguredDelay() {
        var session = startSession()
        passCurrentStage(&session, at: t0.addingTimeInterval(30))
        #expect(session.stages[0].isComplete)
        #expect(session.currentStageIndex == 1)

        // 1 minute after stage 1: still locked (delay is 2 minutes).
        WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(30 + 60))
        #expect(!session.stages[1].isAvailable)

        // 2 minutes after stage 1 completion: unlocked, questions generated.
        let events = WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(30 + 120))
        #expect(events.contains(.stageUnlocked(index: 1)))
        #expect(session.stages[1].isAvailable)
        #expect(session.stages[1].questions.count == 2)
    }

    @Test func heavySleeperRunsThreeStagesInOrder() {
        var session = startSession(preset: .heavySleeper)
        #expect(session.stages.count == 3)

        var now = t0.addingTimeInterval(60)
        passCurrentStage(&session, at: now)

        now = now.addingTimeInterval(120)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)

        now = now.addingTimeInterval(300)
        WakeGuardEngine.tick(&session, now: now)
        #expect(session.stages[2].isAvailable)
        #expect(session.stages[2].questions.count == 1)
        passCurrentStage(&session, at: now)
        #expect(session.outcome == .completed)
    }

    @Test func wrongAnswersDoNotAdvanceProgress() {
        var session = startSession()
        let q = WakeGuardEngine.activeQuestion(in: session)!
        let (correct, _) = WakeGuardEngine.submitAnswer(q.answer + 1, to: q.id, session: &session, now: t0)
        #expect(!correct)
        #expect(session.stages[0].correctAnswers == 0)
        #expect(session.stages[0].failedAttempts == 1)
    }

    @Test func questionsRegenerateDeterministicallyForSameSessionAndStage() {
        let seed = QuestionGenerator.seed(sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, stageIndex: 1)
        let a = QuestionGenerator.questions(count: 5, difficulty: .balanced, seed: seed)
        let b = QuestionGenerator.questions(count: 5, difficulty: .balanced, seed: seed)
        #expect(a == b)
    }
}

struct CompletionGatingTests {

    @Test func sessionNotSuccessfulUntilAllRequiredStagesPass() {
        var session = startSession()
        passCurrentStage(&session, at: t0.addingTimeInterval(60))
        #expect(session.outcome == nil) // main challenge done ≠ session done

        var now = t0.addingTimeInterval(60 + 120)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)
        #expect(session.outcome == nil) // stage 2 done, stage 3 still pending

        now = now.addingTimeInterval(300)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)
        #expect(session.outcome == .completed)
        #expect(session.completedAt != nil)
    }

    @Test func finishingAfterLateThresholdIsCompletedLate() {
        var session = startSession() // heavy sleeper: lateThreshold 30 min
        var now = t0.addingTimeInterval(35 * 60)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)

        now = now.addingTimeInterval(120)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)

        now = now.addingTimeInterval(300)
        WakeGuardEngine.tick(&session, now: now)
        passCurrentStage(&session, at: now)

        #expect(session.outcome == .completedLate)
        #expect(session.outcome?.isSuccess == true)
    }
}

struct ExpirationTests {

    @Test func threeHourNuclearWindowExpiresAsMissedWhenNothingCompleted() {
        var session = startSession(preset: .nuclear)
        #expect(session.maxExpiration == t0.addingTimeInterval(3 * 3600))

        // One second before expiry: still unresolved.
        WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(3 * 3600 - 1))
        #expect(session.outcome == nil)

        let events = WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(3 * 3600))
        #expect(session.outcome == .missed)
        #expect(events.contains(.sessionResolved(.missed)))
    }

    @Test func expiryAfterMainChallengeIsFollowUpFailed() {
        var session = startSession()
        passCurrentStage(&session, at: t0.addingTimeInterval(60))
        WakeGuardEngine.tick(&session, now: session.maxExpiration)
        #expect(session.outcome == .followUpFailed)
    }

    @Test func maxWindowNeverExceedsThreeHours() {
        let config = WakeGuardConfiguration(preset: nil,
                                            stages: [StagePlan(kind: .mainChallenge, questionCount: 1,
                                                               delayAfterPreviousStage: 0, responseWindow: 600)],
                                            maxWindow: 12 * 3600, // absurd custom value
                                            lateThreshold: 600,
                                            escalationAlertOffsets: [],
                                            supportingReminderOffsets: [],
                                            difficulty: .balanced)
        #expect(config.maxWindow == 3 * 3600)
    }

    @Test func resolvedSessionIgnoresFurtherTicks() {
        var session = startSession(preset: .standard)
        WakeGuardEngine.tick(&session, now: session.maxExpiration)
        #expect(session.outcome == .missed)
        let events = WakeGuardEngine.tick(&session, now: session.maxExpiration.addingTimeInterval(9999))
        #expect(events.isEmpty)
        #expect(session.outcome == .missed)
    }
}

struct IgnoredCheckTests {

    @Test func unansweredStageIsMarkedIgnoredAfterResponseWindow() {
        var session = startSession()
        let window = session.stages[0].plan.responseWindow
        let events = WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(window))
        #expect(events.contains(.stageIgnored(index: 0)))
        #expect(session.stages[0].ignoredAt != nil)
        #expect(session.escalationCount == 1)
    }

    @Test func ignoredStageCanStillBeCompletedBeforeExpiry() {
        var session = startSession()
        let window = session.stages[0].plan.responseWindow
        WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(window + 60))
        #expect(session.stages[0].ignoredAt != nil)
        passCurrentStage(&session, at: t0.addingTimeInterval(window + 120))
        #expect(session.stages[0].isComplete)
        #expect(session.outcome == nil) // later stages still required
    }

    @Test func ignoredIsRecordedOncePerStage() {
        var session = startSession()
        let window = session.stages[0].plan.responseWindow
        WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(window))
        WakeGuardEngine.tick(&session, now: t0.addingTimeInterval(window + 600))
        #expect(session.escalationCount == 1)
    }
}

struct InterruptionTests {

    @Test func interruptResolvesSessionAsInterrupted() {
        var session = startSession()
        let events = WakeGuardEngine.interrupt(&session)
        #expect(session.outcome == .interrupted)
        #expect(events == [.sessionResolved(.interrupted)])
        #expect(WakeGuardEngine.interrupt(&session).isEmpty) // idempotent
    }
}
