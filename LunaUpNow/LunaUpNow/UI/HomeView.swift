//
//  HomeView.swift
//  LunaUpNow
//
//  Dashboard per the WakeProof mockups: greeting, hero next-alarm card,
//  quick actions, quick settings, and wake stats with a weekly bar chart.
//

import SwiftUI
import Charts

struct HomeView: View {
    @Environment(WakeGuardController.self) private var controller
    @Binding var selectedTab: Int

    @State private var showingNewAlarm = false
    @State private var editingAlarm: AlarmConfig?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appHeader
                    greetingBlock
                    nextAlarmCard

                    if let error = controller.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .card()
                    }

                    actionButtons
                    quickSettingsSection
                    statsCard
                }
                .padding()
            }
            .background(Theme.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewAlarm) { AlarmEditView(alarm: nil) }
            .sheet(item: $editingAlarm) { AlarmEditView(alarm: $0) }
        }
    }

    // MARK: - Header

    private var appHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill")
                .font(.subheadline)
                .foregroundStyle(.black)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent))
            Text("LunaUpNow")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "moon.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Tomorrow's wake-up plan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: controller.clock.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Next alarm hero card

    @ViewBuilder
    private var nextAlarmCard: some View {
        if let next = controller.nextAlarm {
            let config = next.alarm.configuration
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("NEXT ALARM", systemImage: "alarm.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentSoft)
                    Spacer()
                    Chip(text: "Armed", icon: "checkmark", color: Theme.accent, filled: true)
                    Chip(text: "No Snooze", icon: "bell.slash.fill", color: Theme.accentSoft)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    let (time, ampm) = timeParts(next.alarm)
                    Text(time)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(ampm)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                DayChipRow(activeDays: next.alarm.repeatDays) { day in
                    toggleRepeatDay(day, of: next.alarm)
                }

                HStack(spacing: 12) {
                    heroInfoTile(icon: "alarm.fill",
                                 value: "\(config.stages.first?.questionCount ?? 0)",
                                 label: "Questions")
                    heroInfoTile(icon: "clock.fill",
                                 value: "Follow-up",
                                 label: followUpLabel(config))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.sunriseGradient)
                    Image(systemName: "sun.haze.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(Theme.accent.opacity(0.15))
                        .offset(x: -12, y: -8)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.25)))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "alarm").font(.title).foregroundStyle(.secondary)
                Text("No alarm scheduled").foregroundStyle(.white)
                Text("Create one alarm — Wake Guard handles the rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .card()
        }
    }

    private func heroInfoTile(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func followUpLabel(_ config: WakeGuardConfiguration) -> String {
        guard config.stages.count > 1 else { return "None" }
        let delay = Int(config.stages[1].delayAfterPreviousStage / 60)
        return delay > 0 ? "Check in \(delay) min" : "Right after"
    }

    private func timeParts(_ alarm: AlarmConfig) -> (String, String) {
        let ampm = alarm.hour >= 12 ? "PM" : "AM"
        var hour = alarm.hour % 12
        if hour == 0 { hour = 12 }
        return (String(format: "%d:%02d", hour, alarm.minute), ampm)
    }

    private func toggleRepeatDay(_ day: Weekday, of alarm: AlarmConfig) {
        var updated = alarm
        if updated.repeatDays.contains(day) {
            updated.repeatDays.remove(day)
        } else {
            updated.repeatDays.insert(day)
        }
        controller.updateAlarm(updated)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            actionButton(title: "Edit Alarm", icon: "pencil") {
                if let alarm = controller.nextAlarm?.alarm ?? controller.alarms.first {
                    editingAlarm = alarm
                } else {
                    showingNewAlarm = true
                }
            }
            actionButton(title: "Add Alarm", icon: "plus") {
                showingNewAlarm = true
            }
        }
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick settings

    private var quickSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Settings")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                let alarm = controller.nextAlarm?.alarm ?? controller.alarms.first
                quickSettingsTile(icon: "questionmark.circle.fill",
                                  label: "Questions",
                                  value: alarm.map { "\($0.configuration.stages.first?.questionCount ?? 0)" } ?? "—")
                quickSettingsTile(icon: "chart.bar.fill",
                                  label: "Difficulty",
                                  value: alarm?.difficulty.displayName ?? "—")
                quickSettingsTile(icon: "checkmark.circle.fill",
                                  label: "Follow-up",
                                  value: alarm != nil ? "On" : "—")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let alarm = controller.nextAlarm?.alarm ?? controller.alarms.first {
                    editingAlarm = alarm
                } else {
                    showingNewAlarm = true
                }
            }
        }
    }

    private func quickSettingsTile(icon: String, label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }

    // MARK: - Wake stats

    private var statsCard: some View {
        let stats = controller.stats
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Wake Stats")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("View all") { selectedTab = 2 }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Avg wake-up time", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stats.averageTimeToComplete.map(formatDuration) ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if let delta = weekOverWeekDelta {
                        Label(deltaText(delta), systemImage: delta <= 0 ? "arrow.down" : "arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delta <= 0 ? Theme.success : Theme.danger)
                    }
                }
                Spacer()
                completionRing
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Wake-up time (min)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                weeklyBarChart
                    .frame(height: 110)
                Label("\(stats.streakDays)-day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentSoft)
            }

            Label(insightText, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var completionRing: some View {
        let week = sessionsThisWeek
        let completed = week.filter { $0.outcome?.isSuccess == true }.count
        let total = week.count
        let progress = total > 0 ? Double(completed) / Double(total) : 0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)/\(total)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .overlay(alignment: .bottom) {
            Text("Alarms completed")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .offset(y: 18)
        }
        .padding(.bottom, 16)
    }

    private var weeklyBarChart: some View {
        let data = weeklyDurations
        return Chart(data, id: \.day) { entry in
            BarMark(
                x: .value("Day", entry.day.shortName),
                y: .value("Minutes", entry.minutes ?? 0)
            )
            .foregroundStyle(entry.minutes == nil ? Color.white.opacity(0.08) : Theme.accent)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var insightText: String {
        let stats = controller.stats
        if stats.totalAlarms == 0 || controller.resolvedSessions.isEmpty {
            return "Complete your first Wake Guard session to unlock insights."
        }
        if let delta = weekOverWeekDelta, delta < 0 {
            return "Great progress! You're getting up faster and more consistently."
        }
        if stats.streakDays >= 3 {
            return "Solid streak — consistency is what beats snoozing."
        }
        return "Every completed session makes the next morning easier."
    }

    // MARK: - Stats plumbing

    private struct DayDuration {
        let day: Weekday
        let minutes: Double?
    }

    private var sessionsThisWeek: [WakeGuardSession] {
        let cal = Calendar.current
        guard let startOfWeek = cal.dateInterval(of: .weekOfYear, for: controller.clock.now)?.start else { return [] }
        return controller.resolvedSessions.filter { $0.sessionStart >= startOfWeek }
    }

    private var weeklyDurations: [DayDuration] {
        let cal = Calendar.current
        var byDay: [Weekday: [TimeInterval]] = [:]
        for session in sessionsThisWeek where session.outcome?.isSuccess == true {
            guard let completed = session.completedAt,
                  let day = Weekday(rawValue: cal.component(.weekday, from: session.sessionStart)) else { continue }
            byDay[day, default: []].append(completed.timeIntervalSince(session.sessionStart))
        }
        return Weekday.allCases.sorted().map { day in
            let durations = byDay[day] ?? []
            let avg = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count) / 60
            return DayDuration(day: day, minutes: avg)
        }
    }

    /// Negative means faster than last week (a good thing).
    private var weekOverWeekDelta: TimeInterval? {
        let cal = Calendar.current
        let now = controller.clock.now
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now),
              let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeek.start) else { return nil }

        func average(in interval: DateInterval) -> TimeInterval? {
            let durations = controller.resolvedSessions.compactMap { s -> TimeInterval? in
                guard s.outcome?.isSuccess == true, let completed = s.completedAt,
                      interval.contains(s.sessionStart) else { return nil }
                return completed.timeIntervalSince(s.sessionStart)
            }
            guard !durations.isEmpty else { return nil }
            return durations.reduce(0, +) / Double(durations.count)
        }

        guard let current = average(in: thisWeek),
              let previous = average(in: DateInterval(start: lastWeekStart, end: thisWeek.start)) else { return nil }
        return current - previous
    }

    private func deltaText(_ delta: TimeInterval) -> String {
        let seconds = abs(Int(delta))
        let direction = delta <= 0 ? "faster" : "slower"
        return "\(seconds) sec \(direction) than last week"
    }
}
