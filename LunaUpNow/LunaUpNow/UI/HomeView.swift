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
    @State private var showingWakePlan = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                appHeader
                greetingBlock
                nextAlarmCard

                if let error = controller.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .card(padding: 10)
                }

                difficultyRow
                statsCard
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewAlarm) { AlarmEditView(alarm: nil) }
            .sheet(item: $editingAlarm) { AlarmEditView(alarm: $0) }
            .sheet(isPresented: $showingWakePlan) {
                if let alarm = controller.nextAlarm?.alarm ?? controller.alarms.first {
                    WakePlanSheet(alarm: alarm)
                }
            }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("Tomorrow's wake-up plan")
                .font(.caption)
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

                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        let (time, ampm) = timeParts(next.alarm)
                        Text(time)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(ampm)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    heroIconButton(icon: "pencil", label: "Edit alarm") {
                        editingAlarm = next.alarm
                    }
                    heroIconButton(icon: "plus", label: "Add alarm") {
                        showingNewAlarm = true
                    }
                }

                DayChipRow(activeDays: next.alarm.repeatDays) { day in
                    toggleRepeatDay(day, of: next.alarm)
                }

                Button { showingWakePlan = true } label: {
                    HStack(spacing: 12) {
                        heroInfoTile(icon: "alarm.fill",
                                     value: "\(config.stages.first?.questionCount ?? 0)",
                                     label: "Questions")
                        heroInfoTile(icon: "clock.fill",
                                     value: "Follow-up",
                                     label: followUpLabel(config))
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accentSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wake plan details")
                .accessibilityHint("Shows check-ins and follow-up alerts for this alarm.")
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
            VStack(spacing: 10) {
                Image(systemName: "alarm").font(.title).foregroundStyle(.secondary)
                Text("No alarm scheduled").foregroundStyle(.white)
                Text("Create one alarm — Wake Guard handles the rest.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { showingNewAlarm = true } label: {
                    Label("Add Alarm", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .card()
        }
    }

    private func heroIconButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.25)))
                .overlay(Circle().stroke(Theme.accent.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    // MARK: - Difficulty

    @ViewBuilder
    private var difficultyRow: some View {
        if let alarm = controller.nextAlarm?.alarm ?? controller.alarms.first {
            HStack(spacing: 8) {
                Text("Difficulty")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                ForEach(QuestionDifficulty.allCases, id: \.self) { level in
                    let selected = alarm.difficulty == level
                    Button {
                        var updated = alarm
                        updated.difficulty = level
                        controller.updateAlarm(updated)
                    } label: {
                        Text(level.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selected ? .black : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selected ? Theme.accent : Theme.cardElevated))
                            .overlay { if !selected { Capsule().stroke(Theme.stroke) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(level.displayName) difficulty\(selected ? ", selected" : "")")
                }
            }
            .animation(.easeOut(duration: 0.15), value: alarm.difficulty)
            .card(padding: 12)
        }
    }

    // MARK: - Wake stats

    private var statsCard: some View {
        let stats = controller.stats
        return VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 5) {
                    Label("Avg wake-up time", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stats.averageTimeToComplete.map(formatDuration) ?? "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
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

            VStack(alignment: .leading, spacing: 5) {
                weeklyBarChart
                    .frame(height: 80)
                Label("\(stats.streakDays)-day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentSoft)
            }
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
                .stroke(Color.white.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)/\(total)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
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

// MARK: - Wake plan sheet

/// Pull-up detail for the hero card's Questions / Follow-up tiles: the full
/// plan behind the alarm — every check-in, and what happens if one is ignored.
private struct WakePlanSheet: View {
    let alarm: AlarmConfig

    var body: some View {
        let config = alarm.configuration
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Wake Plan")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Text("\(alarm.preset.displayName) mode · \(alarm.difficulty.displayName) questions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: modeIcon)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.15)))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("CHECK-INS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentSoft)
                    ForEach(Array(config.stages.enumerated()), id: \.offset) { index, stage in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.accent))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(stageDetail(stage, isFirst: index == 0))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("IF YOU IGNORE A CHECK-IN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentSoft)
                    Label(followUpSummary(config), systemImage: "bell.badge.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Label("The session stays active for up to \(Int(config.maxWindow / 60)) minutes — dismissing an alert never ends it.",
                          systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding(20)
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    private var modeIcon: String {
        switch alarm.preset {
        case .standard: "sun.max.fill"
        case .heavySleeper: "moon.zzz.fill"
        case .nuclear: "flame.fill"
        }
    }

    private func stageDetail(_ stage: StagePlan, isFirst: Bool) -> String {
        let questions = "\(stage.questionCount) question\(stage.questionCount == 1 ? "" : "s")"
        let unlock = isFirst
            ? "Starts when the alarm rings."
            : "Unlocks \(Int(stage.delayAfterPreviousStage / 60)) min after the previous check-in."
        return "\(questions) · \(unlock) Answer within \(Int(stage.responseWindow / 60)) min."
    }

    private func followUpSummary(_ config: WakeGuardConfiguration) -> String {
        let minutes = config.escalationAlertOffsets.map { "\(Int($0 / 60))" }
        guard !minutes.isEmpty else { return "No follow-up alerts for this mode." }
        return "Follow-up alarms fire \(minutes.joined(separator: ", ")) min after wake time until you finish."
    }
}
