// Developer: gengyun
// Purpose: Schedules and cancels local cooking timer notifications.

import Foundation
import RecipeCore
import UserNotifications

@MainActor
enum TimerNotifications {
    private static let presentationDelegate = TimerNotificationDelegate()
    private static var operations: [String: Task<Void, Error>] = [:]
    private static var operationRevisions: [String: UUID] = [:]

    static func configurePresentation() {
        UNUserNotificationCenter.current().delegate = presentationDelegate
    }

    static func schedule(id: String, title: String, seconds: Int) -> Task<Void, Error> {
        enqueue(id: id) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            else {
                throw TimerNotificationError.notAuthorized
            }
            let content = UNMutableNotificationContent()
            content.title = String(
                localized: LocalizedStringResource(
                    "Your cooking timer is ready", locale: RecipeLanguage.active))
            content.body = title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(1, seconds)), repeats: false)
            try await center.add(
                UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel(id: String) {
        enqueue(id: id) {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
    }

    private static func enqueue(
        id: String,
        operation: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Error> {
        let previous = operations[id]
        let revision = UUID()
        operationRevisions[id] = revision
        let task = Task { @MainActor in
            if let previous {
                _ = try? await previous.value
            }
            guard operationRevisions[id] == revision else { return }
            try await operation()
        }
        operations[id] = task
        Task { @MainActor in
            _ = try? await task.value
            guard operationRevisions[id] == revision else { return }
            operations[id] = nil
            operationRevisions[id] = nil
        }
        return task
    }

    private enum TimerNotificationError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            String(
                localized: LocalizedStringResource(
                    "The timer is running. To also receive an alert when Recipe is closed, enable notifications in Profile.",
                    locale: RecipeLanguage.active))
        }
    }
}

private final class TimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        guard identifier.hasPrefix("cook.timer.")
            || identifier.hasPrefix("recipe.uitesting.timer.")
        else {
            completionHandler([])
            return
        }

        completionHandler([.banner, .sound])
    }
}
