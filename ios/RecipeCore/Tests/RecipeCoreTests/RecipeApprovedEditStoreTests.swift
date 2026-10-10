// Developer: gengyun
// Purpose: Tests local revision-checked persistence for explicitly approved recipe edits.

import Foundation
import Testing
@testable import RecipeCore

private func reviewableRecipe() -> Recipe {
    let butter = RecipeIngredient.from(
        name: "Butter", amountText: "50 g", category: .dairy
    )
    let steps = (1...8).map { step in
        RecipeStep(instruction: "Preparation step \(step).")
    }
    return Recipe(
        title: "Private pasta", servings: 2,
        ingredients: [butter], steps: steps,
        sourceURL: "https://example.org/author/recipe",
        sourceText: "Author's original recipe evidence",
        isFavorite: true, notes: "Keep this personal note",
        createdAt: Date(timeIntervalSince1970: 1_600_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func replacementProposal(for recipe: Recipe) -> RecipeEditProposal {
    RecipeEditProposal(
        recipeID: recipe.id,
        basedOnUpdate: recipe.updatedAt,
        changes: [
            .ingredientName(
                id: recipe.ingredients[0].id,
                original: recipe.ingredients[0].name,
                proposed: "Olive oil"
            )
        ],
        reasons: ["A user-reviewed dairy substitution."],
        warnings: ["Confirm the appropriate cooking technique."]
    )
}

@Test @MainActor
func approvedRecipeEditRejectsInterveningUpdatesAndReplayWithoutLosingPrivateChanges() throws {
    let store = RecipeStore()
    let original = reviewableRecipe()
    let sibling = Recipe(
        title: "Unrelated soup",
        ingredients: [.from(name: "Carrot", amountText: "2")],
        steps: [.init(instruction: "Simmer.")]
    )
    try store.upsert(original)
    try store.upsert(sibling)

    let initial = try #require(store.recipe(id: original.id))
    let siblingBefore = try #require(store.recipe(id: sibling.id))
    let staleProposal = replacementProposal(for: initial)

    var manuallyChanged = initial
    manuallyChanged.notes = "Keep this newer edit"
    try store.upsert(manuallyChanged)
    let current = try #require(store.recipe(id: original.id))
    let beforeFailedApproval = store.recipes

    #expect(throws: RecipeEditProposalError.staleRecipe) {
        try store.applyApprovedRecipeEdit(staleProposal)
    }
    #expect(store.recipes == beforeFailedApproval)

    let freshProposal = replacementProposal(for: current)
    let approved = try store.applyApprovedRecipeEdit(
        freshProposal, at: Date(timeIntervalSince1970: 0)
    )
    #expect(approved.updatedAt > current.updatedAt)
    #expect(approved.id == current.id)
    #expect(approved.createdAt == current.createdAt)
    #expect(approved.ingredients[0].name == "Olive oil")
    #expect(approved.notes == "Keep this newer edit")
    #expect(approved.sourceURL == current.sourceURL)
    #expect(approved.sourceText == current.sourceText)
    #expect(approved.steps == current.steps)
    #expect(approved.isFavorite == current.isFavorite)
    #expect(store.recipe(id: current.id) == approved)
    #expect(store.recipe(id: sibling.id) == siblingBefore)

    // An approved patch cannot be applied again against the old preview revision.
    #expect(throws: RecipeEditProposalError.staleRecipe) {
        try store.applyApprovedRecipeEdit(freshProposal)
    }
    #expect(store.recipe(id: current.id) == approved)
}

@Test @MainActor
func approvedRecipeEditCanCreateAPrivateVariantWithoutChangingOriginalOrShoppingState() throws {
    let store = RecipeStore()
    var original = reviewableRecipe()
    let imported = RecipeImportJobResponse.Result(
        recipeID: original.id,
        status: "ready",
        source: .init(inputType: "url"),
        fields: [:]
    )
    original.importRecord = RecipeImportRecord(jobID: UUID(), result: imported)
    try store.upsert(original)
    try store.addToGroceries(
        recipeID: original.id,
        servings: original.servings,
        ingredientIDs: Set(original.ingredients.map(\.id))
    )
    let before = try #require(store.recipe(id: original.id))
    let groceriesBefore = store.groceries
    let plansBefore = store.mealPlan
    let membershipsBefore = store.collectionMemberships

    let variant = try store.applyApprovedRecipeEdit(
        replacementProposal(for: before), asVariant: true,
        at: Date(timeIntervalSince1970: 0)
    )

    #expect(variant.id != before.id)
    #expect(variant.createdAt == variant.updatedAt)
    #expect(variant.updatedAt > before.updatedAt)
    #expect(variant.ingredients[0].name == "Olive oil")
    #expect(variant.importRecord == nil)
    #expect(variant.isFavorite == false)
    #expect(variant.sourceURL == before.sourceURL)
    #expect(variant.sourceText == before.sourceText)
    #expect(variant.notes == before.notes)
    #expect(store.recipe(id: original.id) == before)
    #expect(store.recipe(id: variant.id) == variant)
    #expect(store.recipes.count == 2)
    #expect(store.groceries == groceriesBefore)
    #expect(store.mealPlan == plansBefore)
    #expect(store.collectionMemberships == membershipsBefore)
}

@Test @MainActor
func approvedRecipeEditRejectsUnknownRecipesAndInvalidPatchesWithoutAnyWrites() throws {
    let store = RecipeStore()
    try store.upsert(reviewableRecipe())
    let saved = try #require(store.recipes.first)
    let before = store.recipes

    let missing = RecipeEditProposal(
        recipeID: UUID(),
        basedOnUpdate: saved.updatedAt,
        changes: [
            .ingredientName(
                id: saved.ingredients[0].id,
                original: "Butter", proposed: "Olive oil"
            )
        ]
    )
    #expect(throws: RecipeStoreError.missingRecipe) {
        try store.applyApprovedRecipeEdit(missing)
    }

    let wrongOriginal = RecipeEditProposal(
        recipeID: saved.id,
        basedOnUpdate: saved.updatedAt,
        changes: [
            .ingredientName(
                id: saved.ingredients[0].id,
                original: "Sugar", proposed: "Olive oil"
            )
        ]
    )
    #expect(throws: RecipeEditProposalError.sourceChanged) {
        try store.applyApprovedRecipeEdit(wrongOriginal)
    }

    let invalidReplacement = RecipeEditProposal(
        recipeID: saved.id,
        basedOnUpdate: saved.updatedAt,
        changes: [
            .ingredientName(
                id: saved.ingredients[0].id,
                original: "Butter", proposed: "   "
            )
        ]
    )
    #expect(throws: RecipeEditProposalError.invalidReplacement) {
        try store.applyApprovedRecipeEdit(invalidReplacement)
    }
    #expect(store.recipes == before)
}

@Test @MainActor
func approvedRecipeEditDiskFailureKeepsLastStoredRecipeAndOriginalBytes() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecipeApprovedEdit-" + UUID().uuidString)
    try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let activeDirectory = root.appendingPathComponent("active")
    let fileURL = activeDirectory.appendingPathComponent("library.json")
    let store = RecipeStore(fileURL: fileURL)
    let original = reviewableRecipe()
    try store.upsert(original)

    let before = try #require(store.recipe(id: original.id))
    let bytesBefore = try Data(contentsOf: fileURL)
    let archivedDirectory = root.appendingPathComponent("archived")
    try FileManager.default.moveItem(at: activeDirectory, to: archivedDirectory)
    // A regular file at the expected parent directory forces a deterministic write error.
    try Data("Not a directory".utf8).write(to: activeDirectory)

    #expect(throws: (any Error).self) {
        try store.applyApprovedRecipeEdit(replacementProposal(for: before))
    }
    #expect(store.recipe(id: original.id) == before)
    #expect(store.recipes.count == 1)
    #expect(
        try Data(contentsOf: archivedDirectory.appendingPathComponent("library.json"))
            == bytesBefore
    )
    #expect(try Data(contentsOf: activeDirectory) == Data("Not a directory".utf8))
}
