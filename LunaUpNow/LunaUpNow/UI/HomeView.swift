//
//  HomeView.swift
//  LunaUpNow
//

import SwiftUI

struct HomeView: View {
    @Environment(WakeGuardController.self) private var controller
    @State private var showingNewAlarm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(greeting)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Here's your next alarm and wake insights")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    nextAlarmCard

                    if let error = controller.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .card()
                    }

                    statsCard

                    Button { showingNewAlarm = true } label: {
                        Label("Create Alarm", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                            .foregroundStyle(.black)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showingNewAlarm) { AlarmEditView(alarm: nil) }
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

    @ViewBuilder
    private var nextAlarmCard: some View {
        if let next = controller.nextAlarm {
            VStack(alignment: .leading, spacing: 12) {
                Label("Next Alarm", systemImage: "alarm.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(next.alarm.timeText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases.sorted(), id: \.self) { day in
                        Text(day.shortName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(next.alarm.repeatDays.contains(day) ? Theme.accent.opacity(0.25) : Theme.cardElevated))
                            .foregroundStyle(next.alarm.repeatDays.contains(day) ? Theme.accentSoft : .secondary)
                    }
                }
                HStack {
                    Chip(text: "Armed", icon: "shield.fill", color: Theme.accent, filled: true)
                    Chip(text: "No Snooze", icon: "bell.slash.fill", color: Theme.accentSoft)
                    Chip(text: next.alarm.preset.displayName, icon: "flame.fill", color: Theme.warning)
                }
                Text("One alarm → one persistent Wake Guard session (\(Int(next.alarm.configuration.maxWindow / 60)) min window, \(next.alarm.configuration.stages.count) stages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.sunriseGradient))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke))
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

    private var statsCard: some View {
        let stats = controller.stats
        return VStack(alignment: .leading, spacing: 12) {
            Text("Wake Stats").font(.headline).foregroundStyle(.white)
            HStack {
                statTile(value: stats.onTimeRate.map { "\(Int($0 * 100))%" } ?? "—",
                         label: "On-time Rate", icon: "alarm.fill")
                statTile(value: "\(stats.totalAlarms)", label: "Alarms", icon: "chart.bar.fill")
                statTile(value: stats.averageTimeToComplete.map(formatDuration) ?? "—",
                         label: "Avg Wake-up", icon: "clock.fill")
                statTile(value: "\(stats.streakDays)", label: "Streak", icon: "flame.fill")
            }
        }
        .card()
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.accent)
            Text(value).font(.subheadline.bold()).foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
