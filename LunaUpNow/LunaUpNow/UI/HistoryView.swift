//
//  HistoryView.swift
//  LunaUpNow
//
//  Wake history per the WakeProof mockups: period picker, wake-up-time line
//  chart, recent sessions table, completion/streak tiles, and an insight card.
//

import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(WakeGuardController.self) private var controller
    @State private var period: Period = .week

    private enum Period: String, CaseIterable {
        case week = "Week", month = "Month", all = "All"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("See how consistently you wake up")
                        .font(.subheadline).foregroundStyle(.secondary)

                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    chartCard
                    sessionsCard

                    HStack(spacing: 10) {
                        completionRateTile
                        streakTile
                    }

                    insightCard
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Wake History")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .tint(Theme.accent)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chartTitle)
                        .font(.headline).foregroundStyle(.white)
                    Text("Wake-up time (min)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Capsule().fill(Theme.accent).frame(width: 14, height: 3)
                    Text("Minutes to get up")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Chart(chartPoints, id: \.date) { point in
                LineMark(x: .value("Day", point.date, unit: .day),
                         y: .value("Minutes", point.minutes))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Day", point.date, unit: .day),
                         y: .value("Minutes", point.minutes))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", point.date, unit: .day),
                          y: .value("Minutes", point.minutes))
                    .foregroundStyle(Theme.accentSoft)
                    .symbolSize(30)
            }
            .frame(height: 160)
            .chartYScale(domain: 0...max(6, (chartPoints.map(\.minutes).max() ?? 0) + 1))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes)) min")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Label(trendNote, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.accentSoft)
        }
        .card()
    }

    private var chartTitle: String {
        switch period {
        case .week: "This Week"
        case .month: "This Month"
        case .all: "All Time"
        }
    }

    private struct ChartPoint {
        let date: Date
        let minutes: Double
    }

    private var chartPoints: [ChartPoint] {
        let cal = Calendar.current
        var byDay: [Date: [TimeInterval]] = [:]
        for session in filteredSessions where session.outcome?.isSuccess == true {
            guard let completed = session.completedAt else { continue }
            let day = cal.startOfDay(for: session.sessionStart)
            byDay[day, default: []].append(completed.timeIntervalSince(session.sessionStart))
        }
        return byDay.keys.sorted().map { day in
            let durations = byDay[day] ?? []
            return ChartPoint(date: day, minutes: durations.reduce(0, +) / Double(durations.count) / 60)
        }
    }

    private var trendNote: String {
        let points = chartPoints
        guard points.count >= 2, let first = points.first, let last = points.last else {
            return "Lower is better. Complete more sessions to see a trend."
        }
        return last.minutes <= first.minutes
            ? "Lower is better. You're improving!"
            : "Lower is better. Recent mornings took a bit longer."
    }

    // MARK: - Sessions table

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Sessions")
                .font(.headline).foregroundStyle(.white)
                .padding(.bottom, 10)

            HStack {
                Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                Text("Alarm").frame(width: 62, alignment: .leading)
                Text("Time to get up").frame(width: 78, alignment: .leading)
                Text("Result").frame(width: 86, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)

            if filteredSessions.isEmpty {
                Text("No completed Wake Guard sessions yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }

            ForEach(Array(filteredSessions.prefix(8).enumerated()), id: \.element.id) { index, session in
                if index > 0 { Divider().background(Theme.stroke) }
                sessionTableRow(session)
            }

            if !filteredSessions.isEmpty {
                Divider().background(Theme.stroke)
                HStack {
                    Text("Avg wake-up time")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(periodAverage.map(formatDuration) ?? "—")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 10)
            }
        }
        .card()
    }

    private func sessionTableRow(_ session: WakeGuardSession) -> some View {
        let (icon, color) = statusIcon(session.outcome)
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(session.scheduledWakeTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(session.scheduledWakeTime.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(durationText(session))
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.outcome == .completed ? Theme.success : .white)
                .frame(width: 78, alignment: .leading)

            resultBadge(session.outcome)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private func statusIcon(_ outcome: WakeGuardOutcome?) -> (String, Color) {
        switch outcome {
        case .completed: ("checkmark.circle.fill", Theme.success)
        case .completedLate, .followUpFailed: ("clock.fill", Theme.warning)
        case .missed: ("xmark.circle.fill", Theme.danger)
        case .interrupted, nil: ("minus.circle.fill", .secondary)
        }
    }

    private func durationText(_ session: WakeGuardSession) -> String {
        guard let completed = session.completedAt else { return "—" }
        return formatDuration(completed.timeIntervalSince(session.sessionStart))
    }

    private func resultBadge(_ outcome: WakeGuardOutcome?) -> some View {
        let (color, text): (Color, String) = switch outcome {
        case .completed: (Theme.success, "Completed")
        case .completedLate: (Theme.warning, "Slow")
        case .followUpFailed: (Theme.warning, "Slow")
        case .missed: (Theme.danger, "Missed")
        case .interrupted: (.secondary, "Stopped")
        case nil: (.secondary, "—")
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
            .foregroundStyle(color)
    }

    // MARK: - Tiles & insight

    private var completionRateTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Completion rate", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.secondary)
            Text(completionRateText)
                .font(.title3.bold()).foregroundStyle(.white)
            ProgressView(value: completionRate)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private var streakTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current streak", systemImage: "flame.fill")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(controller.stats.streakDays) day\(controller.stats.streakDays == 1 ? "" : "s")")
                .font(.title3.bold()).foregroundStyle(.white)
            Text("Keep it going!")
                .font(.caption2).foregroundStyle(Theme.accentSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private var insightCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(insightTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(insightSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.25)))
    }

    private var insightTitle: String {
        if controller.resolvedSessions.isEmpty { return "No sessions yet." }
        if let first = chartPoints.first, let last = chartPoints.last, chartPoints.count >= 2, last.minutes < first.minutes {
            return "You're getting up faster this \(period == .month ? "month" : "week")."
        }
        return "Consistency is building."
    }

    private var insightSubtitle: String {
        controller.resolvedSessions.isEmpty ? "Set an alarm to start tracking." : "Keep the streak going."
    }

    // MARK: - Plumbing

    private var filteredSessions: [WakeGuardSession] {
        let cal = Calendar.current
        let now = controller.clock.now
        switch period {
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return controller.resolvedSessions }
            return controller.resolvedSessions.filter { interval.contains($0.sessionStart) }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return controller.resolvedSessions }
            return controller.resolvedSessions.filter { interval.contains($0.sessionStart) }
        case .all:
            return controller.resolvedSessions
        }
    }

    private var periodAverage: TimeInterval? {
        let durations = filteredSessions.compactMap { s -> TimeInterval? in
            guard s.outcome?.isSuccess == true, let completed = s.completedAt else { return nil }
            return completed.timeIntervalSince(s.sessionStart)
        }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    private var completionRate: Double {
        let finished = filteredSessions
        guard !finished.isEmpty else { return 0 }
        let ok = finished.filter { $0.outcome?.isSuccess == true }.count
        return Double(ok) / Double(finished.count)
    }

    private var completionRateText: String {
        filteredSessions.isEmpty ? "—" : "\(Int(completionRate * 100))%"
    }
}
