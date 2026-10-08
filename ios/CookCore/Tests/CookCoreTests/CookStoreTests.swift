import Foundation
import Testing
@testable import CookCore

private func libraryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CookCoreTests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("library.json")
}

private func exampleRecipe(ingredients: [RecipeIngredient]? = nil) -> Recipe {
    Recipe(
        title: "Test pasta", servings: 2,
        ingredients: ingredients ?? [.from(name: "Pasta", amountText: "100 g", category: .pantry)],
        steps: [RecipeStep(instruction: "Cook the pasta.")],
        sourceURL: "https://example.com/recipe?original=1",
        sourceText: "Original amount: 100 g\nOriginal instructions.",
        sourceName: "Original source"
    )
}

@Test @MainActor
func libraryStartsEmptyAndSamplesAreExplicitAndIdempotent() throws {
    let store = CookStore()
    #expect(store.recipes.isEmpty)
    try store.loadSampleRecipes()
    let ids = store.recipes.map(\.id)
    #expect(ids.count == 5)
    #expect(store.recipes.allSatisfy { $0.sourceName == "Sample recipe" && !$0.needsReview })
    try store.toggleFavorite(id: ids[0])
    try store.loadSampleRecipes()
    #expect(store.recipes.map(\.id) == ids)
    #expect(store.recipe(id: ids[0])?.isFavorite == true)
}

@Test @MainActor
func savedLibraryRoundTripsEveryUserFacingState() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = CookStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    try store.toggleFavorite(id: recipe.id)
    try store.addToGroceries(recipeID: recipe.id, servings: 4,
                             ingredientIDs: Set(recipe.ingredients.map(\.id)))
    let grocery = try #require(store.groceries.first)
    try store.toggleGrocery(id: grocery.id)
    try store.upsertMeal(MealPlanEntry(recipeID: recipe.id, date: .now))
    let settings = CookSettings(displayName: "Sam", email: "sam@example.com",
                                appearance: .dark, keepScreenAwake: false, timerNotifications: true)
    try store.updateSettings(settings)

    let restored = CookStore(fileURL: url)
    #expect(restored.loadError == nil)
    #expect(restored.recipes == store.recipes)
    #expect(restored.groceries == store.groceries)
    #expect(restored.mealPlan == store.mealPlan)
    #expect(restored.settings == settings)
    #expect(restored.groceries.first?.quantity == 200)
    #expect(restored.groceries.first?.isChecked == true)
    #expect(restored.recipe(id: recipe.id)?.sourceText == recipe.sourceText)
    #expect(restored.recipe(id: recipe.id)?.sourceURL == recipe.sourceURL)
    #expect(try restored.exportData() == Data(contentsOf: url))
}

@Test @MainActor
func unreadableLibraryIsPreservedAndMutationsStayBlockedUntilReloadSucceeds() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = CookStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    let original = try Data(contentsOf: url)
    let corrupt = Data("{ unfinished library".utf8)
    try corrupt.write(to: url)
    store.reload()
    #expect(store.loadError != nil)
    #expect(store.recipe(id: recipe.id)?.title == recipe.title)
    #expect(throws: CookStoreError.self) { try store.toggleFavorite(id: recipe.id) }
    #expect(throws: CookStoreError.self) { try store.resetLibrary() }
    #expect(try Data(contentsOf: url) == corrupt)
    let restarted = CookStore(fileURL: url)
    #expect(restarted.loadError != nil)
    #expect(throws: CookStoreError.self) { try restarted.loadSampleRecipes() }
    #expect(try Data(contentsOf: url) == corrupt)
    try original.write(to: url)
    store.reload()
    #expect(store.loadError == nil)
    try store.toggleFavorite(id: recipe.id)
    #expect(store.recipe(id: recipe.id)?.isFavorite == true)
}

@Test @MainActor
func aWriteFailureDoesNotPublishAnUnsavedMutation() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let blockedParent = url.deletingLastPathComponent().appendingPathComponent("blocked")
    let store = CookStore(fileURL: blockedParent.appendingPathComponent("library.json"))
    #expect(store.loadError == nil)
    let sentinel = Data("A file occupies the intended parent directory.".utf8)
    try sentinel.write(to: blockedParent)
    #expect(throws: (any Error).self) { try store.upsert(exampleRecipe()) }
    #expect(store.recipes.isEmpty)
    #expect(try Data(contentsOf: blockedParent) == sentinel)
}

@Test @MainActor
func groceryMergeRequiresKnownQuantitiesAndExactlyMatchingUnits() throws {
    let grams = RecipeIngredient.from(name: " Flour ", amountText: "100 g", category: .pantry)
    let moreGrams = RecipeIngredient.from(name: "flour", amountText: "50 g", category: .pantry)
    let cups = RecipeIngredient.from(name: "Flour", amountText: "1 cup", category: .pantry)
    let unknown = RecipeIngredient.from(name: "Flour", amountText: "as needed", category: .pantry)
    let recipe = exampleRecipe(ingredients: [grams, moreGrams, cups, unknown])
    let store = CookStore()
    try store.upsert(recipe)
    try store.addToGroceries(recipeID: recipe.id, servings: 4,
                             ingredientIDs: Set(recipe.ingredients.map(\.id)))
    #expect(store.groceries.count == 3)
    #expect(store.groceries.first { $0.unit == "g" }?.quantity == 300)
    #expect(store.groceries.first { $0.unit == "cup" }?.quantity == 2)
    #expect(store.groceries.first { $0.quantity == nil }?.amountText == "as needed")
    let checked = try #require(store.groceries.first { $0.unit == "g" })
    try store.toggleGrocery(id: checked.id)
    try store.addToGroceries(recipeID: recipe.id, servings: 2, ingredientIDs: [grams.id])
    #expect(store.groceries.count == 4)
    #expect(store.groceries.first { $0.id == checked.id }?.isChecked == true)
    try store.clearCheckedGroceries()
    #expect(store.groceries.count == 3)
}

@Test(arguments: [1, 2]) @MainActor
func shoppingSelectionAndInexactScalePreserveEvidence(amount: Int) throws {
    let sourceText = "\(amount) cup"
    let flour = RecipeIngredient.from(name: "Flour", amountText: sourceText, category: .pantry)
    let salt = RecipeIngredient.from(name: "Salt", amountText: "to taste", category: .pantry)
    var recipe = exampleRecipe(ingredients: [flour, salt])
    recipe.servings = 3
    let store = CookStore()
    try store.upsert(recipe)
    try store.addToGroceries(recipeID: recipe.id, servings: 1, ingredientIDs: [flour.id])
    #expect(store.groceries.count == 1)
    #expect(store.groceries[0].quantity == nil)
    #expect(store.groceries[0].amountText == "\(sourceText) × 1/3")
    #expect(store.recipe(id: recipe.id)?.ingredients[0].amountText == sourceText)
    #expect(throws: CookStoreError.missingItem) {
        try store.addToGroceries(recipeID: recipe.id, servings: 1, ingredientIDs: [UUID()])
    }
    #expect(store.groceries.count == 1)
}

@Test @MainActor
func differentlyWrittenUnitsAreNotSilentlyConverted() throws {
    let ingredients = ["1 t", "1 T", "1 cup", "1 cups"].map {
        RecipeIngredient.from(name: "Spice", amountText: $0)
    }
    let recipe = exampleRecipe(ingredients: ingredients)
    let store = CookStore()
    try store.upsert(recipe)
    try store.addToGroceries(recipeID: recipe.id, servings: nil,
                             ingredientIDs: Set(ingredients.map(\.id)))
    #expect(store.groceries.count == 4)
    #expect(store.groceries.allSatisfy { $0.quantity == 1 })
}

@Test @MainActor
func planReplacesSameDaySlotAndDeletingRecipeCleansReferences() throws {
    let store = CookStore()
    let first = exampleRecipe()
    let second = exampleRecipe()
    try store.upsert(first)
    try store.upsert(second)
    let day = Calendar.current.startOfDay(for: .now)
    try store.upsertMeal(MealPlanEntry(recipeID: first.id, date: day, slot: .dinner))
    try store.upsertMeal(MealPlanEntry(recipeID: second.id,
                                     date: day.addingTimeInterval(3600), slot: .dinner))
    #expect(store.mealPlan.count == 1)
    #expect(store.mealPlan[0].recipeID == second.id)
    try store.addToGroceries(recipeID: second.id, servings: nil,
                             ingredientIDs: Set(second.ingredients.map(\.id)))
    try store.deleteRecipe(id: second.id)
    #expect(store.mealPlan.isEmpty)
    #expect(store.groceries.count == 1)
    #expect(store.groceries[0].recipeIDs.isEmpty)
    try store.updateSettings(CookSettings(displayName: "Local profile", appearance: .dark))
    try store.resetLibrary()
    #expect(store.recipes.isEmpty && store.groceries.isEmpty && store.mealPlan.isEmpty)
    #expect(store.settings == CookSettings())
}

@Test @MainActor
func invalidRecipeDoesNotChangeOrPersistLibrary() throws {
    let store = CookStore()
    var recipe = exampleRecipe()
    recipe.servings = 0
    #expect(throws: CookStoreError.self) { try store.upsert(recipe) }
    #expect(store.recipes.isEmpty)
    recipe.servings = 2
    recipe.ingredients[0].quantity = .nan
    #expect(throws: IngredientAmount.ValidationError.invalidValue) { try store.upsert(recipe) }
    #expect(store.recipes.isEmpty)
}


@Test @MainActor
func collectionsRoundTripAndRemainIndependentFromFavorites() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = CookStore(fileURL: url)
    let first = exampleRecipe()
    let second = Recipe(
        title: "Second recipe",
        ingredients: [.from(name: "Rice", amountText: "100 g")],
        steps: [RecipeStep(instruction: "Cook rice.")]
    )

    try store.upsert(first)
    try store.upsert(second)
    try store.toggleFavorite(id: first.id)

    let quick = try store.createCollection(name: "Quick Meals")
    let weekend = try store.createCollection(name: "Weekend")
    try store.setRecipe(first.id, inCollection: quick.id, isMember: true)
    try store.setRecipe(first.id, inCollection: weekend.id, isMember: true)
    try store.setRecipe(second.id, inCollection: weekend.id, isMember: true)

    #expect(store.collectionIDs(forRecipe: first.id) == [quick.id, weekend.id])
    #expect(store.recipes(inCollection: quick.id).map(\.id) == [first.id])
    #expect(Set(store.recipes(inCollection: weekend.id).map(\.id)) == [first.id, second.id])
    #expect(store.recipe(id: first.id)?.isFavorite == true)

    try store.renameCollection(id: quick.id, name: "Fast")
    #expect(store.collection(id: quick.id)?.name == "Fast")

    let restored = CookStore(fileURL: url)
    #expect(restored.loadError == nil)
    #expect(restored.collectionIDs(forRecipe: first.id) == [quick.id, weekend.id])
    #expect(restored.recipe(id: first.id)?.isFavorite == true)

    try restored.deleteCollection(id: quick.id)
    #expect(restored.recipe(id: first.id) != nil)
    #expect(restored.recipe(id: first.id)?.isFavorite == true)
    #expect(restored.collection(id: quick.id) == nil)
    #expect(restored.collectionIDs(forRecipe: first.id) == [weekend.id])

    try restored.deleteRecipe(id: first.id)
    #expect(restored.collectionIDs(forRecipe: first.id).isEmpty)
    #expect(restored.recipes(inCollection: weekend.id).map(\.id) == [second.id])
}

@Test @MainActor
func collectionNamesRejectDuplicatesAndLegacyNamesMigrateSafely() throws {
    let store = CookStore()
    _ = try store.createCollection(name: "Weeknight")
    #expect(throws: CookStoreError.self) {
        try store.createCollection(name: "  weeknight  ")
    }
    #expect(throws: CookStoreError.self) {
        try store.createCollection(name: "Favorites")
    }

    let added = try store.importLegacyCollectionNames([
        "Favorites",
        "Weeknight",
        "Family",
        " family ",
        ""
    ])
    #expect(added == 1)
    #expect(store.collections.map(\.name).sorted() == ["Family", "Weeknight"])
}

@Test @MainActor
func versionOneLibraryLoadsAndUpgradesWithoutInventingMemberships() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = CookStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)

    let currentData = try store.exportData()
    var object = try #require(
        JSONSerialization.jsonObject(with: currentData) as? [String: Any]
    )
    object["version"] = 1
    object.removeValue(forKey: "collections")
    object.removeValue(forKey: "collectionMemberships")
    let versionOneData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    try versionOneData.write(to: url, options: .atomic)

    let restored = CookStore(fileURL: url)
    #expect(restored.loadError == nil)
    #expect(restored.recipes.map(\.id) == [recipe.id])
    #expect(restored.collections.isEmpty)
    #expect(restored.collectionMemberships.isEmpty)

    let collection = try restored.createCollection(name: "Migrated")
    try restored.setRecipe(recipe.id, inCollection: collection.id, isMember: true)

    let exported = try restored.exportData()
    let upgraded = try #require(
        JSONSerialization.jsonObject(with: exported) as? [String: Any]
    )
    #expect(upgraded["version"] as? Int == 2)
    #expect((upgraded["collections"] as? [[String: Any]])?.count == 1)
    #expect((upgraded["collectionMemberships"] as? [[String: Any]])?.count == 1)
}

@Test @MainActor
func collectionExportContainsStableIDsAndRelationships() throws {
    let store = CookStore()
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    let collection = try store.createCollection(name: "Dinner")
    try store.setRecipe(recipe.id, inCollection: collection.id, isMember: true)

    let data = try store.exportData()
    let object = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let collections = try #require(object["collections"] as? [[String: Any]])
    let memberships = try #require(
        object["collectionMemberships"] as? [[String: Any]]
    )

    #expect(collections.first?["id"] as? String == collection.id.uuidString)
    #expect(collections.first?["name"] as? String == "Dinner")
    #expect(memberships.first?["recipeID"] as? String == recipe.id.uuidString)
    #expect(memberships.first?["collectionID"] as? String == collection.id.uuidString)
}


@Test @MainActor
func groceryConsolidationPreferenceChangesOnlyFutureAdds() throws {
    let flourA = RecipeIngredient.from(
        name: "Flour",
        amountText: "100 g",
        category: .pantry
    )
    let flourB = RecipeIngredient.from(
        name: " flour ",
        amountText: "50 g",
        category: .pantry
    )
    let recipe = exampleRecipe(ingredients: [flourA, flourB])
    let store = CookStore()
    try store.upsert(recipe)

    var settings = store.settings
    settings.consolidateCompatibleGroceries = false
    try store.updateSettings(settings)
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [flourA.id, flourB.id]
    )

    #expect(store.groceries.count == 2)
    #expect(Set(store.groceries.compactMap(\.quantity)) == [100, 50])

    settings = store.settings
    settings.consolidateCompatibleGroceries = true
    try store.updateSettings(settings)
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [flourA.id]
    )

    // Changing the setting never rewrites existing rows; only this new add may
    // merge into one compatible unchecked item.
    #expect(store.groceries.count == 2)
    #expect(Set(store.groceries.compactMap(\.quantity)) == [200, 50])
}

@Test
func legacyCookSettingsDecodeWithNewPreferenceDefaults() throws {
    let json = #"{
      "displayName":"Sam",
      "email":"sam@example.com",
      "appearance":"Dark",
      "keepScreenAwake":false,
      "timerNotifications":true
    }"#
    let settings = try JSONDecoder().decode(
        CookSettings.self,
        from: Data(json.utf8)
    )

    #expect(settings.displayName == "Sam")
    #expect(settings.appearance == .dark)
    #expect(settings.keepScreenAwake == false)
    #expect(settings.timerNotifications == true)
    #expect(settings.consolidateCompatibleGroceries == true)
    #expect(settings.showGroceryRecipeNames == true)
    #expect(settings.mealPlanWeekStart == .system)
}

@Test
func mealPlanWeekStartAppliesWithoutChangingOtherCalendarRules() {
    var base = Calendar(identifier: .gregorian)
    base.firstWeekday = 5
    base.minimumDaysInFirstWeek = 4

    let system = MealPlanWeekStart.system.applying(to: base)
    let sunday = MealPlanWeekStart.sunday.applying(to: base)
    let monday = MealPlanWeekStart.monday.applying(to: base)

    #expect(system.firstWeekday == 5)
    #expect(sunday.firstWeekday == 1)
    #expect(monday.firstWeekday == 2)
    #expect(system.minimumDaysInFirstWeek == 4)
    #expect(sunday.minimumDaysInFirstWeek == 4)
    #expect(monday.minimumDaysInFirstWeek == 4)
}
