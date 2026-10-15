// Developer: gengyun
// Purpose: Exercises the native draft review flow's loading, review, and manual-exit main path.

import XCTest

final class RecipeDraftFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDraftReviewPresentsAndSkipsToManual() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-draft-review",
        ]
        app.launch()

        // Without a signed-in owner the flow must reach an explicit manual-exit
        // failure state instead of an indefinite spinner. Skip returns to the
        // root view without writing to the private library.
        let skipManual = app.buttons["Enter Manually"]
        XCTAssertTrue(skipManual.waitForExistence(timeout: 15), app.debugDescription)
        skipManual.tap()

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Review Recipe"]
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 8), .completed, app.debugDescription)
    }
}
