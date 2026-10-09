// Developer: gengyun
// Purpose: Verifies UI-test cooking state stays separate from normal user data.

import Foundation
import RecipeCore
import Supabase
import UserNotifications
import XCTest

@testable import Recipe

final class RecipeTestIsolationTests: XCTestCase {
    func testClearingUITestSessionsPreservesNormalAndLegacySessions() throws {
        let suiteName = "recipe.test.isolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let recipeID = UUID()
        let normalKey = "recipe.cookingSession.\(recipeID.uuidString)"
        let legacyKey = "cook.cookingSession.\(recipeID.uuidString)"
        let testKey = RecipeUITestNamespace.preferenceKey(normalKey, isUITesting: true)
        let onboardingKey = RecipeUITestNamespace.preferenceKey(
            "recipe.onboarding.completed",
            isUITesting: true
        )

        defaults.set(Data([1]), forKey: normalKey)
        defaults.set(Data([2]), forKey: legacyKey)
        defaults.set(Data([3]), forKey: testKey)
        defaults.set(true, forKey: onboardingKey)

        RecipeUITestNamespace.clearCookingSessions(from: defaults)

        XCTAssertEqual(defaults.data(forKey: normalKey), Data([1]))
        XCTAssertEqual(defaults.data(forKey: legacyKey), Data([2]))
        XCTAssertNil(defaults.object(forKey: testKey))
        XCTAssertEqual(defaults.object(forKey: onboardingKey) as? Bool, true)
        XCTAssertEqual(
            RecipeUITestNamespace.preferenceKey(normalKey, isUITesting: false),
            normalKey
        )
    }

    func testCookingTimerNotificationsUseSeparateIdentifiers() {
        let recipeID = UUID()
        let timerID = UUID()
        let normalID = RecipeUITestNamespace.timerNotificationID(
            recipeID: recipeID,
            timerID: timerID,
            isUITesting: false
        )
        let testID = RecipeUITestNamespace.timerNotificationID(
            recipeID: recipeID,
            timerID: timerID,
            isUITesting: true
        )

        XCTAssertEqual(
            normalID,
            "cook.timer.\(recipeID.uuidString).\(timerID.uuidString)"
        )
        XCTAssertEqual(
            testID,
            "recipe.uitesting.timer.\(recipeID.uuidString).\(timerID.uuidString)"
        )
        XCTAssertNotEqual(normalID, testID)
    }

    @MainActor
    func testUITestDeletionClearsOnlyUITestLibraryAndPreferences() async throws {
        let suiteName = "recipe.test.deletion-isolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let productionKeys = [
            "recipe.grocery.consolidate",
            "cook.grocery.sources",
            "recipe.meal.weekStart",
            "recipe.collections",
            "recipe.sync.mode",
            "recipe.sync.localErasePending",
            "recipe.shareInbox",
        ]
        for (index, key) in productionKeys.enumerated() {
            defaults.set("normal-\(index)", forKey: key)
        }

        let testKeys = [
            "recipe.grocery.consolidate",
            "recipe.grocery.sources",
            "recipe.meal.weekStart",
            "recipe.collections",
        ].map { RecipeUITestNamespace.preferenceKey($0, isUITesting: true) }
        for (index, key) in testKeys.enumerated() {
            defaults.set("test-\(index)", forKey: key)
        }

        let store = RecipeStore(fileURL: nil)
        try store.loadSampleRecipes()
        let cloudSync = CloudSyncCoordinator(
            service: UnconfiguredCloudSync(),
            defaults: defaults,
            monitorsNetworkChanges: false
        )

        try await RecipeLocalDataDeletion.erase(
            store: store,
            cloudSync: cloudSync,
            authState: .signedOut,
            isUITesting: true,
            defaults: defaults
        )

        XCTAssertFalse(store.hasUserData)
        for key in productionKeys {
            XCTAssertNotNil(defaults.object(forKey: key), "Unexpectedly cleared \(key)")
        }
        for key in testKeys {
            XCTAssertNil(defaults.object(forKey: key), "Did not clear \(key)")
        }
    }

    #if DEBUG
        func testUITestSupabaseClientUsesIsolatedStorageAndBlocksNetwork() async {
            RecipeUITestNetworkURLProtocol.reset()
            let client = RecipeSupabase.makeUITestClient()
            let authKey = "recipe.test.auth-isolation.\(UUID().uuidString)"
            let authDefaults = RecipeUITestNamespace.authDefaults(isUITesting: true)
            defer {
                authDefaults.removeObject(forKey: authKey)
            }

            authDefaults.set(true, forKey: authKey)
            XCTAssertTrue(authDefaults.bool(forKey: authKey))
            XCTAssertNil(UserDefaults.standard.object(forKey: authKey))
            XCTAssertNotEqual(
                RecipeSupabase.uiTestAuthStorageService,
                RecipeSupabase.productionAuthStorageService
            )

            do {
                _ = try await client.auth.signIn(
                    email: "recipe-ui-test@example.test",
                    password: "not-a-real-password"
                )
                XCTFail("The UI-test Supabase client must not complete network requests.")
            } catch {
            }

            let interceptedHosts = RecipeUITestNetworkURLProtocol.interceptedHosts
            XCTAssertFalse(interceptedHosts.isEmpty)
            XCTAssertTrue(
                interceptedHosts.allSatisfy { $0 == "uitesting.recipe.invalid" },
                "Unexpected request hosts: \(interceptedHosts)"
            )
        }
    #endif
}

@MainActor
final class RecipeTimerNotificationTests: XCTestCase {
    func testPrefixCleanupWaitsForQueuedAddAndPreservesNormalTimer() async throws {
        let center = try await authorizedCenter()
        let recipeID = UUID()
        let timerID = UUID()
        let testID = RecipeUITestNamespace.timerNotificationID(
            recipeID: recipeID,
            timerID: timerID,
            isUITesting: true
        )
        let normalID = RecipeUITestNamespace.timerNotificationID(
            recipeID: recipeID,
            timerID: timerID,
            isUITesting: false
        )
        let testPrefix = RecipeUITestNamespace.timerNotificationPrefix(
            recipeID: recipeID,
            isUITesting: true
        )
        defer {
            TimerNotifications.cancel(id: testID)
            TimerNotifications.cancel(id: normalID)
        }

        let queuedTestSchedule = TimerNotifications.schedule(
            id: testID,
            title: "QA timer removed during scheduling",
            seconds: 120
        )
        let normalSchedule = TimerNotifications.schedule(
            id: normalID,
            title: "Normal timer preserved",
            seconds: 120
        )
        await TimerNotifications.cancelAll(matchingPrefixes: [testPrefix])
        try await queuedTestSchedule.value
        try await normalSchedule.value

        await verifyRemoval(of: [testID], from: center)
        let pending = await center.pendingNotificationRequests()
        XCTAssertEqual(
            pending.first { $0.identifier == normalID }?.content.body,
            "Normal timer preserved"
        )
    }

    func testLatestNotificationSurvivesRepeatedCancelAndReschedule() async throws {
        let center = try await authorizedCenter()
        let id = "recipe.uitesting.timer.\(UUID().uuidString)"
        defer {
            TimerNotifications.cancel(id: id)
        }

        for attempt in 0..<20 {
            let oldRequest = TimerNotifications.schedule(
                id: id,
                title: "QA stale request \(attempt)",
                seconds: 120
            )
            TimerNotifications.cancel(id: id)
            let latestTitle = "QA latest request \(attempt)"
            let newRequest = TimerNotifications.schedule(
                id: id,
                title: latestTitle,
                seconds: 120
            )
            try await newRequest.value
            try await oldRequest.value

            let pending = await center.pendingNotificationRequests()
            let matching = pending.filter { $0.identifier == id }
            XCTAssertEqual(matching.count, 1)
            XCTAssertEqual(matching.first?.content.body, latestTitle)
        }

        TimerNotifications.cancel(id: id)
        await verifyRemoval(of: [id], from: center)
    }

    func testCancellingOneNotificationPreservesAnIndependentTimer() async throws {
        let center = try await authorizedCenter()
        let firstID = "recipe.uitesting.timer.\(UUID().uuidString)"
        let secondID = "recipe.uitesting.timer.\(UUID().uuidString)"
        defer {
            TimerNotifications.cancel(id: firstID)
            TimerNotifications.cancel(id: secondID)
        }

        let first = TimerNotifications.schedule(id: firstID, title: "QA first", seconds: 120)
        let second = TimerNotifications.schedule(id: secondID, title: "QA second", seconds: 120)
        try await first.value
        try await second.value

        TimerNotifications.cancel(id: firstID)
        await verifyRemoval(of: [firstID], from: center)
        let pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.first { $0.identifier == secondID }?.content.body, "QA second")

        TimerNotifications.cancel(id: secondID)
        await verifyRemoval(of: [secondID], from: center)
    }

    func testNotificationPresentationDelegateIsRetained() {
        TimerNotifications.configurePresentation()
        XCTAssertNotNil(UNUserNotificationCenter.current().delegate)
    }

    func testForegroundTimerRequestsBannerAndSound() async throws {
        let center = try await authorizedCenter()
        let originalDelegate = try XCTUnwrap(center.delegate)
        let id = "recipe.uitesting.timer.\(UUID().uuidString)"
        let callback = XCTestExpectation(description: "Real foreground timer callback")
        let recorder = RecipeNotificationPresentationRecorder(
            identifier: id,
            originalDelegate: originalDelegate,
            expectation: callback
        )
        center.delegate = recorder
        defer {
            center.delegate = originalDelegate
            TimerNotifications.cancel(id: id)
        }

        try await TimerNotifications.schedule(id: id, title: "QA timer verification", seconds: 1)
            .value
        let result = await XCTWaiter.fulfillment(of: [callback], timeout: 6)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(recorder.options, [.banner, .sound])
        TimerNotifications.cancel(id: id)
        await verifyRemoval(of: [id], from: center)
    }

    private func authorizedCenter() async throws -> UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            throw XCTSkip(
                "Device notification permission is unavailable; no permission prompt was requested."
            )
        }
        return center
    }

    private func verifyRemoval(
        of identifiers: Set<String>,
        from center: UNUserNotificationCenter
    ) async {
        // Observe only disposable test identifiers; never remove the user's requests.
        for _ in 0..<100 {
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            let hasPending = pending.contains { identifiers.contains($0.identifier) }
            let hasDelivered = delivered.contains {
                identifiers.contains($0.request.identifier)
            }
            if !hasPending && !hasDelivered {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("A canceled test notification remained in the notification center.")
    }
}

// The notification center invokes its delegate off the test actor; protect the recorded result.
private final class RecipeNotificationPresentationRecorder: NSObject,
    UNUserNotificationCenterDelegate, @unchecked Sendable
{
    private let identifier: String
    private let originalDelegate: UNUserNotificationCenterDelegate
    private let expectation: XCTestExpectation
    private let lock = NSLock()
    private var recordedOptions: UNNotificationPresentationOptions?

    init(
        identifier: String,
        originalDelegate: UNUserNotificationCenterDelegate,
        expectation: XCTestExpectation
    ) {
        self.identifier = identifier
        self.originalDelegate = originalDelegate
        self.expectation = expectation
    }

    var options: UNNotificationPresentationOptions? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return recordedOptions
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        originalDelegate.userNotificationCenter?(
            center,
            willPresent: notification,
            withCompletionHandler: { options in
                if notification.request.identifier == self.identifier {
                    self.lock.lock()
                    self.recordedOptions = options
                    self.lock.unlock()
                    self.expectation.fulfill()
                }
                completionHandler(options)
            }
        )
    }
}
