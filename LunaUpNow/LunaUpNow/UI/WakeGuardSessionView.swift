//
//  WakeGuardSessionView.swift
//  LunaUpNow
//
//  The active Wake Guard screen. Shows current stage, stage + total progress,
//  time since the alarm began, time remaining before Missed, and the next
//  follow-up time. No success UI appears until every required stage is done.
//

import SwiftUI

struct WakeGuardSessionView: View {
    @Environment(WakeGuardController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var answerText = ""
    @State private var shakeTrigger = 0
    @FocusState private var answerFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let session = controller.activeSession {
                activeBody(session)
            } else if let last = controller.resolvedSessions.first {
                ResolvedSessionView(session: last) { dismiss() }
            }
        }
        // tickCount dependency keeps countdowns live.
        .onChange(of: controller.tickCount) { _, _ in }
    }

    @ViewBuilder
    private func activeBody(_ session: WakeGuardSession) -> some View {
        let now = controller.clock.now
        ScrollView {
            VStack(spacing: 16) {
                header(session, now: now)
                if let stage = session.currentStage, stage.isAvailable {
                    challengeCard(session: session, stage: stage)
                } else {
                    waitingCard(session, now: now)
                }
                timeline(session)
                Text("The wake session is NOT complete yet. Wake Guard stays active until every stage is passed.")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ session: WakeGuardSession, now: Date) -> some View {
        VStack(spacing: 10) {
            HStack {
                Chip(text: "Wake Guard active", icon: "shield.lefthalf.filled", color: Theme.accent, filled: true)
                Spacer()
                Chip(text: session.configuration.preset?.displayName ?? "Custom",
                     icon: "flame.fill", color: Theme.accentSoft)
            }
            Text("Stage \(min(session.currentStageIndex + 1, session.stages.count)) of \(session.stages.count)")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text(session.currentStage?.plan.kind.title ?? "")
                .font(.headline)
                .foregroundStyle(Theme.accentSoft)

            // Total Wake Guard progress: correct answers across all stages.
            let total = session.stages.reduce(0) { $0 + $1.plan.questionCount }
            let done = session.stages.reduce(0) { $0 + min($1.correctAnswers, $1.plan.questionCount) }
            ProgressView(value: Double(done), total: Double(total))
                .tint(Theme.accent)

            HStack {
                statPill("Since alarm", formatDuration(now.timeIntervalSince(session.sessionStart)))
                statPill("Marked Missed in", formatDuration(session.maxExpiration.timeIntervalSince(now)))
            }
            Text("Session ends at \(session.maxExpiration.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
    }

    private func challengeCard(session: WakeGuardSession, stage: StageRecord) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Question \(min(stage.correctAnswers + 1, stage.plan.questionCount)) of \(stage.plan.questionCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if stage.ignoredAt != nil {
                    Chip(text: "Check was ignored", icon: "exclamationmark.triangle.fill", color: Theme.danger)
                }
            }
            if let question = WakeGuardEngine.activeQuestion(in: session) {
                Text(question.prompt)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

                TextField("Answer", text: $answerText)
                    .keyboardType(.numberPad)
                    .focused($answerFocused)
                    .multilineTextAlignment(.center)
                    .font(.title2.weight(.semibold))
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                    .onAppear { answerFocused = true }

                Button {
                    submit(question)
                } label: {
                    Text("Submit")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                        .foregroundStyle(.black)
                }
                .disabled(Int(answerText) == nil)
            }
        }
        .card()
    }

    private func submit(_ question: Question) {
        guard let value = Int(answerText) else { return }
        let correct = controller.submitAnswer(value, questionID: question.id)
        answerText = ""
        if !correct {
            withAnimation(.default) { shakeTrigger += 1 }
        }
    }

    private func waitingCard(_ session: WakeGuardSession, now: Date) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text(session.currentStageIndex > 0 && session.stages[session.currentStageIndex - 1].plan.kind == .mainChallenge
                 ? "Main challenge complete" : "Stage complete")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Do not go back to sleep.")
                .font(.headline)
                .foregroundStyle(Theme.warning)
            if let unlock = session.nextStageUnlockDate() {
                Text("Your next check begins in \(formatDuration(unlock.timeIntervalSince(now)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func timeline(_ session: WakeGuardSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stages").font(.headline).foregroundStyle(.white)
            ForEach(Array(session.stages.enumerated()), id: \.offset) { idx, stage in
                HStack(spacing: 10) {
                    Image(systemName: stage.isComplete ? "checkmark.circle.fill"
                          : stage.isAvailable ? "circle.dashed.inset.filled" : "lock.circle")
                        .foregroundStyle(stage.isComplete ? Theme.success
                                         : stage.isAvailable ? Theme.accent : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stage.plan.kind.title).font(.subheadline).foregroundStyle(.white)
                        Text(stageSubtitle(stage, index: idx, session: session))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if stage.ignoredAt != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    }
                }
            }
        }
        .card()
    }

    private func stageSubtitle(_ stage: StageRecord, index: Int, session: WakeGuardSession) -> String {
        if let completed = stage.completedAt {
            return "Completed \(completed.formatted(date: .omitted, time: .shortened))"
        }
        if stage.isAvailable {
            return "\(stage.correctAnswers)/\(stage.plan.questionCount) answered"
        }
        if let unlock = session.nextStageUnlockDate(), index == session.currentStageIndex {
            return "Unlocks at \(unlock.formatted(date: .omitted, time: .shortened))"
        }
        return "\(stage.plan.questionCount) questions • locked"
    }
}

// MARK: - Resolved

struct ResolvedSessionView: View {
    let session: WakeGuardSession
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            let success = session.outcome?.isSuccess == true
            Image(systemName: success ? "sun.max.fill" : "moon.zzz.fill")
                .font(.system(size: 60))
                .foregroundStyle(success ? Theme.accent : Theme.danger)
            Text(success ? "You're up. Wake Guard complete." : (session.outcome?.displayName ?? ""))
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if session.outcome == .completedLate {
                Text("Completed, but later than your target. It still counts.")
                    .foregroundStyle(.secondary)
            }
            if let completed = session.completedAt {
                Text("Finished \(formatDuration(completed.timeIntervalSince(session.sessionStart))) after the alarm")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button("Done") { onDismiss() }
                .font(.headline)
                .padding(.horizontal, 40).padding(.vertical, 14)
                .background(Capsule().fill(Theme.accent))
                .foregroundStyle(.black)
        }
        .padding()
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
