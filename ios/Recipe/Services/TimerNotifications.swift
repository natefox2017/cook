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

    private static func warningID(for id: String) -> String { id + ".early" }

    static func schedule(
        id: String, title: String, deadline: Date,
        warningSeconds: Int = 30, completionSoundEnabled: Bool = true
    ) -> Task<Void, Error> {
        enqueue(id: id) {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            else {
                throw TimerNotificationError.notAuthorized
            }
            let relatedIDs = [id, warningID(for: id)]
            center.removePendingNotificationRequests(withIdentifiers: relatedIDs)
            center.removeDeliveredNotifications(withIdentifiers: relatedIDs)

            // Use the absolute deadline, not the duration before awaiting authorization.
            let now = Date.now
            guard deadline > now else { return }
            if warningSeconds > 0,
                deadline.timeIntervalSince(now) > Double(warningSeconds + 1)
            {
                let soon = UNMutableNotificationContent()
                soon.title = String(
                    localized: LocalizedStringResource(
                        "Timer almost done", locale: RecipeLanguage.active))
                soon.body = title
                soon.sound = UNNotificationSound(
                    named: UNNotificationSoundName("timer-warning.wav"))
                let delay = deadline.addingTimeInterval(-TimeInterval(warningSeconds))
                    .timeIntervalSinceNow
                if delay > 0 {
                    try await center.add(
                        UNNotificationRequest(
                            identifier: warningID(for: id),
                            content: soon,
                            trigger: UNTimeIntervalNotificationTrigger(
                                timeInterval: max(1, delay), repeats: false)
                        )
                    )
                }
            }
            let done = UNMutableNotificationContent()
            done.title = String(
                localized: LocalizedStringResource(
                    "Your cooking timer is ready", locale: RecipeLanguage.active))
            done.body = title
            done.sound = completionSoundEnabled ? .default : nil
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: id, content: done,
                        trigger: UNTimeIntervalNotificationTrigger(
                            timeInterval: max(1, deadline.timeIntervalSinceNow),
                            repeats: false)
                    )
                )
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: relatedIDs)
                throw error
            }
        }
    }

    /// Preferences can change from Profile while the Cooking screen is dismissed.
    static func refreshScheduledPreferences(
        warningSeconds: Int, completionSoundEnabled: Bool
    ) async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let completionRequests = pending.filter { request in
            (request.identifier.hasPrefix("cook.timer.")
                || request.identifier.hasPrefix("recipe.uitesting.timer."))
                && !request.identifier.hasSuffix(".early")
        }
        for request in completionRequests {
            guard let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                let deadline = trigger.nextTriggerDate(), deadline > .now
            else {
                continue
            }
            let task = schedule(
                id: request.identifier, title: request.content.body,
                deadline: deadline, warningSeconds: warningSeconds,
                completionSoundEnabled: completionSoundEnabled
            )
            _ = try? await task.value
        }
    }

    static func cancel(id: String) {
        enqueueCancellation(id: id)
    }

    static func cancelAll(matchingPrefixes prefixes: [String]) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        // The final center snapshot and queue snapshot cover completed and queued adds.
        let identifiers = Set(
            pending.map(\.identifier)
                + delivered.map { $0.request.identifier }
                + operations.keys.filter { id in
                    prefixes.contains { id.hasPrefix($0) }
                }
        ).filter { id in
            prefixes.contains { id.hasPrefix($0) }
        }

        let cancellationTasks = Set(identifiers.map { id in
            id.hasSuffix(".early") ? String(id.dropLast(".early".count)) : id
        }).map { id in
            enqueueCancellation(id: id)
        }
        for task in cancellationTasks {
            _ = try? await task.value
        }
    }

    private static func enqueueCancellation(id: String) -> Task<Void, Error> {
        enqueue(id: id) {
            let center = UNUserNotificationCenter.current()
            let relatedIDs = [id, warningID(for: id)]
            center.removePendingNotificationRequests(withIdentifiers: relatedIDs)
            center.removeDeliveredNotifications(withIdentifiers: relatedIDs)
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
