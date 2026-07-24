//
//  LunaUpNowApp.swift
//  LunaUpNow
//

import SwiftUI

@main
struct LunaUpNowApp: App {
    @State private var controller = WakeGuardController.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { controller.handleBecameActive() }
                }
                .onAppear {
                    // Smoke-test hook: `simctl launch ... -devSession` starts a
                    // simulated Wake Guard immediately (simulator/dev only).
                    if ProcessInfo.processInfo.arguments.contains("-devSession") {
                        controller.enableSimulationMode()
                        controller.devStartSessionNow(preset: .heavySleeper)
                    }
                }
        }
    }
}
