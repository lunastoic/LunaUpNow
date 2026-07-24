//
//  WakeGuardIntents.swift
//  LunaUpNow
//
//  The custom action on the AlarmKit alert. `LiveActivityIntent` runs in the
//  app process; with `openAppWhenRun` the alert's secondary button brings the
//  user straight into the Wake Guard flow. Tapping it does NOT complete
//  anything — it only opens the session.
//

import Foundation
import AppIntents

extension Notification.Name {
    static let wakeGuardAlarmActioned = Notification.Name("wakeGuardAlarmActioned")
}

struct StartWakeGuardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Wake Guard"
    static let description = IntentDescription("Opens the Wake Guard challenge for the alarm that is ringing.")
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .wakeGuardAlarmActioned,
                                        object: nil,
                                        userInfo: ["alarmID": alarmID])
        return .result()
    }
}
