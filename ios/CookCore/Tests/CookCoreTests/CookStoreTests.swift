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
    #expect(ids.count == 4)
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
