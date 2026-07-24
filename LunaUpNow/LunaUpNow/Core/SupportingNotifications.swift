//
//  SupportingNotifications.swift
//  LunaUpNow
//
//  Optional supporting local notifications. These are REMINDERS ONLY — they
//  never replace the primary AlarmKit alarm and are clearly labeled as such.
//

import Foundation
import UserNotifications

@MainActor
final class SupportingNotifications {
    private let center = UNUserNotificationCenter.current()

    private func identifier(sessionID: UUID, slot: Int) -> String {
        "wakeguard.reminder.\(sessionID.uuidString).\(slot)"
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Schedule the session's still-future reminders. Idempotent via stable
    /// identifiers (re-adding the same identifier replaces, never duplicates).
    func scheduleReminders(for session: WakeGuardSession, now: Date) async {
        await requestAuthorizationIfNeeded()
        for (slot, offset) in session.configuration.supportingReminderOffsets.enumerated() {
            let fireDate = session.sessionStart.addingTimeInterval(offset)
            guard fireDate > now, fireDate < session.maxExpiration else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Wake Guard is still active"
            content.body = "Your wake session isn't complete. Open the app and finish your checks."
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
            let request = UNNotificationRequest(identifier: identifier(sessionID: session.id, slot: slot),
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelReminders(for session: WakeGuardSession) {
        let ids = session.configuration.supportingReminderOffsets.indices.map {
            identifier(sessionID: session.id, slot: $0)
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
