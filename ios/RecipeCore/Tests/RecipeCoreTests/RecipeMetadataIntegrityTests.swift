// Developer: gengyun
// Purpose: Test that recipe editing and persistence preserve valid optional metadata references.

import Foundation
import Testing
@testable import RecipeCore

@Test @MainActor
func deletingIngredientRetainsOnlyExistingStepAndSectionLinks() throws {
    let flour = RecipeIngredient(name: "Flour", amountText: "200 g")
    let water = RecipeIngredient(name: "Water", amountText: "100 ml")
    let step = RecipeStep(
        instruction: "Combine flour and water.",
        linkedIngredientIDs: [flour.id, water.id]
    )
    let dry = RecipeIngredientSection(title: "Dry", ingredientIDs: [flour.id])
    let mix = RecipeIngredientSection(
        title: "Mix", ingredientIDs: [flour.id, water.id]
    )
    var recipe = Recipe(
        title: "Bread", ingredients: [flour, water], steps: [step],
        ingredientSections: [dry, mix]
    )

    recipe.removeIngredient(id: flour.id)

    #expect(recipe.ingredients.map(\.id) == [water.id])
    #expect(recipe.steps[0].linkedIngredientIDs == [water.id])
    #expect(recipe.ingredientSections?.map(\.id) == [mix.id])
    #expect(recipe.ingredientSections?[0].ingredientIDs == [water.id])

    let store = RecipeStore()
    try store.upsert(recipe)
    #expect(store.recipe(id: recipe.id)?.ingredientSections?[0].id == mix.id)
}

@Test @MainActor
func deletingStepRetainsOtherStepImages() throws {
    let first = RecipeStep(instruction: "Mix.")
    let second = RecipeStep(instruction: "Bake.")
    let removed = RecipeStepImageReference(
        stepID: first.id, privateAssetPath: "private/old.jpg"
    )
    let retained = RecipeStepImageReference(
        stepID: second.id, privateAssetPath: "private/current.jpg"
    )
    var recipe = Recipe(
        title: "Bread", steps: [first, second], stepImages: [removed, retained]
    )

    recipe.removeStep(id: first.id)

    #expect(recipe.steps.map(\.id) == [second.id])
    #expect(recipe.stepImages?.map(\.id) == [retained.id])

    let store = RecipeStore()
    try store.upsert(recipe)
    #expect(store.recipe(id: recipe.id)?.stepImages?.map(\.id) == [retained.id])
}

@Test
func pruningAfterEditorDiscardsEmptyRowsWithoutDroppingValidReferences() {
    let kept = RecipeIngredient(name: "Oil")
    let step = RecipeStep(
        instruction: "Add oil.",
        linkedIngredientIDs: [UUID(), kept.id]
    )
    var recipe = Recipe(title: "Oil", ingredients: [kept], steps: [step])
    recipe.pruneDanglingReferences()

    #expect(recipe.steps[0].linkedIngredientIDs == [kept.id])
    #expect(recipe.ingredientSections == nil)
    #expect(recipe.stepImages == nil)
}

@Test @MainActor
func storeRejectsDanglingIngredientSectionLinks() {
    let known = RecipeIngredient(name: "Sugar")
    let invalidSection = RecipeIngredientSection(
        title: "Topping", ingredientIDs: [UUID()]
    )
    let recipe = Recipe(
        title: "Cake", ingredients: [known],
        steps: [RecipeStep(instruction: "Mix.")],
        ingredientSections: [invalidSection]
    )
    let store = RecipeStore()
    #expect(throws: RecipeStoreError.self) {
        try store.upsert(recipe)
    }
    #expect(store.recipes.isEmpty)
}

@Test @MainActor
func storeRejectsStepImageReferencesToRemovedSteps() {
    let step = RecipeStep(instruction: "Roast.")
    let invalidImage = RecipeStepImageReference(
        stepID: UUID(), privateAssetPath: "private/stale.jpg"
    )
    let recipe = Recipe(
        title: "Roast", steps: [step], stepImages: [invalidImage]
    )
    let store = RecipeStore()
    #expect(throws: RecipeStoreError.self) {
        try store.upsert(recipe)
    }
    #expect(store.recipes.isEmpty)
}
