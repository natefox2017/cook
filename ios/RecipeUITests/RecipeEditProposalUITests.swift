// Developer: gengyun
// Purpose: Regression coverage for explicit private recipe edit proposal review and acceptance.

import XCTest

final class RecipeEditProposalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDiscardAndSaveVariantPreserveTheOriginalRecipe() {
        let app = launchFixture()
        defer { app.terminate() }
        let search = app.textFields["recipeSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Garlic Butter Shrimp Pasta")
        waitForLibraryRecipeCount(1, in: app)
        let originalRecipeIDs = libraryRecipeIDs(in: app)
        XCTAssertEqual(originalRecipeIDs.count, 1)
        openSamplePasta(in: app)

        openProposalReview(in: app)
        let original = app.staticTexts["reviewProposalBefore.0"].label
        let input = proposalInput(in: app)
        let suggested = input.value as? String ?? input.label
        XCTAssertTrue(suggested.hasPrefix("QA Changed "))
        XCTAssertNotEqual(original, suggested)
        XCTAssertTrue(input.isEnabled)

        app.buttons["discardRecipeProposal"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])

        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, original)
        app.buttons["saveRecipeProposalVariant"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])

        dismissRecipeFeedback(in: app)

        // Only a separate private copy is saved; the original is still current.
        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, original)
        app.buttons["discardRecipeProposal"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])
        returnToLibrary(in: app)

        waitForLibraryRecipeCount(originalRecipeIDs.count + 1, in: app)
        let savedRecipeIDs = libraryRecipeIDs(in: app)
        XCTAssertEqual(savedRecipeIDs.count, originalRecipeIDs.count + 1)
        let newRecipeIDs = savedRecipeIDs.subtracting(originalRecipeIDs)
        XCTAssertEqual(newRecipeIDs.count, 1)
        guard let variantID = newRecipeIDs.first else { return }
        app.buttons[variantID].tap()
        XCTAssertTrue(app.buttons["startCooking"].waitForExistence(timeout: 8))
        assertIngredientText(suggested, in: app)
        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, suggested)
        app.buttons["discardRecipeProposal"].tap()
    }

    @MainActor
    func testApplyingProposalRevalidatesAndUpdatesTheCurrentRecipe() {
        let app = launchFixture()
        defer { app.terminate() }
        openSamplePasta(in: app)

        openProposalReview(in: app)
        let input = proposalInput(in: app)
        let marker = " UIEdited76"
        input.tap()
        input.typeText(marker)
        let edited = input.value as? String ?? input.label
        XCTAssertTrue(edited.contains(marker))
        app.buttons["applyRecipeProposal"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])

        dismissRecipeFeedback(in: app)
        assertIngredientText(edited, in: app)
        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, edited)
        app.buttons["discardRecipeProposal"].tap()
    }

    @MainActor
    func testStaleProposalCannotBeAppliedOrSavedAsVariant() {
        let app = launchFixture(stale: true)
        defer { app.terminate() }
        openSamplePasta(in: app)

        openProposalReview(in: app)
        XCTAssertTrue(app.staticTexts["staleRecipeProposal"].exists)
        XCTAssertFalse(app.buttons["applyRecipeProposal"].isEnabled)
        XCTAssertFalse(app.buttons["saveRecipeProposalVariant"].isEnabled)
        app.navigationBars["Review changes"].buttons["Cancel"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])
        XCTAssertTrue(app.buttons["startCooking"].exists)
    }

    @MainActor
    func testOversizedProposalsDoNotRenderChangesAndRemainDismissible() {
        for flag in [
            "--uitesting-ai-edit-oversized-changes",
            "--uitesting-ai-edit-oversized-explanation",
        ] {
            let app = launchFixture(extraArgument: flag)
            openSamplePasta(in: app)
            openProposalReview(in: app)

            XCTAssertTrue(app.staticTexts["invalidRecipeProposal"].exists)
            XCTAssertFalse(app.staticTexts["reviewProposalBefore.0"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["reviewProposalAfter.0"].exists)
            XCTAssertFalse(app.buttons["applyRecipeProposal"].isEnabled)
            XCTAssertFalse(app.buttons["saveRecipeProposalVariant"].isEnabled)
            XCTAssertTrue(app.buttons["discardRecipeProposal"].isEnabled)
            app.buttons["discardRecipeProposal"].tap()
            waitUntilAbsent(app.navigationBars["Review changes"])
            XCTAssertTrue(app.buttons["startCooking"].exists)
            app.terminate()
        }
    }

    @MainActor
    private func launchFixture(
        stale: Bool = false,
        extraArgument: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-reset-cooking-sessions",
            "--uitesting-locale", "en",
            "--uitesting-ai-edit-preview",
        ]
        if stale {
            app.launchArguments.append("--uitesting-ai-edit-stale")
        }
        if let extraArgument {
            app.launchArguments.append(extraArgument)
        }
        app.launch()
        XCTAssertTrue(app.buttons["addRecipeButton"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
                .waitForExistence(timeout: 8)
        )
        return app
    }

    @MainActor
    private func openSamplePasta(in app: XCUIApplication) {
        let sample = app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
        XCTAssertTrue(sample.waitForExistence(timeout: 8))
        sample.tap()
        XCTAssertTrue(app.buttons["startCooking"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func dismissRecipeFeedback(in app: XCUIApplication) {
        let feedback = app.alerts["Recipe"]
        if feedback.waitForExistence(timeout: 2) {
            feedback.buttons["OK"].tap()
        }
    }

    @MainActor
    private func waitForLibraryRecipeCount(_ count: Int, in app: XCUIApplication) {
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "recipe.")
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in cards.count == count },
            object: cards
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }

    @MainActor
    private func libraryRecipeIDs(in app: XCUIApplication) -> Set<String> {
        Set(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "recipe.")
        ).allElementsBoundByIndex.map(\.identifier))
    }

    @MainActor
    private func returnToLibrary(in app: XCUIApplication) {
        app.navigationBars["Recipe"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["addRecipeButton"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func assertIngredientText(_ text: String, in app: XCUIApplication) {
        let ingredient = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "recipeIngredientInfo.", text
        )).firstMatch
        let scroll = app.scrollViews["recipeDetailScroll"]
        for _ in 0..<6 {
            if ingredient.exists { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(ingredient.waitForExistence(timeout: 8))
    }

    @MainActor
    private func openProposalReview(in app: XCUIApplication) {
        app.buttons["Recipe Options"].tap()
        let fixture = app.buttons["qaReviewRecipeProposal"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 8))
        fixture.tap()
        XCTAssertTrue(app.navigationBars["Review changes"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func proposalInput(in app: XCUIApplication) -> XCUIElement {
        let field = app.descendants(matching: .any)["reviewProposalAfter.0"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        return field
    }

    @MainActor
    private func waitUntilAbsent(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
}
