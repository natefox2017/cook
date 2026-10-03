import XCTest

@MainActor
final class CookUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testNativeTabsAndURLValidation() {
        XCTAssertTrue(app.tabBars.buttons["Recipes"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.navigationBars["Groceries"].exists)
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your personal cookbook"].exists)
        app.tabBars.buttons["Recipes"].tap()
        app.buttons["Add"].tap()
        let link = app.textFields["Paste a recipe link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("invalid-link")
        app.buttons["Save link"].tap()
        XCTAssertTrue(app.staticTexts["Enter a complete http or https recipe link."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Recipes"].exists)
        attachScreenshot("Native tabs and source validation")
    }

    func testManualRecipePersistsAndTimerRemainsVisible() {
        let title = "UI Test \(UUID().uuidString.prefix(6))"
        app.buttons["Add"].tap()
        app.buttons["Other ways"].tap()
        app.buttons["Create manually"].tap()
        let name = app.textFields["Recipe name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(title)
        app.swipeUp()
        app.buttons["Add ingredient"].tap()
        let ingredient = app.textFields["Ingredient"]
        ingredient.tap()
        ingredient.typeText("Salt")
        app.textFields["Amount or “to taste”"].tap()
        app.textFields["Amount or “to taste”"].typeText("to taste")
        app.swipeUp()
        app.buttons["Add step"].tap()
        let instruction = app.textFields["What to do"]
        instruction.tap()
        instruction.typeText("Rest for one minute.")
        app.swipeUp()
        app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Timer:")).buttons["Increment"].firstMatch.tap()
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.staticTexts[title].tap()
        app.swipeUp()
        app.buttons["Start cooking"].tap()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 5))
        app.buttons["Start timer"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].exists)
        app.buttons["Reset"].tap()
        XCTAssertTrue(app.buttons["Start timer"].exists)
        attachScreenshot("Cooking timer controls")
        app.buttons["Close"].tap()
        app.buttons["Add to groceries"].tap()
        XCTAssertTrue(app.staticTexts["Adjust servings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["to taste"].exists)
        app.buttons["servings.addToGroceries"].tap()
        app.tabBars.buttons["Groceries"].tap()
        XCTAssertTrue(app.staticTexts["Salt"].waitForExistence(timeout: 5))
        app.buttons["Mark Salt bought"].tap()
        XCTAssertTrue(app.buttons["Mark Salt not bought"].exists)
        attachScreenshot("Groceries preserve uncertain quantity")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
