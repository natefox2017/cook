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

        let feedback = app.alerts["Recipe"]
        if feedback.waitForExistence(timeout: 2) {
            feedback.buttons["OK"].tap()
        }

        // Only a separate private copy is saved; the original is still current.
        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, original)
        app.buttons["discardRecipeProposal"].tap()
    }

    @MainActor
    func testApplyingProposalRevalidatesAndUpdatesTheCurrentRecipe() {
        let app = launchFixture()
        defer { app.terminate() }
        openSamplePasta(in: app)

        openProposalReview(in: app)
        let input = proposalInput(in: app)
        let suggested = input.value as? String ?? input.label
        app.buttons["applyRecipeProposal"].tap()
        waitUntilAbsent(app.navigationBars["Review changes"])

        openProposalReview(in: app)
        XCTAssertEqual(app.staticTexts["reviewProposalBefore.0"].label, suggested)
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
    private func launchFixture(stale: Bool = false) -> XCUIApplication {
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
