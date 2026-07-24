//
//  SettingsView.swift
//  LunaUpNow
//
//  Mode explanations plus the simulator test controls required by the spec:
//  start Wake Guard immediately, advance virtual time, trigger stages,
//  simulate ignored checks, expiration, and AlarmKit scheduling failure.
//

import SwiftUI

struct SettingsView: View {
    @Environment(WakeGuardController.self) private var controller
    @State private var devPreset: WakeGuardModePreset = .heavySleeper
    @State private var failScheduling = false
    @State private var showDevTools = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick how tough your mornings should be")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    modesCard
                    difficultyCard
                    howItWorksCard

                    #if targetEnvironment(simulator) || DEBUG
                    devCard
                    #endif
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Settings")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
        .tint(Theme.accent)
    }

    // MARK: - Wake Guard modes

    private var modesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wake Guard Modes")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Set per alarm when you create or edit it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(WakeGuardModePreset.allCases, id: \.self) { preset in
                let config = WakeGuardConfiguration.preset(preset)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: modeIcon(preset))
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(modeSummary(config))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func modeIcon(_ preset: WakeGuardModePreset) -> String {
        switch preset {
        case .standard: "sun.max.fill"
        case .heavySleeper: "moon.zzz.fill"
        case .nuclear: "flame.fill"
        }
    }

    private func modeSummary(_ config: WakeGuardConfiguration) -> String {
        let stages = config.stages.count
        let questions = config.stages.first?.questionCount ?? 0
        let window = Int(config.maxWindow / 60)
        let alerts = config.escalationAlertOffsets.count
        return "\(stages) check-in\(stages == 1 ? "" : "s") starting with \(questions) questions. "
            + "Stays on your case for up to \(window) minutes with \(alerts) follow-up alert\(alerts == 1 ? "" : "s")."
    }

    // MARK: - Question difficulty

    private var difficultyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question Difficulty")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Set per alarm. Gentle and Balanced use easy round numbers — think 10 + 85 or 34 + 20. Hard brings real mental math.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                difficultyTile("Gentle", example: "20 + 15", note: "Small round sums")
                difficultyTile("Balanced", example: "34 + 20", note: "Default — easy rounds")
                difficultyTile("Hard", example: "47 + 86", note: "Wide-awake math")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func difficultyTile(_ name: String, example: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentSoft)
            Text(example)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke))
    }

    // MARK: - How it works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How Wake Guard Works")
                .font(.headline)
                .foregroundStyle(.white)

            howItWorksStep(icon: "alarm.fill", number: 1,
                           text: "Your alarm rings at wake time — one alarm is all it takes.")
            howItWorksStep(icon: "shield.checkered", number: 2,
                           text: "A Wake Guard session starts and stays active until you finish every check-in.")
            howItWorksStep(icon: "bell.badge.fill", number: 3,
                           text: "Ignore a check-in and follow-up alerts keep coming until the window runs out.")

            Text("iOS controls how long any single alert rings — it's the persistent session and follow-ups that keep you honest, not one endless sound.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func howItWorksStep(icon: String, number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Developer tools

    #if targetEnvironment(simulator) || DEBUG
    private var devCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showDevTools.toggle() }
            } label: {
                HStack {
                    Label("Developer Tools", systemImage: "wrench.and.screwdriver.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showDevTools ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if showDevTools {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Simulation mode (virtual time)", isOn: Binding(
                        get: { controller.simulationMode },
                        set: { $0 ? controller.enableSimulationMode() : controller.disableSimulationMode() }))
                        .tint(Theme.accent)

                    Picker("Preset for test session", selection: $devPreset) {
                        ForEach(WakeGuardModePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Button("Start Wake Guard now") {
                        controller.devStartSessionNow(preset: devPreset)
                    }
                    .buttonStyle(.bordered)

                    if controller.simulationMode {
                        LabeledContent("Virtual now",
                                       value: controller.clock.now.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                        HStack {
                            Button("+1 min") { controller.devAdvanceTime(by: 60) }
                            Button("+5 min") { controller.devAdvanceTime(by: 300) }
                            Button("+30 min") { controller.devAdvanceTime(by: 1800) }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Complete current stage") { controller.devCompleteCurrentStage() }
                        .buttonStyle(.bordered)
                        .disabled(controller.activeSession == nil)
                    Button("Simulate ignored check") { controller.devSimulateIgnoredCheck() }
                        .buttonStyle(.bordered)
                        .disabled(controller.activeSession == nil || !controller.simulationMode)
                    Button("Simulate expiration") { controller.devSimulateExpiration() }
                        .buttonStyle(.bordered)
                        .disabled(controller.activeSession == nil || !controller.simulationMode)

                    Toggle("Simulate AlarmKit scheduling failure", isOn: Binding(
                        get: { failScheduling },
                        set: { failScheduling = $0; controller.devSetSchedulingFailure($0) }))
                        .tint(Theme.accent)
                        .disabled(!controller.simulationMode)

                    if let session = controller.activeSession {
                        LabeledContent("Session", value: String(session.id.uuidString.prefix(8)))
                        LabeledContent("Stage", value: "\(session.currentStageIndex + 1)/\(session.stages.count)")
                        LabeledContent("Escalations", value: "\(session.escalationCount)")
                    }
                    if let error = controller.lastError {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    }

                    Text("Simulation mode swaps in a virtual clock and a simulated AlarmKit coordinator. Real AlarmKit behavior (Silent Mode, Focus, terminated app, alert duration) can only be verified on a physical iPhone — see DEVICE_TEST_CHECKLIST.md.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)
            }
        }
        .card()
    }
    #endif
}
