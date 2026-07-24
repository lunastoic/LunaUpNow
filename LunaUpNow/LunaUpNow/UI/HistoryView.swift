//
//  HistoryView.swift
//  LunaUpNow
//

import SwiftUI

struct HistoryView: View {
    @Environment(WakeGuardController.self) private var controller

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("See how consistently you wake up")
                        .font(.subheadline).foregroundStyle(.secondary)

                    summaryRow

                    Text("Recent Sessions").font(.headline).foregroundStyle(.white)
                    if controller.resolvedSessions.isEmpty {
                        Text("No completed Wake Guard sessions yet.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).card()
                    }
                    ForEach(controller.resolvedSessions.prefix(30)) { session in
                        sessionRow(session)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Wake History")
        }
    }

    private var summaryRow: some View {
        let stats = controller.stats
        return HStack(spacing: 10) {
            summaryTile(title: "Avg wake-up time",
                        value: stats.averageTimeToComplete.map(formatDuration) ?? "—",
                        icon: "clock.fill", color: Theme.accent)
            summaryTile(title: "Completion rate",
                        value: completionRateText,
                        icon: "checkmark.seal.fill", color: Theme.warning)
            summaryTile(title: "Current streak",
                        value: "\(stats.streakDays) day\(stats.streakDays == 1 ? "" : "s")",
                        icon: "flame.fill", color: Theme.danger)
        }
    }

    private var completionRateText: String {
        let finished = controller.resolvedSessions
        guard !finished.isEmpty else { return "—" }
        let ok = finished.filter { $0.outcome?.isSuccess == true }.count
        return "\(Int(Double(ok) / Double(finished.count) * 100))%"
    }

    private func summaryTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.headline).foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    private func sessionRow(_ session: WakeGuardSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.scheduledWakeTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("Alarm \(session.scheduledWakeTime.formatted(date: .omitted, time: .shortened)) • \(session.completedStageCount)/\(session.stages.count) stages")
                    .font(.caption).foregroundStyle(.secondary)
                if session.escalationCount > 0 {
                    Text("\(session.escalationCount) escalation\(session.escalationCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let completed = session.completedAt {
                    Text(formatDuration(completed.timeIntervalSince(session.sessionStart)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.outcome == .completed ? Theme.success : Theme.warning)
                }
                outcomeBadge(session.outcome)
            }
        }
        .card(padding: 14)
    }

    private func outcomeBadge(_ outcome: WakeGuardOutcome?) -> some View {
        let (color, text): (Color, String) = switch outcome {
        case .completed: (Theme.success, "Completed")
        case .completedLate: (Theme.warning, "Late")
        case .followUpFailed: (Theme.warning, "Follow-up Failed")
        case .missed: (Theme.danger, "Missed")
        case .interrupted: (.secondary, "Interrupted")
        case nil: (.secondary, "—")
        }
        return Chip(text: text, color: color, filled: true)
    }
}
