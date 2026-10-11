// Developer: gengyun
// Purpose: Verifies real Detail sharing entry, unavailable consent cancellation, and private deletion.

import XCTest

final class RecipeOwnerSharingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUnavailableShareCancelsAndPrivateDeleteStillWorks() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-locale", "en"]
        app.launch()
        defer {
            app.terminate()
        }
        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        XCTAssertTrue(app.buttons["recipeEdit"].waitForExistence(timeout: 8))
        app.buttons["Recipe Options"].tap()
        app.buttons["recipeShare"].tap()
        let unavailable = app.staticTexts["Sharing is unavailable. Try again later."]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Publish link"].isEnabled)
        XCTAssertFalse(app.buttons["Copy Link"].exists)
        XCTAssertFalse(app.buttons["Revoke link"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "DEV242 actual unavailable sharing sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["recipeEdit"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["startCooking"].isEnabled)
        app.buttons["Recipe Options"].tap()
        app.buttons["Delete Recipe"].tap()
        app.sheets.buttons["Delete Recipe"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(recipe.exists)
    }
}
