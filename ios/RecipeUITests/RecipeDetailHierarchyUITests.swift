// Developer: gengyun
// Purpose: Verifies visible recipe attribution and direct editing preserve save and cancel behavior.

import XCTest

final class RecipeDetailHierarchyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSourceAttributionAndDirectEditSaveCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-locale", "en"]
        app.launch()
        defer {
            app.terminate()
        }

        let sample = app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        let edit = app.buttons["recipeEdit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertTrue(edit.isHittable)
        let source = app.descendants(matching: .any).matching(
            identifier: "recipeOverviewSource"
        ).firstMatch
        XCTAssertTrue(source.exists)
        XCTAssertEqual(source.label, "Sample recipe")
        XCTAssertFalse(app.staticTexts["recipeOverviewAuthor"].exists)
        XCTAssertTrue(app.buttons["startCooking"].isEnabled)
        capture("DEV51 same sample after hierarchy change", app: app)

        app.buttons["Recipe Options"].tap()
        XCTAssertTrue(app.buttons["Add to Meal Plan"].exists)
        XCTAssertTrue(app.buttons["Collections"].exists)
        XCTAssertTrue(app.buttons["Delete Recipe"].exists)
        XCTAssertFalse(app.buttons["Edit Recipe"].exists)
        app.tap()
        edit.tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 8))

        // Explicit user entry modifies only this in-memory UI-test recipe.
        let original = app.textFields["Original link (optional)"]
        reveal(original, in: app)
        original.tap()
        original.typeText("https://example.com/dev51-fixture\n")
        app.buttons["saveRecipe"].tap()
        waitForEditorDismissal(in: app)
        XCTAssertTrue(source.exists)
        capture("DEV51 explicitly entered source link", app: app)

        edit.tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 8))
        let name = app.textFields["recipeName"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText(" changed")
        app.navigationBars.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        waitForEditorDismissal(in: app)
        XCTAssertTrue(app.staticTexts["Garlic Butter Shrimp Pasta"].exists)
        XCTAssertTrue(app.buttons["startCooking"].isEnabled)
        XCTAssertTrue(app.buttons["addToGroceries"].exists)
    }

    @MainActor
    func testExplicitSourceAndCreatorFixture() throws {
        let app = XCUIApplication()
        // The host seeds only the existing isolated Export QA library before this test.
        app.launchArguments = ["--uitesting", "--uitesting-export-qa", "--uitesting-locale", "en"]
        app.launch()
        defer {
            app.terminate()
        }
        let fixture = app.buttons["recipe.BF80A79C-A36C-6C5A-AA23-15B5E66BAF06"]
        guard fixture.waitForExistence(timeout: 10),
            fixture.label.contains("DEV51 Source Fixture")
        else {
            throw XCTSkip("Requires a host-seeded, isolated Export QA source/creator fixture.")
        }
        fixture.tap()
        let source = app.descendants(matching: .any).matching(
            identifier: "recipeOverviewSource"
        ).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertEqual(source.label, "DEV51 Test Kitchen")
        XCTAssertEqual(
            app.staticTexts["recipeOverviewAuthor"].label, "Creator: DEV51 Fixture Author")
        XCTAssertTrue(app.buttons["recipeEdit"].isHittable)
        capture("DEV51 explicit source and creator fixture", app: app)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable {
                return
            }
            let form = app.collectionViews.firstMatch
            form.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor
    private func waitForEditorDismissal(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Edit recipe"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
