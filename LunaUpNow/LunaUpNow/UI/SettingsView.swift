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

    var body: some View {
        NavigationStack {
            Form {
                Section("Wake Guard Modes") {
                    ForEach(WakeGuardModePreset.allCases, id: \.self) { preset in
                        let config = WakeGuardConfiguration.preset(preset)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.displayName).font(.headline)
                            Text(modeSummary(config))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    Text("One alarm begins a persistent multi-stage wake session that stays unresolved until completed or expired. Wake Guard does not — and cannot — make a single sound play continuously for three hours; iOS controls how long an alert keeps ringing. Follow-up alerts and the persistent session are what keep you honest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { Text("How Wake Guard works") }

                #if targetEnvironment(simulator) || DEBUG
                devSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }

    private func modeSummary(_ config: WakeGuardConfiguration) -> String {
        let stageBits = config.stages.enumerated().map { idx, s in
            "S\(idx + 1): \(s.questionCount)q" + (s.delayAfterPreviousStage > 0 ? " +\(Int(s.delayAfterPreviousStage / 60))m" : "")
        }.joined(separator: ", ")
        return "\(stageBits) • window \(Int(config.maxWindow / 60)) min • \(config.escalationAlertOffsets.count) follow-up alerts"
    }

    #if targetEnvironment(simulator) || DEBUG
    @ViewBuilder
    private var devSection: some View {
        Section {
            Toggle("Simulation mode (virtual time)", isOn: Binding(
                get: { controller.simulationMode },
                set: { $0 ? controller.enableSimulationMode() : controller.disableSimulationMode() }))

            Picker("Preset for test session", selection: $devPreset) {
                ForEach(WakeGuardModePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            Button("Start Wake Guard now") {
                controller.devStartSessionNow(preset: devPreset)
            }

            if controller.simulationMode {
                LabeledContent("Virtual now",
                               value: controller.clock.now.formatted(date: .omitted, time: .standard))
                HStack {
                    Button("+1 min") { controller.devAdvanceTime(by: 60) }
                    Button("+5 min") { controller.devAdvanceTime(by: 300) }
                    Button("+30 min") { controller.devAdvanceTime(by: 1800) }
                }
                .buttonStyle(.bordered)
            }

            Button("Complete current stage") { controller.devCompleteCurrentStage() }
                .disabled(controller.activeSession == nil)
            Button("Simulate ignored check") { controller.devSimulateIgnoredCheck() }
                .disabled(controller.activeSession == nil || !controller.simulationMode)
            Button("Simulate expiration") { controller.devSimulateExpiration() }
                .disabled(controller.activeSession == nil || !controller.simulationMode)

            Toggle("Simulate AlarmKit scheduling failure", isOn: Binding(
                get: { failScheduling },
                set: { failScheduling = $0; controller.devSetSchedulingFailure($0) }))
                .disabled(!controller.simulationMode)

            if let session = controller.activeSession {
                LabeledContent("Session", value: String(session.id.uuidString.prefix(8)))
                LabeledContent("Stage", value: "\(session.currentStageIndex + 1)/\(session.stages.count)")
                LabeledContent("Escalations", value: "\(session.escalationCount)")
            }
            if let error = controller.lastError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Developer / Simulator Test Controls")
        } footer: {
            Text("Simulation mode swaps in a virtual clock and a simulated AlarmKit coordinator. Real AlarmKit behavior (Silent Mode, Focus, terminated app, alert duration) can only be verified on a physical iPhone — see DEVICE_TEST_CHECKLIST.md.")
        }
    }
    #endif
}
