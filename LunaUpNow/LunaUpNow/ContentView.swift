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
    @State private var selectedTab = 0

    private var wakeGuardActive: Binding<Bool> {
        Binding(get: { controller.activeSession != nil }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            AlarmsView()
                .tabItem { Label("Alarms", systemImage: "alarm.fill") }
                .tag(1)
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
        .toolbarBackground(Theme.card, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
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
