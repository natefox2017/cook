// Developer: gengyun
// Purpose: Verifies ingredient-group and private step-photo edits save and discard in the native editor.

import XCTest

final class RecipeMetadataEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGroupsAndStepPhotosSaveReopenAndCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-locale", "en"]
        app.launch()
        defer { app.terminate() }
        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 10))
        recipe.tap()
        openEditor(in: app)

        reveal(app.buttons["addIngredientGroup"], in: app)
        app.buttons["addIngredientGroup"].tap()
        let firstName = groupNames(in: app).firstMatch
        reveal(firstName, in: app)
        firstName.tap()
        firstName.typeText("Dry ingredients\n")
        let firstID = firstName.identifier.replacingOccurrences(
            of: "ingredientGroupName.", with: "")
        let firstDisclosure = app.buttons["Ingredients in this group"].firstMatch
        reveal(firstDisclosure, in: app)
        firstDisclosure.tap()
        let firstToggle = groupMembers(firstID, in: app).firstMatch
        reveal(firstToggle, in: app)
        firstToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(firstToggle.value as? String, "1")
        firstDisclosure.tap()

        reveal(app.buttons["addIngredientGroup"], in: app)
        app.buttons["addIngredientGroup"].tap()
        let secondName = groupNames(in: app).element(
            boundBy: 1)
        reveal(secondName, in: app)
        secondName.tap()
        secondName.typeText("Wet ingredients\n")
        let secondID = secondName.identifier.replacingOccurrences(
            of: "ingredientGroupName.", with: "")
        let secondDisclosure = app.buttons.matching(identifier: "Ingredients in this group")
            .element(boundBy: 1)
        reveal(secondDisclosure, in: app)
        secondDisclosure.tap()
        let secondToggle = groupMembers(secondID, in: app).element(boundBy: 1)
        reveal(secondToggle, in: app)
        secondToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(secondToggle.value as? String, "1")
        secondDisclosure.tap()
        let up = app.buttons["ingredientGroupUp.\(secondID)"]
        reveal(up, in: app)
        up.tap()
        XCTAssertEqual(
            groupNames(in: app).firstMatch.value as? String, "Wet ingredients")

        let photoButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'addStepPhoto.'"))
        let firstPhoto = photoButtons.element(boundBy: 0)
        reveal(firstPhoto, in: app)
        firstPhoto.tap()
        choosePhoto(at: 0, in: app)
        let secondPhoto = photoButtons.element(boundBy: 1)
        reveal(secondPhoto, in: app)
        secondPhoto.tap()
        choosePhoto(at: 1, in: app)
        let save = app.buttons["saveRecipe"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForEditorDismissal(in: app)
        let detailPhotos = app.images.matching(
            NSPredicate(format: "identifier BEGINSWITH 'stepPhoto.'"))
        XCTAssertEqual(detailPhotos.count, 2)
        for photo in detailPhotos.allElementsBoundByIndex {
            reveal(photo, in: app)
            XCTAssertTrue(photo.isHittable)
        }
        let detailAttachment = XCTAttachment(screenshot: app.screenshot())
        detailAttachment.name = "DEV52 saved step photos displayed in recipe detail"
        detailAttachment.lifetime = .keepAlways
        add(detailAttachment)

        openEditor(in: app)
        let wet = groupNames(in: app).firstMatch
        reveal(wet, in: app)
        XCTAssertEqual(wet.value as? String, "Wet ingredients")
        XCTAssertEqual(
            groupNames(in: app).element(boundBy: 1).value
                as? String,
            "Dry ingredients")
        wet.tap()
        wet.typeText(" changed\n")
        reveal(app.buttons["Remove step photo"].firstMatch, in: app)
        app.buttons["Remove step photo"].firstMatch.tap()
        app.navigationBars.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        waitForEditorDismissal(in: app)

        openEditor(in: app)
        reveal(groupNames(in: app).firstMatch, in: app)
        XCTAssertEqual(
            groupNames(in: app).firstMatch.value as? String, "Wet ingredients")
        reveal(app.buttons["Remove step photo"].firstMatch, in: app)
        XCTAssertTrue(app.buttons["Remove step photo"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "DEV52 persisted private photo after discarded removal"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForEditorDismissal(in app: XCUIApplication) {
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Edit recipe"]
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 8), .completed, app.debugDescription)
    }

    @MainActor
    private func groupNames(in app: XCUIApplication) -> XCUIElementQuery {
        app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'ingredientGroupName.'"))
    }

    @MainActor
    private func groupMembers(_ id: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "ingredientGroupMember.\(id)."))
    }

    @MainActor
    private func openEditor(in app: XCUIApplication) {
        let options = app.buttons["Recipe Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        options.tap()
        app.buttons["Edit Recipe"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func choosePhoto(at index: Int, in app: XCUIApplication) {
        // The isolated simulator is seeded with two synthetic product-reference photos via simctl addmedia.
        // Match the picker grid itself, excluding photo icons in the obscured editor underneath it.
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").element(boundBy: index)
        XCTAssertTrue(photo.waitForExistence(timeout: 8), app.debugDescription)
        photo.tap()
        let pickerGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.navigationBars["Photos"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pickerGone], timeout: 8), .completed)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"),
            object: app.buttons["saveRecipe"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let preview = app.images.matching(NSPredicate(format: "identifier BEGINSWITH 'stepPhoto.'"))
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable {
                return
            }
            let form =
                app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
            if element.exists && element.frame.maxY < form.frame.minY + 12 {
                form.swipeDown()
            } else {
                form.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
}
