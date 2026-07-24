//
//  AlarmsView.swift
//  LunaUpNow
//

import SwiftUI

struct AlarmsView: View {
    @Environment(WakeGuardController.self) private var controller
    @State private var editingAlarm: AlarmConfig?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if controller.alarms.isEmpty {
                        Text("No alarms yet. One alarm is all Wake Guard needs.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .card()
                    }
                    ForEach(controller.alarms) { alarm in
                        alarmRow(alarm)
                            .contentShape(Rectangle())
                            .onTapGesture { editingAlarm = alarm }
                    }
                    Button { showingNew = true } label: {
                        Label("New Alarm", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Your Alarms")
            .sheet(item: $editingAlarm) { AlarmEditView(alarm: $0) }
            .sheet(isPresented: $showingNew) { AlarmEditView(alarm: nil) }
        }
    }

    private func alarmRow(_ alarm: AlarmConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(alarm.timeText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(alarm.isEnabled ? .white : .secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { controller.setAlarmEnabled(alarm, enabled: $0) }))
                .labelsHidden()
                .tint(Theme.accent)
            }
            Text(repeatText(alarm))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                let config = alarm.configuration
                Chip(text: alarm.preset.displayName, icon: "flame.fill",
                     color: alarm.isEnabled ? Theme.accent : .secondary)
                Chip(text: "\(config.stages.first?.questionCount ?? 0) questions", icon: "questionmark.circle",
                     color: .secondary)
                Chip(text: "\(config.stages.count) stages", icon: "shield.lefthalf.filled", color: .secondary)
                if alarm.isEnabled {
                    Chip(text: "Armed", icon: "shield.fill", color: Theme.accent, filled: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func repeatText(_ alarm: AlarmConfig) -> String {
        if alarm.repeatDays.isEmpty { return "One time" }
        if alarm.repeatDays.count == 7 { return "Every day" }
        return alarm.repeatDays.sorted().map(\.shortName).joined(separator: " • ")
    }
}

// MARK: - Editor

struct AlarmEditView: View {
    @Environment(WakeGuardController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    private let existing: AlarmConfig?
    @State private var time: Date
    @State private var repeatDays: Set<Weekday>
    @State private var preset: WakeGuardModePreset
    @State private var difficulty: QuestionDifficulty

    init(alarm: AlarmConfig?) {
        existing = alarm
        let comps = DateComponents(hour: alarm?.hour ?? 7, minute: alarm?.minute ?? 0)
        _time = State(initialValue: Calendar.current.date(from: comps) ?? Date())
        _repeatDays = State(initialValue: alarm?.repeatDays ?? [.monday, .tuesday, .wednesday, .thursday, .friday])
        _preset = State(initialValue: alarm?.preset ?? .heavySleeper)
        _difficulty = State(initialValue: alarm?.difficulty ?? .balanced)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Wake time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                } header: { Text("Time") }

                Section("Repeat") {
                    HStack {
                        ForEach(Weekday.allCases.sorted(), id: \.self) { day in
                            let on = repeatDays.contains(day)
                            Text(day.shortName)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(on ? Theme.accent.opacity(0.3) : Theme.cardElevated))
                                .foregroundStyle(on ? Theme.accentSoft : .secondary)
                                .onTapGesture {
                                    if on { repeatDays.remove(day) } else { repeatDays.insert(day) }
                                }
                        }
                    }
                }

                Section {
                    Picker("Mode", selection: $preset) {
                        ForEach(WakeGuardModePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(QuestionDifficulty.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    let config = WakeGuardConfiguration.preset(preset, difficulty: difficulty)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(config.stages.enumerated()), id: \.offset) { idx, stage in
                            Text("Stage \(idx + 1): \(stage.summary)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Unresolved window: up to \(Int(config.maxWindow / 60)) minutes, then the session is marked Missed.")
                            .font(.caption).foregroundStyle(Theme.warning)
                        Text("One alarm starts one persistent Wake Guard session. Follow-up alerts are derived automatically — you never create extra alarms.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Wake Guard") }

                if existing != nil {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            if let existing { controller.deleteAlarm(existing) }
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existing == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        var alarm = existing ?? AlarmConfig(hour: 7, minute: 0)
        alarm.hour = comps.hour ?? 7
        alarm.minute = comps.minute ?? 0
        alarm.repeatDays = repeatDays
        alarm.preset = preset
        alarm.difficulty = difficulty
        if existing == nil {
            controller.addAlarm(alarm)
        } else {
            controller.updateAlarm(alarm)
        }
        dismiss()
    }
}

private extension StagePlan {
    var summary: String {
        let delay = delayAfterPreviousStage > 0 ? " (+\(Int(delayAfterPreviousStage / 60)) min)" : ""
        return "\(kind.title) — \(questionCount) question\(questionCount == 1 ? "" : "s")\(delay)"
    }
}
