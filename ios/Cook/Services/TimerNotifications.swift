// Developer: gengyun
// Purpose: Schedules and clears cooking timer notifications.

import Foundation
import UserNotifications

@MainActor
enum TimerNotifications {
    static func schedule(id: String, title: String, seconds: Int) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            throw TimerNotificationError.notAuthorized
        }
        let content = UNMutableNotificationContent()
        content.title = "Your cooking timer is ready"
        content.body = title
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    private enum TimerNotificationError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            "The timer is running. To also receive an alert when Cook is closed, enable notifications in Profile."
        }
    }
}
