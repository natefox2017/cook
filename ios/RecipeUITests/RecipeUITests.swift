// Developer: gengyun
// Purpose: Tests RecipeUITests behavior.

import StoreKit
import StoreKitTest
import XCTest

final class RecipeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecipeIngredientsBecomeRealGroceryItems() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        attachScreenshot("Recipe library", app: app)
        openSamplePasta(in: app)
        let addIngredients = app.buttons["addToGroceries"]
        reveal(
            addIngredients, in: app, scrollView: app.scrollViews["recipeDetailScroll"],
            maximumSwipes: 3)
        addIngredients.tap()

        let confirm = app.buttons["confirmAddIngredientsButton"]
        waitUntilReady(confirm)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        let confirmation = app.alerts["Recipe"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8))
        XCTAssertTrue(
            confirmation.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", "added to Groceries.")
            ).firstMatch.exists)
        confirmation.buttons["OK"].tap()

        app.navigationBars.buttons.firstMatch.tap()

        let groceriesTab = app.tabBars.buttons["Groceries"]
        waitUntilReady(groceriesTab)
        groceriesTab.tap()

        let grocery = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "grocery.check.")
        ).firstMatch
        waitUntilReady(grocery)
        XCTAssertEqual(grocery.value as? String, "To buy")
        let groceryIdentifier = grocery.identifier
        grocery.tap()
        let boughtGrocery = app.buttons[groceryIdentifier]
        waitUntilReady(boughtGrocery)
        XCTAssertEqual(boughtGrocery.value as? String, "Bought")
        attachScreenshot("Ingredients added to groceries", app: app)
    }

    @MainActor
    func testManuallyCreatedRecipeCanBeFoundBySearch() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }
        let recipeTitle = "Tomato Toast Smoke Test"

        app.buttons["addRecipeButton"].tap()
        let createManually = app.buttons["createManually"]
        reveal(createManually, in: app, maximumSwipes: 2)
        createManually.tap()

        let name = app.textFields["recipeName"]
        waitUntilReady(name)
        name.tap()
        name.typeText(recipeTitle)

        let ingredient = app.textFields["ingredientName"].firstMatch
        revealFormField(ingredient, in: app)
        ingredient.tap()
        ingredient.typeText("Tomato")
        let amount = app.textFields["ingredientAmount"].firstMatch
        revealFormField(amount, in: app)
        amount.tap()
        amount.typeText("2")

        let instruction = app.descendants(matching: .any).matching(identifier: "stepInstruction")
            .firstMatch
        revealFormField(instruction, in: app)
        instruction.tap()
        instruction.typeText("Slice the tomatoes and arrange them on warm toast.")

        let save = app.buttons["saveRecipe"]
        waitUntilReady(save)
        XCTAssertEqual(save.label, "Save")
        save.tap()
        waitUntilAbsent(save)

        // An editor opened from Add returns to the import sheet. If the app
        // closes both sheets after saving, the library is already ready.
        let libraryAdd = app.buttons["addRecipeButton"]
        if !libraryAdd.isHittable {
            let done = app.navigationBars.buttons["Done"].firstMatch
            waitUntilReady(done)
            done.tap()
        }
        waitUntilReady(libraryAdd)

        let search = app.textFields["recipeSearchField"]
        waitUntilReady(search)
        search.tap()
        search.typeText(recipeTitle)
        let result = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "recipe.", recipeTitle
            )
        ).firstMatch
        waitUntilReady(result)
        XCTAssertEqual(app.staticTexts["recipeCount"].label, "1 Recipe")
        result.tap()
        waitUntilReady(app.buttons["startCooking"])
        XCTAssertTrue(app.staticTexts[recipeTitle].exists)
        attachScreenshot("Manually created recipe", app: app)
    }

    @MainActor
    func testCookingVoiceToggleIsOptInAndStepButtonsRemainAvailable() {
        let app = launchSeededApp()
        defer { app.terminate() }
        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()
        let mic = app.buttons["cookingVoiceToggle"]
        XCTAssertTrue(mic.waitForExistence(timeout: 8))
        XCTAssertTrue(mic.isEnabled)
        XCTAssertFalse(app.staticTexts["cookingVoiceListening"].exists)
        XCTAssertTrue(app.buttons["previousStep"].exists)
        XCTAssertTrue(app.buttons["nextStep"].exists)
        // Do not turn on the microphone in automated simulator tests.
    }

    @MainActor
    func testCookingTimerNavigationAndCompletion() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }
        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()

        assertCookingStep("Step 1 of 3", in: app)
        XCTAssertFalse(app.buttons["previousStep"].isEnabled)
        waitUntilReady(app.buttons["closeCookingButton"])
        attachScreenshot("Cooking full-screen presentation", app: app)
        waitUntilNotHittable(app.tabBars.firstMatch)
        for title in ["Recipes", "Groceries", "Profile"] {
            waitUntilNotHittable(app.tabBars.buttons[title])
        }
        app.buttons["nextStep"].tap()
        assertCookingStep("Step 2 of 3", in: app)

        let startTimer = app.buttons["timerStart"]
        revealCookingTimer(startTimer, in: app)
        startTimer.tap()
        let pauseTimer = app.buttons["timerPause"]
        XCTAssertTrue(pauseTimer.waitForExistence(timeout: 10), app.debugDescription)
        waitUntilReady(pauseTimer)
        pauseTimer.tap()
        waitUntilReady(app.buttons["timerStart"])
        XCTAssertFalse(app.buttons["timerPause"].exists)
        attachScreenshot("Cooking with a paused timer", app: app)

        app.buttons["previousStep"].tap()
        assertCookingStep("Step 1 of 3", in: app)
        app.buttons["nextStep"].tap()
        assertCookingStep("Step 2 of 3", in: app)
        app.buttons["nextStep"].tap()
        assertCookingStep("Step 3 of 3", in: app)
        app.buttons["nextStep"].tap()

        XCTAssertTrue(app.staticTexts["Ready to enjoy"].waitForExistence(timeout: 8))
        waitUntilReady(app.buttons["closeCookingButton"])
        app.buttons["closeCookingButton"].tap()
        waitUntilReady(app.buttons["startCooking"])
        app.navigationBars.buttons.firstMatch.tap()
        waitUntilReady(app.tabBars.buttons["Recipes"])
    }

    @MainActor
    func testComplexCookingStepShowsIngredientsAndMultipleTimers() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000005"]
        reveal(recipe, in: app, maximumSwipes: 4)
        recipe.tap()

        // Create saved progress first, then verify an explicit "Cook from Step"
        // action overrides the restored session position.
        let startCooking = app.buttons["startCooking"]
        waitUntilReady(startCooking)
        startCooking.tap()
        assertCookingStep("Step 1 of 8", in: app)
        waitUntilReady(app.buttons["closeCookingButton"])
        app.buttons["closeCookingButton"].tap()
        waitUntilReady(app.buttons["startCooking"])

        let cookFromStep = app.buttons["cookFromStep.4"]
        revealRecipeStepAction(cookFromStep, in: app)
        cookFromStep.tap()

        assertCookingStep("Step 4 of 8", in: app)
        XCTAssertTrue(app.buttons["cookingStepTemperatureInfo"].waitForExistence(timeout: 8))

        let chicken = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Chicken thighs")
        ).firstMatch
        reveal(chicken, in: app, scrollView: app.scrollViews["cookingScroll"], maximumSwipes: 3)
        XCTAssertTrue(chicken.label.contains("not used"))
        chicken.tap()
        XCTAssertTrue(chicken.label.contains("used"))

        for _ in 0..<2 {
            let start = app.buttons["timerStart"].firstMatch
            revealCookingTimer(start, in: app)
            start.tap()
        }

        let timers = app.buttons["cookingTimersButton"]
        waitUntilReady(timers)
        timers.tap()

        XCTAssertTrue(app.staticTexts["First roast"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Check tray halfway"].exists)
        app.navigationBars.buttons["Done"].tap()

        let next = app.buttons["nextStep"]
        waitUntilReady(next)
        next.tap()
        assertCookingStep("Step 5 of 8", in: app)
        XCTAssertTrue(app.staticTexts["1 done"].waitForExistence(timeout: 8))

        app.buttons["closeCookingButton"].tap()
        let restartAtStepTwo = app.buttons["cookFromStep.2"]
        revealRecipeStepAction(restartAtStepTwo, in: app)
        restartAtStepTwo.tap()
        assertCookingStep("Step 2 of 8", in: app)
        XCTAssertTrue(app.staticTexts["1 done"].exists == false)
    }

    @MainActor
    func testManualTimerCanBeRenamedWithoutStoppingIt() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000005"]
        reveal(recipe, in: app, maximumSwipes: 4)
        recipe.tap()
        let startCooking = app.buttons["startCooking"]
        waitUntilReady(startCooking)
        startCooking.tap()

        let timers = app.buttons["cookingTimersButton"]
        waitUntilReady(timers)
        timers.tap()
        let addTimer = app.buttons["Add"]
        waitUntilReady(addTimer)
        addTimer.tap()

        let name = app.textFields["Name"]
        waitUntilReady(name)
        name.tap()
        name.typeText("Kitchen QA")
        app.navigationBars.buttons["Start"].tap()

        let manualTimer = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "cookingTimerRename.")
        ).firstMatch
        waitUntilReady(manualTimer)
        let timerIdentifier = manualTimer.identifier
        manualTimer.tap()

        let renameAlert = app.alerts["Rename Timer"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 8))
        let renameField = renameAlert.textFields["Timer label"]
        XCTAssertEqual(renameField.value as? String, "Kitchen QA")
        renameField.tap()
        let existingName = renameField.value as? String ?? ""
        renameField.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingName.count)
                + "  Renamed QA  "
        )
        renameAlert.buttons["Save"].tap()

        let renamedTimer = app.buttons[timerIdentifier]
        XCTAssertTrue(renamedTimer.waitForExistence(timeout: 8))
        XCTAssertEqual(renamedTimer.value as? String, "Renamed QA")
        XCTAssertTrue(app.buttons["Pause"].exists)
    }

    @MainActor
    func testRecipeCanBeAddedDirectlyToMealPlan() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }
        openSamplePasta(in: app)

        let options = app.buttons["Recipe Options"]
        waitUntilReady(options)
        options.tap()
        let plan = app.buttons["Add to Meal Plan"]
        waitUntilReady(plan)
        plan.tap()

        let add = app.buttons["Add"]
        waitUntilReady(add)
        add.tap()

        app.navigationBars.buttons.firstMatch.tap()
        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()
        let mealPlan = app.buttons["Meal Plan"]
        waitUntilReady(mealPlan)
        mealPlan.tap()
        XCTAssertTrue(app.staticTexts["Garlic Butter Shrimp Pasta"].waitForExistence(timeout: 8))
        attachScreenshot("Recipe added directly to meal plan", app: app)
    }

    @MainActor
    func testRecipeCanBelongToLocalCollection() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let collections = app.buttons["profile.collections"]
        waitUntilReady(collections)
        collections.tap()

        let name = app.textFields["New collection"]
        waitUntilReady(name)
        name.tap()
        name.typeText("Weeknight")
        let add = app.buttons["Add"]
        waitUntilReady(add)
        add.tap()
        XCTAssertTrue(app.staticTexts["Weeknight"].waitForExistence(timeout: 8))

        app.navigationBars.buttons.firstMatch.tap()

        let recipesTab = app.tabBars.buttons["Recipes"]
        waitUntilReady(recipesTab)
        recipesTab.tap()
        openSamplePasta(in: app)

        let options = app.buttons["Recipe Options"]
        waitUntilReady(options)
        options.tap()
        let manageCollections = app.buttons["Collections"]
        waitUntilReady(manageCollections)
        manageCollections.tap()

        let weeknightMembership = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Weeknight")
        ).firstMatch
        waitUntilReady(weeknightMembership)
        weeknightMembership
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        let membershipEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "In collection"),
            object: weeknightMembership
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [membershipEnabled], timeout: 5), .completed,
            app.debugDescription
        )
        app.navigationBars.buttons["Done"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        profile.tap()
        waitUntilReady(app.buttons["profile.collections"])
        app.buttons["profile.collections"].tap()

        let weeknight = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Weeknight")
        ).firstMatch
        waitUntilReady(weeknight)
        weeknight.tap()

        XCTAssertTrue(
            app.staticTexts["Garlic Butter Shrimp Pasta"].waitForExistence(timeout: 8)
        )
    }

    @MainActor
    func testRootTabsUseNativeTitlesAndSecondaryPagesHideTabBar() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        // Test the hierarchy, not hard-coded pixel coordinates. The native
        // navigation bar owns its title and safe-area placement on each iOS.
        let rootScreens: [(tab: String, title: String)] = [
            ("Recipes", "My Recipes"),
            ("Plan", "Meal Plan"),
            ("Groceries", "Groceries"),
            ("Profile", "Profile"),
        ]
        for screen in rootScreens {
            let tab = app.tabBars.buttons[screen.tab]
            waitUntilReady(tab)
            tab.tap()
            XCTAssertTrue(
                app.navigationBars[screen.title].waitForExistence(timeout: 8),
                "Missing native title for \(screen.tab)"
            )
        }

        let settings = app.buttons["Settings"]
        waitUntilReady(settings)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        waitUntilNotHittable(app.tabBars.firstMatch)
        attachScreenshot("Settings navigation without root tab bar", app: app)

        let settingsBack = app.navigationBars["Settings"].buttons["Profile"]
        waitUntilReady(settingsBack)
        settingsBack.tap()
        waitUntilReady(app.tabBars.buttons["Profile"])

        let savedRecipes = app.buttons["Saved Recipes"]
        reveal(savedRecipes, in: app, maximumSwipes: 4)
        savedRecipes.tap()
        XCTAssertTrue(app.navigationBars["My Recipes"].waitForExistence(timeout: 8))
        waitUntilNotHittable(app.tabBars.firstMatch)
        attachScreenshot("Saved Recipes uses secondary native title", app: app)

        let recipesBack = app.navigationBars["My Recipes"].buttons["Profile"]
        waitUntilReady(recipesBack)
        recipesBack.tap()
        waitUntilReady(app.tabBars.buttons["Profile"])
    }

    @MainActor
    func testRootTabsSwipeBetweenAdjacentScreensWithoutWrapping() {
        let app = launchSeededApp()
        defer { app.terminate() }

        // Swipe from non-interactive regions so native row actions and
        // horizontal date/filter controls keep ownership of their gestures.
        let recipes = app.scrollViews["recipeLibraryScroll"]
        swipeAcrossRoot(recipes, in: app, towardNext: true)
        XCTAssertTrue(app.navigationBars["Meal Plan"].waitForExistence(timeout: 8))

        let mealHeader = app.staticTexts["Breakfast"]
        waitUntilReady(mealHeader)
        swipeAcrossRoot(mealHeader, in: app, towardNext: true)
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 8))

        let groceryHeader = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH %@", " items")
        ).firstMatch
        waitUntilReady(groceryHeader)
        swipeAcrossRoot(groceryHeader, in: app, towardNext: true)
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 8))

        swipeAcrossRoot(app.buttons["Settings"], in: app, towardNext: true)
        XCTAssertTrue(app.navigationBars["Profile"].exists, "The last tab must not wrap")

        swipeAcrossRoot(app.buttons["Settings"], in: app, towardNext: false)
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 8))
        swipeAcrossRoot(groceryHeader, in: app, towardNext: false)
        XCTAssertTrue(app.navigationBars["Meal Plan"].waitForExistence(timeout: 8))
        swipeAcrossRoot(mealHeader, in: app, towardNext: false)
        XCTAssertTrue(app.navigationBars["My Recipes"].waitForExistence(timeout: 8))

        swipeAcrossRoot(recipes, in: app, towardNext: false)
        XCTAssertTrue(app.navigationBars["My Recipes"].exists, "The first tab must not wrap")
        recipes.swipeUp()
        XCTAssertTrue(app.navigationBars["My Recipes"].exists, "Vertical scroll must not change tabs")
    }

    @MainActor
    func testMealPlanWeekHeaderCanSwipeWithoutChangingTabs() {
        let app = launchSeededApp()
        defer { app.terminate() }

        app.tabBars.buttons["Plan"].tap()
        let heading = app.staticTexts["mealplan.weekRange"]
        waitUntilReady(heading)
        let initialWeek = heading.label

        heading.swipeLeft()
        XCTAssertNotEqual(heading.label, initialWeek)
        XCTAssertTrue(app.navigationBars["Meal Plan"].exists)

        heading.swipeRight()
        XCTAssertEqual(heading.label, initialWeek)
        XCTAssertTrue(app.navigationBars["Meal Plan"].exists)
    }

    @MainActor
    func testCookingStepTextSwipesUseExistingStepControls() {
        let app = launchSeededApp()
        defer { app.terminate() }

        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()
        assertCookingStep("Step 1 of 3", in: app)

        let stepContent = app.otherElements["cookingStepSwipeSurface"]
        waitUntilReady(stepContent)
        stepContent.swipeLeft()
        assertCookingStep("Step 2 of 3", in: app)

        stepContent.swipeRight()
        assertCookingStep("Step 1 of 3", in: app)
        XCTAssertFalse(app.buttons["previousStep"].isEnabled)

        app.buttons["nextStep"].tap()
        assertCookingStep("Step 2 of 3", in: app)
        XCTAssertFalse(app.tabBars.buttons["Recipes"].isHittable)
    }

    @MainActor
    func testGroceryLeadingSwipeTogglesStateWithoutBreakingTrailingActions() {
        let app = launchSeededApp()
        defer { app.terminate() }

        openSamplePasta(in: app)
        let addIngredients = app.buttons["addToGroceries"]
        reveal(
            addIngredients, in: app, scrollView: app.scrollViews["recipeDetailScroll"],
            maximumSwipes: 3
        )
        addIngredients.tap()
        let confirm = app.buttons["confirmAddIngredientsButton"]
        waitUntilReady(confirm)
        confirm.tap()
        let alert = app.alerts["Recipe"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.buttons["OK"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Groceries"].tap()

        let grocery = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "grocery.check.")
        ).firstMatch
        waitUntilReady(grocery)
        let groceryID = grocery.identifier
        XCTAssertEqual(grocery.value as? String, "To buy")

        grocery.swipeRight()
        let updatedGrocery = app.buttons[groceryID]
        // Devices may reveal a leading action rather than complete a full swipe.
        if updatedGrocery.value as? String == "To buy" {
            let markBought = app.buttons["Bought"]
            waitUntilReady(markBought)
            markBought.tap()
        }
        XCTAssertEqual(updatedGrocery.value as? String, "Bought")
        XCTAssertTrue(app.navigationBars["Groceries"].exists)

        updatedGrocery.swipeLeft()
        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertTrue(app.navigationBars["Groceries"].exists)
    }

    @MainActor
    func testAddRecipeSheetUsesSingleNativeTitleWithoutTagline() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        app.buttons["addRecipeButton"].tap()
        XCTAssertTrue(app.navigationBars["Add Recipe"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Good food, kept in one place."].exists)
        XCTAssertFalse(app.staticTexts["Add a recipe"].exists)
        XCTAssertTrue(app.textFields["importURL"].waitForExistence(timeout: 8))
        attachScreenshot("Add Recipe native title and compact copy", app: app)

        let done = app.navigationBars["Add Recipe"].buttons["Done"]
        waitUntilReady(done)
        done.tap()
        waitUntilReady(app.buttons["addRecipeButton"])
    }

    @MainActor
    func testProfileLayoutAndPrimaryActionsAreVisible() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let editProfile = app.buttons["profile.edit"]
        waitUntilReady(editProfile)
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.staticTexts["Account & subscription"].exists)
        XCTAssertTrue(app.staticTexts["Your kitchen"].exists)
        attachScreenshot("Profile spacing", app: app)
    }

    @MainActor
    func testAccountScreenShowsAvailableSignInOptions() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let account = app.buttons["Account"]
        waitUntilReady(account)
        account.tap()

        let emailEntry = app.buttons["account.email"]
        XCTAssertTrue(emailEntry.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["account.brand"].label, "Recipe Pals")
        let appleButton = app.buttons["account.apple"]
        let googleButton = app.buttons["account.google"]
        XCTAssertTrue(appleButton.waitForExistence(timeout: 8))
        XCTAssertTrue(googleButton.waitForExistence(timeout: 8))
        XCTAssertEqual(googleButton.frame.height, appleButton.frame.height, accuracy: 2)
        XCTAssertEqual(googleButton.frame.width, appleButton.frame.width, accuracy: 2)

        attachScreenshot("Recipe Pals account sign in sheet", app: app)

        // Both providers and the email entry are shown without extra navigation.
        XCTAssertFalse(app.textFields["Email"].exists)
        emailEntry.tap()
        XCTAssertTrue(app.buttons["account.submit"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Email"].exists)
        XCTAssertFalse(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["account.passwordAlternative"].exists)
        XCTAssertFalse(app.textFields["account.emailCode"].exists)
        attachScreenshot("Expanded account sign in sheet", app: app)

        app.buttons["account.passwordAlternative"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 8))
        app.buttons["account.passwordAlternative"].tap()
        XCTAssertFalse(app.secureTextFields["Password"].exists)

        app.buttons["account.close"].tap()
        XCTAssertTrue(app.buttons["profile.account"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testCookingParameterDetailsDoNotChangeStepProgress() {
        let app = launchSeededApp()
        defer { app.terminate() }

        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000005"]
        reveal(recipe, in: app, maximumSwipes: 4)
        recipe.tap()

        let start = app.buttons["cookFromStep.4"]
        revealRecipeStepAction(start, in: app)
        start.tap()
        assertCookingStep("Step 4 of 8", in: app)

        let temperature = app.buttons["cookingStepTemperatureInfo"]
        reveal(temperature, in: app, scrollView: app.scrollViews["cookingScroll"])
        waitUntilReady(temperature)
        temperature.tap()
        XCTAssertTrue(app.navigationBars["Temperature"].waitForExistence(timeout: 8))
        let conversion = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "428°F")
        ).firstMatch
        XCTAssertTrue(conversion.exists)
        app.navigationBars.buttons["Done"].tap()

        let ingredientInfo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "cookingIngredientInfo.")
        ).firstMatch
        reveal(ingredientInfo, in: app, scrollView: app.scrollViews["cookingScroll"])
        waitUntilReady(ingredientInfo)
        ingredientInfo.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Current amount")
        ).firstMatch.waitForExistence(timeout: 8))
        app.navigationBars.buttons["Done"].tap()
        assertCookingStep("Step 4 of 8", in: app)
    }

    @MainActor
    func testCookingIngredientCheckoffPersistsInSession() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }
        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()
        waitUntilReady(app.buttons["Ingredients"])
        app.buttons["Ingredients"].tap()
        let tomato = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pasta"))
            .firstMatch
        waitUntilReady(tomato)
        tomato.tap()
        XCTAssertTrue(tomato.label.contains("used"))
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Ingredients"].tap()
        let restored = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pasta"))
            .firstMatch
        waitUntilReady(restored)
        XCTAssertTrue(restored.label.contains("used"))
    }

    @MainActor
    func testCookingProgressRestoresAfterAppRelaunch() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()
        waitUntilReady(app.buttons["nextStep"])
        app.buttons["nextStep"].tap()
        assertCookingStep("Step 2 of 3", in: app)

        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--uitesting-reset-cooking-sessions"
        }
        app.launch()
        waitUntilReady(app.buttons["addRecipeButton"])
        openSamplePasta(in: app)
        app.buttons["startCooking"].tap()
        assertCookingStep("Step 2 of 3", in: app)
    }

    @MainActor
    func testDataPrivacyRowsUseConciseAccountDeletionLabel() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        openDataAndPrivacy(in: app)

        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Privacy Summary"].exists)
        XCTAssertFalse(app.buttons["What Recipe Pals Stores"].exists)

        // Match either the signed-in button or the signed-out informational row.
        let deleteAccount = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Delete Account & Cloud Data")
        ).firstMatch
        XCTAssertTrue(deleteAccount.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "Delete Recipe Pals Account")
            ).firstMatch.exists
        )
    }

    @MainActor
    func testBothLocalDeletionEntryPointsPresentCenteredCancelableAlerts() {
        let app = launchSeededApp()
        defer { app.terminate() }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let profileDelete = app.buttons["profile.delete-data"]
        reveal(profileDelete, in: app, maximumSwipes: 5)
        profileDelete.tap()

        let profileAlert = app.alerts["Delete all local data?"]
        XCTAssertTrue(profileAlert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(profileAlert.buttons["Delete Local Data"].exists)
        XCTAssertLessThan(
            abs(profileAlert.frame.midY - app.frame.midY),
            app.frame.height * 0.20
        )
        profileAlert.buttons["Cancel"].tap()

        openDataAndPrivacy(in: app)
        let settingsDelete = app.buttons["privacy.delete-local"]
        reveal(settingsDelete, in: app, maximumSwipes: 5)
        settingsDelete.tap()

        let settingsAlert = app.alerts["Delete all local data?"]
        XCTAssertTrue(settingsAlert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(settingsAlert.buttons["Delete Local Data"].exists)
        XCTAssertLessThan(
            abs(settingsAlert.frame.midY - app.frame.midY),
            app.frame.height * 0.20
        )
        settingsAlert.buttons["Cancel"].tap()
        XCTAssertTrue(settingsDelete.exists)
    }

    @MainActor
    func testManualLanguageSelectionOverridesEnglishTestDefault() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-reset-language"]
        app.launch()
        defer { app.terminate() }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let settings = app.buttons["Settings"]
        reveal(settings, in: app, maximumSwipes: 5)
        settings.tap()
        let languageAndCountry = app.buttons["Language & Country"]
        reveal(languageAndCountry, in: app, maximumSwipes: 6)
        languageAndCountry.tap()

        let picker = app.buttons["settings.languagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        picker.tap()
        let japanese = app.staticTexts["日本語"].firstMatch
        XCTAssertTrue(japanese.waitForExistence(timeout: 5), app.debugDescription)
        japanese.tap()
        XCTAssertTrue(
            app.navigationBars["言語と国・地域"].waitForExistence(timeout: 8),
            app.debugDescription
        )
        XCTAssertTrue(app.staticTexts["アプリの言語"].exists)
    }

    @MainActor
    func testExportFormatsAreAvailableInBothEntryPoints() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let profileExport = app.buttons["profile.export"]
        reveal(profileExport, in: app, maximumSwipes: 5)
        let exportRowFrame = profileExport.frame
        attachScreenshot("Profile export trigger", app: app)
        profileExport.tap()
        for format in ["Recipes (JSON)", "Recipes (HTML)", "All Local Library Data (JSON)"] {
            XCTAssertTrue(app.buttons[format].waitForExistence(timeout: 5))
        }
        attachScreenshot("Profile export format chooser", app: app)
        if #available(iOS 27.0, *) {
            // The native popover must point to the export row, not the whole List.
            XCTAssertGreaterThanOrEqual(
                app.buttons["All Local Library Data (JSON)"].frame.maxY,
                exportRowFrame.minY - 60,
                "Export choices appeared far above their triggering row."
            )
        }
        app.buttons["Recipes (JSON)"].tap()
        let profileExportCancel = fileExporterCancel(in: app)
        XCTAssertTrue(
            profileExportCancel.waitForExistence(timeout: 8),
            app.debugDescription
        )
        profileExportCancel.tap()

        app.terminate()
        let settingsApp = launchSeededApp()
        defer {
            settingsApp.terminate()
        }

        let profileTab = settingsApp.tabBars.buttons["Profile"]
        waitUntilReady(profileTab)
        profileTab.tap()

        let settings = settingsApp.buttons["Settings"]
        reveal(settings, in: settingsApp, maximumSwipes: 5)
        settings.tap()

        let dataAndPrivacy = settingsApp.buttons["Data & Privacy"]
        reveal(dataAndPrivacy, in: settingsApp, maximumSwipes: 6)
        dataAndPrivacy.tap()

        let settingsExport = settingsApp.buttons["Export Data"]
        waitUntilReady(settingsExport)
        settingsExport.tap()
        for format in ["Recipes (JSON)", "Recipes (HTML)", "All Local Library Data (JSON)"] {
            XCTAssertTrue(settingsApp.buttons[format].waitForExistence(timeout: 5))
        }
        attachScreenshot("Settings export format chooser", app: settingsApp)
        settingsApp.buttons["Recipes (HTML)"].tap()
        let settingsExportCancel = fileExporterCancel(in: settingsApp)
        XCTAssertTrue(
            settingsExportCancel.waitForExistence(timeout: 8),
            settingsApp.debugDescription
        )
        settingsExportCancel.tap()
        attachScreenshot("Export format choices", app: settingsApp)
    }

    @MainActor
    func testExportQAFailureFeedbackIsClearlyInjectedFromBothEntryPoints() {
        let app = launchExportQAApp(injectPermissionFailure: true)
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let export = app.buttons["profile.export"]
        reveal(export, in: app, maximumSwipes: 5)
        export.tap()
        app.buttons["Recipes (JSON)"].tap()
        let cancel = fileExporterCancel(in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
        cancel.tap()

        let injectedFeedback = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "QA-INJECTED file-write permission denial")
        ).firstMatch
        XCTAssertTrue(injectedFeedback.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(injectedFeedback.label.contains("not a Files provider error"))
        attachScreenshot("Profile export QA injected failure feedback", app: app)
        app.alerts.buttons["OK"].tap()

        openDataAndPrivacy(in: app)
        let settingsExport = app.buttons["Export Data"]
        waitUntilReady(settingsExport)
        settingsExport.tap()
        app.buttons["Recipes (HTML)"].tap()
        let settingsCancel = fileExporterCancel(in: app)
        XCTAssertTrue(settingsCancel.waitForExistence(timeout: 8), app.debugDescription)
        settingsCancel.tap()

        let settingsFeedback = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "QA-INJECTED file-write permission denial")
        ).firstMatch
        XCTAssertTrue(settingsFeedback.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(settingsFeedback.label.contains("not a Files provider error"))
        attachScreenshot("Settings export QA injected failure feedback", app: app)
    }

    @MainActor
    func testExportQAProfileDeletionStaysEmptyAfterRestart() {
        let app = launchExportQAApp()
        deleteLocalDataFromProfile(in: app)
        app.terminate()

        let relaunchedApp = launchExportQAApp(resetFixture: false, expectsSeededFixture: false)
        defer {
            relaunchedApp.terminate()
        }
        XCTAssertTrue(relaunchedApp.buttons["loadSampleRecipes"].waitForExistence(timeout: 8))
        XCTAssertFalse(relaunchedApp.buttons[Self.exportQAFixtureRecipeIdentifier].exists)
    }

    @MainActor
    func testExportQASettingsDeletionStaysEmptyAfterRestart() {
        let app = launchExportQAApp()
        openDataAndPrivacy(in: app)

        let delete = app.buttons["privacy.delete-local"]
        reveal(delete, in: app, maximumSwipes: 5)
        delete.tap()
        let confirm = app.alerts["Delete all local data?"].buttons["Delete Local Data"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(
            app.staticTexts["Local Recipe Pals data deleted."].waitForExistence(timeout: 8),
            app.debugDescription
        )
        app.terminate()

        let relaunchedApp = launchExportQAApp(resetFixture: false, expectsSeededFixture: false)
        defer {
            relaunchedApp.terminate()
        }
        XCTAssertTrue(relaunchedApp.buttons["loadSampleRecipes"].waitForExistence(timeout: 8))
        XCTAssertFalse(relaunchedApp.buttons[Self.exportQAFixtureRecipeIdentifier].exists)
    }

    @MainActor
    private func launchExportQAApp(
        injectPermissionFailure: Bool = false,
        resetFixture: Bool = true,
        expectsSeededFixture: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-export-qa",
            "--uitesting-reset-cooking-sessions",
            "--uitesting-locale",
            "en",
        ]
        if resetFixture {
            app.launchArguments.append("--uitesting-export-qa-reset")
        }
        if injectPermissionFailure {
            app.launchArguments.append(
                "--uitesting-export-qa-inject-write-permission-denial"
            )
        }
        app.launch()
        if expectsSeededFixture {
            XCTAssertTrue(
                app.buttons[Self.exportQAFixtureRecipeIdentifier].waitForExistence(timeout: 8),
                app.debugDescription
            )
        } else {
            XCTAssertTrue(app.buttons["loadSampleRecipes"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons[Self.exportQAFixtureRecipeIdentifier].exists)
        }
        return app
    }

    @MainActor
    private func openDataAndPrivacy(in app: XCUIApplication) {
        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let settings = app.buttons["Settings"]
        reveal(settings, in: app, maximumSwipes: 5)
        settings.tap()

        let dataAndPrivacy = app.buttons["Data & Privacy"]
        reveal(dataAndPrivacy, in: app, maximumSwipes: 6)
        dataAndPrivacy.tap()
    }

    @MainActor
    private func deleteLocalDataFromProfile(in app: XCUIApplication) {
        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let delete = app.buttons["profile.delete-data"]
        reveal(delete, in: app, maximumSwipes: 5)
        delete.tap()
        let confirm = app.alerts["Delete all local data?"].buttons["Delete Local Data"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(
            app.staticTexts["Local Recipe Pals data deleted."].waitForExistence(timeout: 8),
            app.debugDescription
        )
    }

    private static let exportQAFixtureRecipeIdentifier =
        "recipe.BF80A79C-A36C-6C5A-AA23-15B5E66BAF06"

    @MainActor
    func testSubscriptionOpensFromProfileAndSettings() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let premium = app.buttons["Premium"]
        reveal(premium, in: app, maximumSwipes: 4)
        premium.tap()
        XCTAssertTrue(app.staticTexts["Recipe Pals Premium"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        attachScreenshot("Subscription from Profile", app: app)

        app.navigationBars.buttons.firstMatch.tap()
        let settings = app.buttons["Settings"]
        reveal(settings, in: app, maximumSwipes: 4)
        settings.tap()

        let subscription = app.buttons["Subscription"]
        reveal(subscription, in: app, maximumSwipes: 4)
        subscription.tap()

        XCTAssertTrue(app.staticTexts["Recipe Pals Premium"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        attachScreenshot("Subscription from Settings", app: app)
    }

    @MainActor
    func testOnboardingPreservesApprovedAIStoryAndPaywall() {
        let app = launchOnboardingApp(productIDs: "")
        defer {
            app.terminate()
        }

        // Keep the approved story order and AI-first messaging through future merges.
        XCTAssertTrue(app.staticTexts["Create with AI"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts[
                "Tell AI what you’re craving or list the ingredients you have. Start with a recipe idea."
            ].exists
        )
        let next = app.buttons["onboarding.primary"]
        waitUntilReady(next)
        XCTAssertEqual(next.label, "Next")

        next.tap()
        XCTAssertTrue(app.staticTexts["Save recipe links"].waitForExistence(timeout: 8))
        waitUntilReady(next)
        next.tap()
        XCTAssertTrue(app.staticTexts["Import social recipes"].waitForExistence(timeout: 8))
        waitUntilReady(next)
        XCTAssertEqual(next.label, "See Plans")

        next.tap()
        XCTAssertTrue(app.staticTexts["Recipe Pals Premium"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Create with AI"].exists)
        let annual = app.buttons["subscription.plan.annual.unavailable"]
        let monthly = app.buttons["subscription.plan.monthly.unavailable"]
        XCTAssertTrue(annual.isSelected)
        XCTAssertGreaterThan(annual.frame.minY, monthly.frame.minY)
        XCTAssertTrue(app.buttons["onboarding.plan.free"].exists)
        XCTAssertTrue(app.buttons["subscription.restore"].exists)
        attachScreenshot("Approved AI-first onboarding and Premium", app: app)
    }

    @MainActor
    func testOnboardingPaywallFreeAndClosePaths() {
        let app = launchOnboardingApp(productIDs: "")
        defer {
            app.terminate()
        }
        waitUntilReady(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        waitUntilReady(app.buttons["onboarding.plan.free"])
        let continueFree = app.buttons["onboarding.purchase"]
        XCTAssertTrue(continueFree.waitForExistence(timeout: 8))
        XCTAssertEqual(continueFree.label, "Subscribe")
        XCTAssertFalse(continueFree.isEnabled)
        let annual = app.buttons["subscription.plan.annual.unavailable"]
        let monthly = app.buttons["subscription.plan.monthly.unavailable"]
        XCTAssertTrue(annual.isSelected)
        XCTAssertGreaterThan(annual.frame.minY, monthly.frame.minY)
        XCTAssertTrue(app.buttons["onboarding.close"].isHittable)
        XCTAssertTrue(app.buttons["subscription.restore"].isHittable)
        attachScreenshot("Product Design subscription - actual unavailable plans", app: app)
        app.buttons["onboarding.plan.free"].tap()
        waitUntilReady(app.buttons["addRecipeButton"])

        app.terminate()
        app.launch()
        waitUntilReady(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        waitUntilReady(app.buttons["onboarding.close"])
        app.buttons["onboarding.close"].tap()
        waitUntilReady(app.buttons["addRecipeButton"])

        app.terminate()
        app.launchArguments = [
            "--uitesting", "--uitesting-onboarding", "--uitesting-locale", "zh-Hans",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["用 AI 创作"].waitForExistence(timeout: 8))
        waitUntilReady(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["私人菜谱高级版"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["onboarding.purchase"].waitForExistence(timeout: 8))
        attachScreenshot("Product Design subscription - Chinese layout smoke", app: app)
    }

    @MainActor
    func testOnboardingPaywallAccessibilitySizeKeepsFreeExitReachable() {
        let app = launchOnboardingApp(productIDs: "", accessibilitySize: true)
        defer {
            app.terminate()
        }
        waitUntilReady(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        let action = app.buttons["onboarding.plan.free"]
        reveal(action, in: app, maximumSwipes: 12)
        XCTAssertTrue(action.isHittable)
        attachScreenshot("Product Design subscription - accessibility size", app: app)
        action.tap()
        waitUntilReady(app.buttons["addRecipeButton"])
    }

    @MainActor
    func testOnboardingLocalStoreKitPurchaseContinuesWithoutSecondPurchase() async throws {
        let session = try makeStoreKitTestSession()
        defer {
            reset(session)
        }
        let app = launchOnboardingApp(productIDs: Self.localStoreKitProductID)
        defer {
            app.terminate()
        }
        waitUntilReady(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        let monthly = app.buttons["subscription.plan.\(Self.localStoreKitProductID)"]
        waitUntilReady(monthly)
        monthly.tap()
        let action = app.buttons["onboarding.purchase"]
        waitUntilReady(action)
        XCTAssertEqual(action.label, "Subscribe")
        XCTAssertTrue(app.staticTexts["Auto-renews until canceled in the App Store."].exists)
        attachScreenshot("Product Design subscription - local StoreKit fixture only", app: app)

        let annual = app.buttons["subscription.plan.annual.unavailable"]
        annual.tap()
        XCTAssertFalse(action.isEnabled)
        monthly.tap()
        action.tap()
        XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 12))
        XCTAssertEqual(action.label, "Continue")
        action.tap()
        waitUntilReady(app.buttons["addRecipeButton"])
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    @MainActor
    func testLocalStoreKitPurchaseAndRestoreWithoutAppStoreAccount() async throws {
        let session = try makeStoreKitTestSession()
        defer {
            reset(session)
        }

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer {
            app.terminate()
        }
        openSubscription(in: app)

        let restore = app.buttons["subscription.restore"]
        waitUntilReady(restore)
        restore.tap()

        let restoreMessage = app.alerts["Subscription"]
        XCTAssertTrue(restoreMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(
            restoreMessage.staticTexts[
                "No active Recipe Pals subscription was found for this App Store account."
            ].exists
        )
        restoreMessage.buttons["OK"].tap()

        let localProduct = app.buttons["subscription.plan.\(Self.localStoreKitProductID)"]
        waitUntilReady(localProduct)
        localProduct.tap()
        let purchase = app.buttons["subscription.purchase"]
        waitUntilReady(purchase)
        purchase.tap()

        XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    @MainActor
    func testFormalMonthlyAndAnnualPlansHaveNoTrialWithDefaultBuildConfiguration() throws {
        let session = try makeStoreKitTestSession()
        session.locale = Locale(identifier: "en_US")
        session.storefront = "USA"
        defer {
            reset(session)
        }

        // These are local transactions using the formal IDs, not ASC Sandbox purchases.
        for productID in [
            "com.shopkivoo.recipe.pro.monthly",
            "com.shopkivoo.recipe.pro.yearly",
        ] {
            session.clearTransactions()
            let app = launchSeededApp()
            openSubscription(in: app)

            let monthly = app.buttons["subscription.plan.com.shopkivoo.recipe.pro.monthly"]
            let annual = app.buttons["subscription.plan.com.shopkivoo.recipe.pro.yearly"]
            XCTAssertTrue(monthly.waitForExistence(timeout: 8))
            XCTAssertTrue(annual.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["$4.99"].exists)
            XCTAssertTrue(app.staticTexts["$39.99"].exists)
            XCTAssertFalse(app.staticTexts["$5.99"].exists)
            XCTAssertFalse(app.buttons["Start Free Trial"].exists)

            let plan = app.buttons["subscription.plan.\(productID)"]
            plan.tap()
            let purchase = app.buttons["subscription.purchase"]
            XCTAssertEqual(purchase.label, "Subscribe")
            XCTAssertTrue(purchase.isEnabled)
            attachScreenshot("Formal IDs, local StoreKit, no introductory offer", app: app)
            purchase.tap()
            XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
            XCTAssertEqual(session.allTransactions().count, 1)
            app.terminate()
        }
    }

    @MainActor
    func testFormalDefaultBuildPreservesLegacySubscriptionAndLifetimeEntitlements() async throws {
        let session = try makeStoreKitTestSession()
        defer {
            reset(session)
        }

        for productID in [
            "com.natefox.cookapp.pro.monthly",
            "com.natefox.cookapp.lifetime",
        ] {
            session.clearTransactions()
            _ = try await session.buyProduct(identifier: productID)
            let app = launchSeededApp()
            openSubscription(in: app)
            XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["subscription.purchase"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testLocalStoreKitLoadFailureKeepsRetryAndRestoreAvailable() async throws {
        let session = try makeStoreKitTestSession()
        defer {
            reset(session)
        }
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer {
            app.terminate()
        }
        openSubscription(in: app)

        XCTAssertTrue(
            app.staticTexts["Premium plans aren’t available right now."].waitForExistence(
                timeout: 8)
        )
        let restore = app.buttons["subscription.restore"]
        waitUntilReady(restore)
        restore.tap()

        let restoreMessage = app.alerts["Subscription"]
        XCTAssertTrue(restoreMessage.waitForExistence(timeout: 8))
        XCTAssertFalse(
            restoreMessage.staticTexts[
                "No active Recipe Pals subscription was found for this App Store account."
            ].exists
        )
        restoreMessage.buttons["OK"].tap()

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        let retry = app.buttons["subscription.retry"]
        waitUntilReady(retry)
        retry.tap()
        waitUntilReady(app.buttons["subscription.plan.\(Self.localStoreKitProductID)"])
    }

    @MainActor
    func testLocalStoreKitLoadFailurePreservesVerifiedEntitlement() async throws {
        let session = try makeStoreKitTestSession()
        defer {
            reset(session)
        }
        _ = try await session.buyProduct(identifier: Self.localStoreKitProductID)
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer {
            app.terminate()
        }
        openSubscription(in: app)

        XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["subscription.retry"].exists)
    }

    @MainActor
    func testRestoreExplainsWhenSubscriptionProductsAreUnconfigured() {
        let app = launchSeededApp(storeKitTestProductID: "")
        defer {
            app.terminate()
        }
        openSubscription(in: app)

        let restore = app.buttons["subscription.restore"]
        waitUntilReady(restore)
        restore.tap()

        let restoreMessage = app.alerts["Subscription"]
        XCTAssertTrue(restoreMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(
            restoreMessage.staticTexts[
                "Subscription products have not been configured in App Store Connect."
            ].exists
        )
        XCTAssertFalse(
            restoreMessage.staticTexts[
                "No active Recipe Pals subscription was found for this App Store account."
            ].exists
        )
    }

    @MainActor
    func testSimplifiedChineseLocaleDisplaysLocalizedUI() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-locale", "zh-Hans"]
        app.launch()
        defer {
            app.terminate()
        }

        // The selected locale is explicit so the result does not depend on simulator settings.
        XCTAssertTrue(app.tabBars.buttons["食谱"].waitForExistence(timeout: 10))
        let profile = app.tabBars.buttons["我的"]
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        profile.tap()
        XCTAssertTrue(app.staticTexts["我的厨房"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["账号"].exists)
        XCTAssertTrue(app.buttons["会员"].exists)
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["账号"].exists)
        attachScreenshot("Simplified Chinese interface", app: app)
    }

    @MainActor
    func testAboutSettingsUsesShortTitleAndCurrentAppDetails() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let settings = app.buttons["Settings"]
        reveal(settings, in: app, maximumSwipes: 4)
        settings.tap()

        let about = app.buttons["About"]
        reveal(about, in: app, maximumSwipes: 5)
        about.tap()

        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Recipe Pals"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Version"].exists)
        XCTAssertTrue(app.buttons["Open Source Licenses"].exists)
        XCTAssertTrue(app.buttons["Acknowledgements"].exists)
        attachScreenshot("About title and app details", app: app)
    }

    @MainActor
    func testFourLocaleTabLabelsUseStringCatalog() {
        // Locale overrides stay scoped to the app and never change global AppleLanguages.
        let examples: [(String, String, String, String, String, String, String, String)] = [
            (
                "en", "Recipes", "Recipe", "Profile", "Settings", "Account", "Premium",
                "Your kitchen"
            ),
            ("zh-Hans", "食谱", "份食谱", "我的", "设置", "账号", "会员", "我的厨房"),
            ("zh-Hant", "食譜", "份食譜", "個人", "設定", "帳號", "會員", "我的廚房"),
            ("ja", "レシピ", "件のレシピ", "マイページ", "設定", "アカウント", "プレミアム", "マイキッチン"),
        ]

        for (
            language, recipesLabel, countNoun, profileLabel, settingsTitle,
            accountLabel, premiumLabel, kitchenLabel
        ) in examples {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--uitesting-locale", language]
            app.launch()
            XCTAssertTrue(
                app.tabBars.buttons[recipesLabel].waitForExistence(timeout: 10),
                "Missing localized Recipes tab for \(language)"
            )
            XCTAssertTrue(app.buttons["addRecipeButton"].exists)
            let recipeCount = app.staticTexts["recipeCount"]
            XCTAssertTrue(
                recipeCount.waitForExistence(timeout: 10),
                "Missing recipe-count label for \(language)"
            )
            XCTAssertTrue(
                recipeCount.label.contains(countNoun),
                "Recipe count not localized for \(language): \(recipeCount.label)"
            )

            let profileTab = app.tabBars.buttons[profileLabel]
            XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
            profileTab.tap()
            XCTAssertTrue(
                app.staticTexts[kitchenLabel].waitForExistence(timeout: 8),
                "Default kitchen name not localized for \(language)"
            )
            XCTAssertTrue(
                app.buttons[accountLabel].exists,
                "Profile account row not localized for \(language)"
            )
            XCTAssertTrue(
                app.buttons[premiumLabel].exists,
                "Profile premium row not localized for \(language)"
            )
            let settingsLink = app.buttons[settingsTitle]
            XCTAssertTrue(settingsLink.waitForExistence(timeout: 8))
            settingsLink.tap()
            XCTAssertTrue(
                app.navigationBars[settingsTitle].waitForExistence(timeout: 8),
                "Settings screen not localized for \(language)"
            )
            XCTAssertTrue(
                app.buttons[accountLabel].exists,
                "Settings account row not localized for \(language)"
            )
            attachScreenshot("Localized settings \(language)", app: app)
            app.terminate()
        }
    }

    @MainActor
    func testSettingsRemainReachableAtAccessibilityDynamicType() {
        let locales: [(String, String, String, String, String, String)] = [
            (
                "en", "Profile", "Settings", "Account", "Subscription",
                "Cloud Sync"
            ),
            (
                "ja", "マイページ", "設定", "アカウント", "サブスクリプション",
                "クラウド同期"
            ),
        ]

        for (
            language, profileLabel, settingsTitle, accountLabel, subscriptionLabel,
            cloudSyncLabel
        ) in locales {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--uitesting-locale", language]
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] =
                "UICTContentSizeCategoryAccessibilityXXXL"
            app.launch()

            let profileTab = app.tabBars.buttons[profileLabel]
            XCTAssertTrue(profileTab.waitForExistence(timeout: 10))
            profileTab.tap()

            let settingsLink = app.buttons[settingsTitle]
            XCTAssertTrue(settingsLink.waitForExistence(timeout: 8))
            settingsLink.tap()

            XCTAssertTrue(app.navigationBars[settingsTitle].waitForExistence(timeout: 8))

            let accountRow = app.buttons[accountLabel]
            XCTAssertTrue(accountRow.waitForExistence(timeout: 8))
            XCTAssertLessThanOrEqual(
                accountRow.frame.height,
                110,
                "The \(language) account row should stay on one line at Accessibility XXXL"
            )

            let subscriptionRow = app.buttons[subscriptionLabel]
            XCTAssertTrue(subscriptionRow.waitForExistence(timeout: 8))
            XCTAssertLessThanOrEqual(
                subscriptionRow.frame.height,
                110,
                "The \(language) subscription row should stay on one line at Accessibility XXXL"
            )

            XCTAssertTrue(app.buttons[cloudSyncLabel].exists)
            attachScreenshot("Settings Accessibility XXXL \(language)", app: app)
            app.terminate()
        }
    }

    @MainActor
    private func launchOnboardingApp(productIDs: String, accessibilitySize: Bool = false)
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-onboarding", "--uitesting-locale", "en"]
        if accessibilitySize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launchEnvironment["RECIPE_STOREKIT_TEST_PRODUCT_IDS"] = productIDs
        app.launch()
        return app
    }

    @MainActor
    private func launchSeededApp(storeKitTestProductID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-reset-cooking-sessions",
            "--uitesting-locale",
            "en",
        ]
        if let storeKitTestProductID {
            app.launchEnvironment["RECIPE_STOREKIT_TEST_PRODUCT_IDS"] = storeKitTestProductID
        }
        app.launch()
        waitUntilReady(app.buttons["addRecipeButton"])
        waitUntilReady(app.buttons["recipe.C0010000-0000-4000-8000-000000000001"])
        return app
    }

    private static let localStoreKitProductID = "com.recipepouch.localtest.premium.monthly"

    private func makeStoreKitTestSession() throws -> SKTestSession {
        let configurationURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "RecipeSubscriptionTests",
                withExtension: "storekit"
            )
        )
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func reset(_ session: SKTestSession) {
        session.clearTransactions()
        session.resetToDefaultState()
    }

    @MainActor
    private func openSubscription(in app: XCUIApplication) {
        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let premium = app.buttons["Premium"]
        reveal(premium, in: app, maximumSwipes: 4)
        premium.tap()
        XCTAssertTrue(app.staticTexts["Recipe Pals Premium"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func fileExporterCancel(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"]))
            .firstMatch
    }

    @MainActor
    private func openSamplePasta(in app: XCUIApplication) {
        let recipe = app.buttons["recipe.C0010000-0000-4000-8000-000000000001"]
        waitUntilReady(recipe)
        recipe.tap()
        waitUntilReady(app.buttons["startCooking"])
    }

    @MainActor
    private func assertCookingStep(
        _ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let progress = app.staticTexts["cookingStepProgress"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: progress)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            "Cooking did not reach \(label)",
            file: file, line: line)
    }

    @MainActor
    private func swipeAcrossRoot(
        _ element: XCUIElement,
        in app: XCUIApplication,
        towardNext: Bool
    ) {
        // Drag across the non-interactive portion of the same row. Short
        // header labels are not wide enough for the intentional 96-pt threshold.
        let normalizedY = (element.frame.midY - app.frame.minY) / app.frame.height
        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: towardNext ? 0.82 : 0.18, dy: normalizedY)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: towardNext ? 0.18 : 0.82, dy: normalizedY)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func waitUntilReady(
        _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate(
            format: "exists == true AND hittable == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
            "Element is not ready: \(element)", file: file, line: line)
    }

    @MainActor
    private func waitUntilAbsent(
        _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            "Element did not dismiss: \(element)", file: file, line: line)
    }

    @MainActor
    private func waitUntilNotHittable(
        _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == false OR hittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            "Underlying navigation remains interactive: \(element)", file: file, line: line)
    }

    @MainActor
    private func revealFormField(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Commit the previous single-line field before finding the next row.
        // The Form also dismisses any remaining keyboard during scrolling.
        if app.keyboards.firstMatch.exists {
            for title in ["Done", "Return", "return"] {
                let key = app.keyboards.firstMatch.buttons[title]
                if key.exists && key.isHittable {
                    key.tap()
                    break
                }
            }
        }

        for _ in 0..<4 {
            if element.exists && element.isHittable {
                break
            }
            let candidates =
                app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex
                + app.scrollViews.allElementsBoundByIndex
            guard
                let form = candidates.first(where: {
                    $0.exists && $0.isHittable && $0.frame.height > 200
                })
            else {
                attachScreenshot("No visible editor form", app: app)
                XCTFail("No visible form can scroll to \(element)", file: file, line: line)
                return
            }
            if element.exists && element.frame.height > 0
                && element.frame.maxY <= form.frame.minY + 12
            {
                form.swipeDown(velocity: .slow)
            } else {
                form.swipeUp(velocity: .slow)
            }
        }
        if !element.exists || !element.isHittable {
            attachScreenshot("Editor field not visible after scrolling", app: app)
        }
        waitUntilReady(element, file: file, line: line)
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, scrollView: XCUIElement? = nil,
        maximumSwipes: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<maximumSwipes {
            if element.exists && element.isHittable {
                break
            }
            if let scrollView, scrollView.exists {
                scrollView.swipeUp()
            } else if app.collectionViews.firstMatch.exists {
                app.collectionViews.firstMatch.swipeUp()
            } else {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
        waitUntilReady(element, file: file, line: line)
    }

    @MainActor
    private func revealCookingTimer(
        _ timer: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scrollView = app.scrollViews["cookingScroll"]
        let previousStep = app.buttons["previousStep"]

        for _ in 0..<5 {
            if timer.exists && timer.isHittable
                && timer.frame.maxY <= previousStep.frame.minY
            {
                break
            }
            scrollView.swipeUp()
        }

        waitUntilReady(timer, file: file, line: line)
        XCTAssertLessThanOrEqual(
            timer.frame.maxY, previousStep.frame.minY,
            "The timer control must sit above the fixed cooking controls.",
            file: file, line: line
        )
    }

    @MainActor
    private func revealRecipeStepAction(
        _ action: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scrollView = app.scrollViews["recipeDetailScroll"]
        let startCooking = app.buttons["startCooking"]

        for _ in 0..<8 {
            if action.exists && action.isHittable
                && action.frame.maxY <= startCooking.frame.minY
            {
                break
            }
            if action.exists && action.frame.maxY < scrollView.frame.minY {
                scrollView.swipeDown()
            } else {
                scrollView.swipeUp()
            }
        }

        if !action.exists {
            for _ in 0..<8 {
                if action.exists && action.isHittable
                    && action.frame.maxY <= startCooking.frame.minY
                {
                    break
                }
                scrollView.swipeDown()
            }
        }

        waitUntilReady(action, file: file, line: line)
        XCTAssertLessThanOrEqual(
            action.frame.maxY, startCooking.frame.minY,
            "The step action must sit above the fixed recipe controls.",
            file: file, line: line
        )
    }

    @MainActor
    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
