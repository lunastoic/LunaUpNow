//
//  ContentView.swift
//  LunaUpNow
//
//  Root tabs. While a Wake Guard session is unresolved, the session screen is
//  presented full-screen and cannot be dismissed — the whole point is that
//  one tiny interaction never ends the wake-up flow.
//

import SwiftUI

struct ContentView: View {
    @Environment(WakeGuardController.self) private var controller

    private var wakeGuardActive: Binding<Bool> {
        Binding(get: { controller.activeSession != nil }, set: { _ in })
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            AlarmsView()
                .tabItem { Label("Alarms", systemImage: "alarm.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .background(Theme.background)
        .fullScreenCover(isPresented: wakeGuardActive) {
            WakeGuardSessionView()
                .interactiveDismissDisabled()
        }
    }
}

#Preview {
    ContentView()
        .environment(WakeGuardController(store: InMemoryStore(),
                                         clock: SystemClock(),
                                         coordinator: SimulatedEscalationCoordinator()))
        .preferredColorScheme(.dark)
}
