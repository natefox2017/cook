// Developer: gengyun
// Purpose: Verifies UI-test cooking state stays separate from normal user data.

import Foundation
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
}
