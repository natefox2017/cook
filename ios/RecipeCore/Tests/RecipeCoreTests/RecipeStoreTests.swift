// Developer: gengyun
// Purpose: Verify local library persistence and cloud snapshot safety contracts.

import Foundation
import Testing
@testable import RecipeCore

private func libraryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecipeCoreTests-" + UUID().uuidString, isDirectory: true)
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
    let store = RecipeStore()
    #expect(store.recipes.isEmpty)
    try store.loadSampleRecipes()
    let ids = store.recipes.map(\.id)
    #expect(ids.count == SampleRecipes.recipes.count)
    #expect(store.recipes.allSatisfy { $0.sourceName == "Sample recipe" && !$0.needsReview })
    try store.toggleFavorite(id: ids[0])
    try store.loadSampleRecipes()
    #expect(store.recipes.map(\.id) == ids)
    #expect(store.recipe(id: ids[0])?.isFavorite == true)
}

@Test @MainActor
func deletionsAndResetRemainInCloudSnapshotAfterReload() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = RecipeStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    try store.deleteRecipe(id: recipe.id)

    let restored = RecipeStore(fileURL: url)
    #expect(try restored.exportCloudSnapshot().deletedEntities?.contains("recipe:\(recipe.id.uuidString)") == true)

    let remaining = Recipe(title: "Keep", steps: [.init(instruction: "Cook.")])
    try restored.upsert(remaining)
    try restored.resetLibrary()

    let reset = RecipeStore(fileURL: url)
    let deletedEntities = try reset.exportCloudSnapshot().deletedEntities ?? []
    #expect(deletedEntities.contains("recipe:\(recipe.id.uuidString)"))
    #expect(deletedEntities.contains("recipe:\(remaining.id.uuidString)"))
}

@Test @MainActor
func savedLibraryRoundTripsEveryUserFacingState() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = RecipeStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    try store.toggleFavorite(id: recipe.id)
    try store.addToGroceries(recipeID: recipe.id, servings: 4,
                             ingredientIDs: Set(recipe.ingredients.map(\.id)))
    let grocery = try #require(store.groceries.first)
    try store.toggleGrocery(id: grocery.id)
    try store.upsertMeal(MealPlanEntry(recipeID: recipe.id, date: .now))
    let settings = RecipeSettings(displayName: "Sam", email: "sam@example.com",
                                appearance: .dark, keepScreenAwake: false, timerNotifications: true)
    try store.updateSettings(settings)

    let restored = RecipeStore(fileURL: url)
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
    let store = RecipeStore(fileURL: url)
    let recipe = exampleRecipe()
    try store.upsert(recipe)
    let original = try Data(contentsOf: url)
    let corrupt = Data("{ unfinished library".utf8)
    try corrupt.write(to: url)
    store.reload()
    #expect(store.loadError != nil)
    #expect(store.recipe(id: recipe.id)?.title == recipe.title)
    #expect(throws: RecipeStoreError.self) { try store.toggleFavorite(id: recipe.id) }
    #expect(throws: RecipeStoreError.self) { try store.resetLibrary() }
    #expect(try Data(contentsOf: url) == corrupt)
    let restarted = RecipeStore(fileURL: url)
    #expect(restarted.loadError != nil)
    #expect(throws: RecipeStoreError.self) { try restarted.loadSampleRecipes() }
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
    let store = RecipeStore(fileURL: blockedParent.appendingPathComponent("library.json"))
    #expect(store.loadError == nil)
    let sentinel = Data("A file occupies the intended parent directory.".utf8)
    try sentinel.write(to: blockedParent)
    #expect(throws: (any Error).self) { try store.upsert(exampleRecipe()) }
    #expect(store.recipes.isEmpty)
    #expect(try Data(contentsOf: blockedParent) == sentinel)
}

@Test @MainActor
func replacingLibraryWithCloudSnapshotIsValidatedAndAtomic() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let local = RecipeStore(fileURL: url)
    let localRecipe = exampleRecipe()
    try local.upsert(localRecipe)
    let originalBytes = try Data(contentsOf: url)

    let remote = RecipeStore()
    let remoteRecipe = Recipe(title: "Remote soup", steps: [.init(instruction: "Simmer.")])
    try remote.upsert(remoteRecipe)
    let remoteBytes = try remote.exportData()
    try local.replaceLibrary(with: remoteBytes)

    #expect(local.recipes.map(\.id) == [remoteRecipe.id])
    #expect(local.recipe(id: localRecipe.id) == nil)
    #expect(try Data(contentsOf: url) == remoteBytes)

    #expect(throws: (any Error).self) {
        try local.replaceLibrary(with: Data("{ invalid".utf8))
    }
    #expect(local.recipes.map(\.id) == [remoteRecipe.id])
    #expect(try Data(contentsOf: url) == remoteBytes)
    #expect(originalBytes != remoteBytes)
}

@Test @MainActor
func mergingIndependentLibrariesKeepsBothRecipes() throws {
    let local = RecipeStore()
    let localRecipe = exampleRecipe()
    try local.upsert(localRecipe)

    let cloud = RecipeStore()
    let cloudRecipe = Recipe(title: "Cloud soup", steps: [.init(instruction: "Simmer.")])
    try cloud.upsert(cloudRecipe)

    #expect(try local.mergeCloudLibrary(with: cloud.exportData()).isEmpty)
    #expect(Set(local.recipes.map(\.id)) == Set([localRecipe.id, cloudRecipe.id]))
}

@Test @MainActor
func mergeRequiresAnExplicitChoiceForSameRecipeAndForDeletionPropagation() throws {
    let local = RecipeStore()
    let shared = exampleRecipe()
    try local.upsert(shared)
    let cloud = RecipeStore()
    try cloud.upsert(Recipe(id: shared.id, title: "Cloud edit", steps: [.init(instruction: "Bake.")]))

    let editConflicts = try local.mergeCloudLibrary(with: cloud.exportData())
    #expect(editConflicts.map(\.entity) == [.recipe])
    #expect(local.recipe(id: shared.id)?.title == shared.title)
    let useCloud = LibraryMergeChoice(conflict: editConflicts[0], source: .cloud)
    #expect(try local.mergeCloudLibrary(with: cloud.exportData(), choices: [useCloud]).isEmpty)
    #expect(local.recipe(id: shared.id)?.title == "Cloud edit")

    let cloudCopy = try local.exportData()
    try local.deleteRecipe(id: shared.id)
    let deleteConflict = try local.mergeCloudLibrary(with: cloudCopy)
    #expect(deleteConflict.map(\.entity) == [.recipe])
    let keepDeletion = LibraryMergeChoice(conflict: deleteConflict[0], source: .local)
    #expect(try local.mergeCloudLibrary(with: cloudCopy, choices: [keepDeletion]).isEmpty)
    #expect(local.recipe(id: shared.id) == nil)

    let restoreCloud = LibraryMergeChoice(conflict: deleteConflict[0], source: .cloud)
    #expect(try local.mergeCloudLibrary(with: cloudCopy, choices: [restoreCloud]).isEmpty)
    #expect(local.recipe(id: shared.id)?.title == "Cloud edit")
}

@Test @MainActor
func typedCloudSnapshotKeepsExactDecimalAmounts() throws {
    let exact = try #require(Decimal(string: "0.1234567890123456789012345678", locale: Locale(identifier: "en_US_POSIX")))
    let store = RecipeStore()
    let recipe = Recipe(
        title: "Precise sauce",
        ingredients: [.init(name: "Oil", amountText: NSDecimalNumber(decimal: exact).stringValue, quantity: exact)],
        steps: [.init(instruction: "Mix.")]
    )
    try store.upsert(recipe)

    let encoded = try JSONEncoder().encode(store.exportCloudSnapshot())
    let decoded = try JSONDecoder().decode(RecipeLibrarySnapshot.self, from: encoded)
    #expect(decoded.recipes.first?.ingredients.first?.quantity == exact)
}

@Test @MainActor
func cloudMergePreservesCollectionsAndMembershipsAcrossDevices() throws {
    let local = RecipeStore()
    let firstRecipe = exampleRecipe()
    try local.upsert(firstRecipe)
    let collection = try local.createCollection(name: "Weeknight")
    try local.setRecipe(firstRecipe.id, inCollection: collection.id, isMember: true)

    let cloud = RecipeStore()
    try cloud.replaceLibrary(with: local.exportCloudSnapshot())
    let secondRecipe = Recipe(title: "Cloud soup", steps: [.init(instruction: "Simmer.")])
    try cloud.upsert(secondRecipe)
    try cloud.setRecipe(secondRecipe.id, inCollection: collection.id, isMember: true)

    #expect(try local.mergeCloudLibrary(with: cloud.exportCloudSnapshot()).isEmpty)
    #expect(local.collection(id: collection.id)?.name == "Weeknight")
    #expect(local.collectionIDs(forRecipe: firstRecipe.id) == [collection.id])
    #expect(local.collectionIDs(forRecipe: secondRecipe.id) == [collection.id])
}

@Test @MainActor
func groceryMergeRequiresKnownQuantitiesAndExactlyMatchingUnits() throws {
    let grams = RecipeIngredient.from(name: " Flour ", amountText: "100 g", category: .pantry)
    let moreGrams = RecipeIngredient.from(name: "flour", amountText: "50 g", category: .pantry)
    let cups = RecipeIngredient.from(name: "Flour", amountText: "1 cup", category: .pantry)
    let unknown = RecipeIngredient.from(name: "Flour", amountText: "as needed", category: .pantry)
    let recipe = exampleRecipe(ingredients: [grams, moreGrams, cups, unknown])
    let store = RecipeStore()
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
    let store = RecipeStore()
    try store.upsert(recipe)
    try store.addToGroceries(recipeID: recipe.id, servings: 1, ingredientIDs: [flour.id])
    #expect(store.groceries.count == 1)
    #expect(store.groceries[0].quantity == nil)
    #expect(store.groceries[0].amountText == "\(sourceText) × 1/3")
    #expect(store.recipe(id: recipe.id)?.ingredients[0].amountText == sourceText)
    #expect(throws: RecipeStoreError.missingItem) {
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
    let store = RecipeStore()
    try store.upsert(recipe)
    try store.addToGroceries(recipeID: recipe.id, servings: nil,
                             ingredientIDs: Set(ingredients.map(\.id)))
    #expect(store.groceries.count == 4)
    #expect(store.groceries.allSatisfy { $0.quantity == 1 })
}

@Test @MainActor
func planReplacesSameDaySlotAndDeletingRecipeCleansReferences() throws {
    let store = RecipeStore()
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
    try store.updateSettings(RecipeSettings(displayName: "Local profile", appearance: .dark))
    try store.resetLibrary()
    #expect(store.recipes.isEmpty && store.groceries.isEmpty && store.mealPlan.isEmpty)
    #expect(store.settings == RecipeSettings())
}

@Test @MainActor
func invalidRecipeDoesNotChangeOrPersistLibrary() throws {
    let store = RecipeStore()
    var recipe = exampleRecipe()
    recipe.servings = 0
    #expect(throws: RecipeStoreError.self) { try store.upsert(recipe) }
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

    let store = RecipeStore(fileURL: url)
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

    let restored = RecipeStore(fileURL: url)
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
    let store = RecipeStore()
    _ = try store.createCollection(name: "Weeknight")
    #expect(throws: RecipeStoreError.self) {
        try store.createCollection(name: "  weeknight  ")
    }
    #expect(throws: RecipeStoreError.self) {
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

    let store = RecipeStore(fileURL: url)
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

    let restored = RecipeStore(fileURL: url)
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
    let store = RecipeStore()
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
func sampleRecipesCanBeLoadedAfterReset() throws {
    let store = RecipeStore()
    try store.loadSampleRecipes()
    try store.resetLibrary()
    #expect(store.recipes.isEmpty)

    try store.loadSampleRecipes()

    #expect(store.recipes.count == SampleRecipes.recipes.count)
    let tombstones = try store.exportCloudSnapshot().deletedEntities ?? []
    #expect(
        SampleRecipes.recipes.allSatisfy {
            !tombstones.contains("recipe:\($0.id.uuidString)")
        }
    )
}

@Test @MainActor
func threeWayMergeAcceptsIndependentLocalAndRemoteChanges() throws {
    let baseStore = RecipeStore()
    let shared = exampleRecipe()
    try baseStore.upsert(shared)
    let base = try baseStore.exportCloudSnapshot()

    let local = RecipeStore()
    try local.replaceLibrary(with: base)
    let localGrocery = GroceryItem(
        name: "Milk",
        amountText: "1 carton",
        category: .dairy
    )
    try local.upsertGrocery(localGrocery)

    let cloud = RecipeStore()
    try cloud.replaceLibrary(with: base)
    var remoteRecipe = try #require(cloud.recipe(id: shared.id))
    remoteRecipe.title = "Remote edit"
    try cloud.upsert(remoteRecipe)

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot(),
        base: base
    )

    #expect(conflicts.isEmpty)
    #expect(local.recipe(id: shared.id)?.title == "Remote edit")
    #expect(local.groceries.contains(where: { $0.id == localGrocery.id }))
}

@Test @MainActor
func threeWayMergeStillConflictsWhenBothSidesEditSameRecipe() throws {
    let baseStore = RecipeStore()
    let shared = exampleRecipe()
    try baseStore.upsert(shared)
    let base = try baseStore.exportCloudSnapshot()

    let local = RecipeStore()
    try local.replaceLibrary(with: base)
    var localRecipe = try #require(local.recipe(id: shared.id))
    localRecipe.title = "Local edit"
    try local.upsert(localRecipe)

    let cloud = RecipeStore()
    try cloud.replaceLibrary(with: base)
    var remoteRecipe = try #require(cloud.recipe(id: shared.id))
    remoteRecipe.title = "Remote edit"
    try cloud.upsert(remoteRecipe)

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot(),
        base: base
    )

    #expect(conflicts.count == 1)
    #expect(conflicts.first?.entity == .recipe)
    #expect(conflicts.first?.entityID == shared.id)
}

@Test @MainActor
func independentMembershipRemovalsMergeWithoutConflict() throws {
    let baseStore = RecipeStore()
    let first = exampleRecipe()
    let second = Recipe(
        title: "Second",
        steps: [.init(instruction: "Cook.")]
    )
    try baseStore.upsert(first)
    try baseStore.upsert(second)
    let collection = try baseStore.createCollection(name: "Dinner")
    try baseStore.setRecipe(first.id, inCollection: collection.id, isMember: true)
    try baseStore.setRecipe(second.id, inCollection: collection.id, isMember: true)
    let base = try baseStore.exportCloudSnapshot()

    let local = RecipeStore()
    try local.replaceLibrary(with: base)
    try local.setRecipe(first.id, inCollection: collection.id, isMember: false)

    let cloud = RecipeStore()
    try cloud.replaceLibrary(with: base)
    try cloud.setRecipe(second.id, inCollection: collection.id, isMember: false)

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot(),
        base: base
    )

    #expect(conflicts.isEmpty)
    #expect(local.collectionIDs(forRecipe: first.id).isEmpty)
    #expect(local.collectionIDs(forRecipe: second.id).isEmpty)
}

@Test @MainActor
func initialMembershipConflictsHaveUniqueIDs() throws {
    let local = RecipeStore()
    let first = exampleRecipe()
    let second = Recipe(
        title: "Second",
        steps: [.init(instruction: "Cook.")]
    )
    try local.upsert(first)
    try local.upsert(second)
    let collection = try local.createCollection(name: "Dinner")
    try local.setRecipe(first.id, inCollection: collection.id, isMember: true)
    try local.setRecipe(second.id, inCollection: collection.id, isMember: true)

    let cloud = RecipeStore()
    try cloud.replaceLibrary(with: local.exportCloudSnapshot())
    try cloud.setRecipe(first.id, inCollection: collection.id, isMember: false)
    try cloud.setRecipe(second.id, inCollection: collection.id, isMember: false)

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot()
    ).filter { $0.entity == .membership }

    #expect(conflicts.count == 2)
    #expect(Set(conflicts.map(\.id)).count == 2)
}

@Test @MainActor
func sameNamedOfflineCollectionsReturnResolvableConflict() throws {
    let local = RecipeStore()
    let localCollection = try local.createCollection(name: "Dinner")

    let cloud = RecipeStore()
    _ = try cloud.createCollection(name: " dinner ")

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot()
    )
    let conflict = try #require(
        conflicts.first(where: { $0.id.hasPrefix("collection-name:") })
    )

    let choice = LibraryMergeChoice(
        conflict: conflict,
        source: .local
    )
    #expect(
        try local.mergeCloudLibrary(
            with: cloud.exportCloudSnapshot(),
            choices: [choice]
        ).isEmpty
    )
    #expect(local.collections.map(\.id) == [localCollection.id])
}

@Test @MainActor
func sameOfflineMealSlotReturnsResolvableConflict() throws {
    let day = Calendar.current.startOfDay(for: .now)

    let local = RecipeStore()
    let localRecipe = exampleRecipe()
    try local.upsert(localRecipe)
    let localMeal = MealPlanEntry(
        recipeID: localRecipe.id,
        date: day,
        slot: .dinner
    )
    try local.upsertMeal(localMeal)

    let cloud = RecipeStore()
    let cloudRecipe = Recipe(
        title: "Cloud dinner",
        steps: [.init(instruction: "Cook.")]
    )
    try cloud.upsert(cloudRecipe)
    let cloudMeal = MealPlanEntry(
        recipeID: cloudRecipe.id,
        date: day,
        slot: .dinner
    )
    try cloud.upsertMeal(cloudMeal)

    let conflicts = try local.mergeCloudLibrary(
        with: cloud.exportCloudSnapshot()
    )
    let conflict = try #require(
        conflicts.first(where: { $0.id.hasPrefix("meal-slot:") })
    )

    let choice = LibraryMergeChoice(
        conflict: conflict,
        source: .cloud
    )
    #expect(
        try local.mergeCloudLibrary(
            with: cloud.exportCloudSnapshot(),
            choices: [choice]
        ).isEmpty
    )
    #expect(local.mealPlan.map(\.id) == [cloudMeal.id])
}


@Test @MainActor
func groceryMergeIndexPreservesBatchAndCheckedRowSemantics() throws {
    let ingredients = (0..<12).map { _ in
        RecipeIngredient.from(
            name: " Fresh Herbs ",
            amountText: "1 g",
            category: .pantry
        )
    }
    let recipe = exampleRecipe(ingredients: ingredients)
    let store = RecipeStore()
    try store.upsert(recipe)

    // Equal numeric items in one batch merge into the earliest eligible row.
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: Set(ingredients.map(\.id))
    )
    #expect(store.groceries.count == 1)
    #expect(store.groceries[0].quantity == 12)
    #expect(store.groceries[0].recipeIDs == [recipe.id])

    let checkedID = store.groceries[0].id
    try store.toggleGrocery(id: checkedID)

    // Completed rows stay immutable. A new batch creates a new eligible row.
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: Set(ingredients.prefix(3).map(\.id))
    )
    #expect(store.groceries.count == 2)
    #expect(store.groceries[0].id == checkedID)
    #expect(store.groceries[0].quantity == 12)
    #expect(store.groceries[0].isChecked)
    #expect(store.groceries[1].quantity == 3)
}

@Test @MainActor
func groceryConsolidationPreferenceIsNonRetroactive() throws {
    let first = RecipeIngredient.from(
        name: "Tomatoes",
        amountText: "100 g",
        category: .produce
    )
    let second = RecipeIngredient.from(
        name: "Tomatoes",
        amountText: "50 g",
        category: .produce
    )
    let recipe = exampleRecipe(ingredients: [first, second])
    let store = RecipeStore()
    try store.upsert(recipe)

    // With consolidation disabled, even compatible ingredients stay separate.
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [first.id, second.id],
        consolidateCompatibleIngredients: false
    )
    #expect(store.groceries.count == 2)
    #expect(store.groceries[0].quantity == 100)
    #expect(store.groceries[1].quantity == 50)

    // Turning the preference back on combines only a newly added ingredient.
    // Existing rows must not be retroactively rewritten or merged.
    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [first.id],
        consolidateCompatibleIngredients: true
    )
    #expect(store.groceries.count == 2)
    #expect(store.groceries[0].quantity == 200)
    #expect(store.groceries[1].quantity == 50)
    #expect(store.groceries.allSatisfy { $0.recipeIDs == [recipe.id] })
}

@Test @MainActor
func localOnlyClearDoesNotCreateCloudDeletionTombstones() throws {
    let url = try libraryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = RecipeStore(fileURL: url)
    let deletedRecipe = exampleRecipe()
    let remainingRecipe = Recipe(
        title: "Saved soup",
        ingredients: [.from(name: "Broth", amountText: "1 cup")],
        steps: [.init(instruction: "Simmer.")]
    )

    try store.upsert(deletedRecipe)
    try store.deleteRecipe(id: deletedRecipe.id)
    try store.upsert(remainingRecipe)
    try store.addToGroceries(
        recipeID: remainingRecipe.id,
        servings: nil,
        ingredientIDs: Set(remainingRecipe.ingredients.map(\.id))
    )
    try store.updateSettings(
        RecipeSettings(displayName: "Local person", appearance: .dark)
    )

    // A normal reset preserves deletion tombstones for cloud synchronization.
    #expect(
        try store.exportCloudSnapshot().deletedEntities?.contains(
            "recipe:\(deletedRecipe.id.uuidString)"
        ) == true
    )

    // Local-only deletion explicitly discards tombstones and saved preferences.
    try store.clearLocalLibraryOnly()
    #expect(store.recipes.isEmpty)
    #expect(store.groceries.isEmpty)
    #expect(store.mealPlan.isEmpty)
    #expect(store.collections.isEmpty)
    #expect(store.settings == RecipeSettings())
    #expect(try store.exportCloudSnapshot().deletedEntities?.isEmpty == true)

    let restarted = RecipeStore(fileURL: url)
    #expect(restarted.loadError == nil)
    #expect(!restarted.hasUserData)
    #expect(try restarted.exportCloudSnapshot().deletedEntities?.isEmpty == true)
}
