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
        defer { app.terminate() }

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
        defer { app.terminate() }
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
    func testCookingTimerNavigationAndCompletion() {
        let app = launchSeededApp()
        defer { app.terminate() }
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
        reveal(startTimer, in: app, scrollView: app.scrollViews["cookingScroll"], maximumSwipes: 2)
        startTimer.tap()
        let pauseTimer = app.buttons["timerPause"]
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
        waitUntilReady(app.tabBars.buttons["Recipes"])
    }

    @MainActor
    func testComplexCookingStepShowsIngredientsAndMultipleTimers() {
        let app = launchSeededApp()
        defer { app.terminate() }

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
        reveal(
            cookFromStep,
            in: app,
            scrollView: app.scrollViews["recipeDetailScroll"],
            maximumSwipes: 8
        )
        cookFromStep.tap()

        assertCookingStep("Step 4 of 8", in: app)
        XCTAssertTrue(app.staticTexts["220°C"].waitForExistence(timeout: 8))

        let chicken = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Chicken thighs")
        ).firstMatch
        reveal(chicken, in: app, scrollView: app.scrollViews["cookingScroll"], maximumSwipes: 3)
        XCTAssertTrue(chicken.label.contains("not used"))
        chicken.tap()
        XCTAssertTrue(chicken.label.contains("used"))

        for _ in 0..<2 {
            let start = app.buttons["timerStart"].firstMatch
            reveal(start, in: app, scrollView: app.scrollViews["cookingScroll"], maximumSwipes: 5)
            start.tap()
        }

        let timers = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Timers")
        ).firstMatch
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
        reveal(
            restartAtStepTwo,
            in: app,
            scrollView: app.scrollViews["recipeDetailScroll"],
            maximumSwipes: 8
        )
        restartAtStepTwo.tap()
        assertCookingStep("Step 2 of 8", in: app)
        XCTAssertTrue(app.staticTexts["1 done"].exists == false)
    }

    @MainActor
    func testRecipeCanBeAddedDirectlyToMealPlan() {
        let app = launchSeededApp()
        defer { app.terminate() }
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
        defer { app.terminate() }

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
        weeknightMembership.tap()
        XCTAssertTrue((weeknightMembership.value as? String) != "Not in collection")
        app.navigationBars.buttons["Done"].tap()

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
    func testProfileLayoutAndPrimaryActionsAreVisible() {
        let app = launchSeededApp()
        defer { app.terminate() }

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
    func testAccountScreenKeepsEmailCodePasswordAppleAndGoogleInOneFlow() {
        let app = launchSeededApp()
        defer {
            app.terminate()
        }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let account = app.buttons["RecipePouch Account"]
        waitUntilReady(account)
        account.tap()

        XCTAssertTrue(app.buttons["account.next"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["account.email"].exists)
        XCTAssertTrue(app.buttons["account.google"].exists)
        XCTAssertTrue(app.buttons["account.apple"].exists)
        attachScreenshot("Account sign in options", app: app)

        let emailField = app.textFields["account.email"]
        emailField.tap()
        emailField.typeText("tester@example.com")
        app.buttons["account.next"].tap()
        XCTAssertTrue(app.buttons["account.sendCode"].waitForExistence(timeout: 5))
        app.buttons["Use Password Instead"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        XCTAssertTrue(app.buttons["Forgot Password?"].exists)
    }

    @MainActor
    func testCookingIngredientCheckoffPersistsInSession() {
        let app = launchSeededApp()
        defer { app.terminate() }
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
    func testExportFormatsAreAvailableInBothEntryPoints() {
        let app = launchSeededApp()
        defer { app.terminate() }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let profileExport = app.buttons["profile.export"]
        reveal(profileExport, in: app, maximumSwipes: 5)
        profileExport.tap()
        for format in ["Recipes (JSON)", "Recipes (HTML)", "All Local Library Data (JSON)"] {
            XCTAssertTrue(app.buttons[format].waitForExistence(timeout: 5))
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
        defer { settingsApp.terminate() }

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
    func testSubscriptionOpensFromProfileAndSettings() {
        let app = launchSeededApp()
        defer { app.terminate() }

        let profile = app.tabBars.buttons["Profile"]
        waitUntilReady(profile)
        profile.tap()

        let premium = app.buttons["RecipePouch Premium"]
        reveal(premium, in: app, maximumSwipes: 4)
        premium.tap()
        XCTAssertTrue(app.staticTexts["RecipePouch Premium"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        attachScreenshot("Subscription from Profile", app: app)

        app.navigationBars.buttons.firstMatch.tap()
        let settings = app.buttons["Settings"]
        reveal(settings, in: app, maximumSwipes: 4)
        settings.tap()

        let subscription = app.buttons["Subscription"]
        reveal(subscription, in: app, maximumSwipes: 4)
        subscription.tap()

        XCTAssertTrue(app.staticTexts["RecipePouch Premium"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        attachScreenshot("Subscription from Settings", app: app)
    }

    @MainActor
    func testLocalStoreKitPurchaseAndRestoreWithoutAppStoreAccount() async throws {
        let session = try makeStoreKitTestSession()
        defer { reset(session) }

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer { app.terminate() }
        openSubscription(in: app)

        let restore = app.buttons["subscription.restore"]
        waitUntilReady(restore)
        restore.tap()

        let restoreMessage = app.alerts["Subscription"]
        XCTAssertTrue(restoreMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(
            restoreMessage.staticTexts[
                "No active RecipePouch subscription was found for this App Store account."
            ].exists
        )
        restoreMessage.buttons["OK"].tap()

        let localProduct = app.buttons["subscription.plan.\(Self.localStoreKitProductID)"]
        waitUntilReady(localProduct)
        localProduct.tap()

        XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    @MainActor
    func testLocalStoreKitLoadFailureKeepsRetryAndRestoreAvailable() async throws {
        let session = try makeStoreKitTestSession()
        defer { reset(session) }
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer { app.terminate() }
        openSubscription(in: app)

        XCTAssertTrue(
            app.staticTexts["Premium plans aren’t available right now."].waitForExistence(timeout: 8)
        )
        let restore = app.buttons["subscription.restore"]
        waitUntilReady(restore)
        restore.tap()

        let restoreMessage = app.alerts["Subscription"]
        XCTAssertTrue(restoreMessage.waitForExistence(timeout: 8))
        XCTAssertFalse(
            restoreMessage.staticTexts[
                "No active RecipePouch subscription was found for this App Store account."
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
        defer { reset(session) }
        _ = try await session.buyProduct(identifier: Self.localStoreKitProductID)
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )

        let app = launchSeededApp(storeKitTestProductID: Self.localStoreKitProductID)
        defer { app.terminate() }
        openSubscription(in: app)

        XCTAssertTrue(app.staticTexts["Subscription active"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["subscription.retry"].exists)
    }

    @MainActor
    func testRestoreExplainsWhenSubscriptionProductsAreUnconfigured() {
        let app = launchSeededApp(storeKitTestProductID: "")
        defer { app.terminate() }
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
                "No active RecipePouch subscription was found for this App Store account."
            ].exists
        )
    }

    @MainActor
    func testFourLocaleTabLabelsUseStringCatalog() {
        // Each launch uses --uitesting fixtures, but only explicit locale
        // smoke cases override the usual deterministic English UI policy.
        let examples: [(String, String, String, String, String, String, String)] = [
            ("en", "en_US", "Recipes", "Recipe", "Profile", "Settings", "RecipePouch Account"),
            ("zh-Hans", "zh_CN", "食谱", "份食谱", "我的", "设置", "RecipePouch 账号"),
            ("zh-Hant", "zh_TW", "食譜", "份食譜", "個人", "設定", "RecipePouch 帳號"),
            ("ja", "ja_JP", "レシピ", "件のレシピ", "マイページ", "設定", "RecipePouch アカウント"),
        ]

        for (language, region, recipesLabel, countNoun, profileLabel, settingsTitle, accountLabel)
            in examples
        {
            let app = XCUIApplication()
            app.launchArguments = [
                "--uitesting",
                "--uitesting-locale", language,
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", region,
            ]
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
        let locales: [(String, String, String, String, String, String, String)] = [
            (
                "en", "en_US", "Profile", "Settings", "RecipePouch Account", "Subscription",
                "Cloud Sync"
            ),
            (
                "ja", "ja_JP", "マイページ", "設定", "RecipePouch アカウント", "サブスクリプション",
                "クラウド同期"
            ),
        ]

        for (
            language, region, profileLabel, settingsTitle, accountLabel, subscriptionLabel,
            cloudSyncLabel
        ) in locales {
            let app = XCUIApplication()
            app.launchArguments = [
                "--uitesting",
                "--uitesting-locale", language,
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", region,
            ]
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
    private func launchSeededApp(storeKitTestProductID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

        let premium = app.buttons["RecipePouch Premium"]
        reveal(premium, in: app, maximumSwipes: 4)
        premium.tap()
        XCTAssertTrue(app.staticTexts["RecipePouch Premium"].waitForExistence(timeout: 8))
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
    private func waitUntilReady(
        _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
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
            if element.exists && element.isHittable { break }
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
            if element.exists && element.frame.height > 0 && element.frame.maxY <= form.frame.minY + 12 {
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
            if element.exists && element.isHittable { break }
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
    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
