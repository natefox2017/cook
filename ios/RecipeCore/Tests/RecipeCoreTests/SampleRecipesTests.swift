// Developer: gengyun
// Purpose: Verify sample recipe content stays aligned with its cover asset.

import Testing

@testable import RecipeCore

@Test
func roastChickenSampleUsesChickenCoverAndMatchingRecipeContent() {
    let recipe = SampleRecipes.recipes.first { $0.title == "Roast chicken & potatoes" }

    #expect(recipe != nil)
    #expect(recipe?.coverAsset == "chicken")
    #expect(recipe?.ingredients.map(\.name).contains("Chicken thighs") == true)
    #expect(recipe?.ingredients.map(\.name).contains("Baby potatoes") == true)

    let instructions = recipe?.steps.map(\.instruction).joined(separator: " ").lowercased()
    #expect(instructions?.contains("chicken") == true)
    #expect(instructions?.contains("potatoes") == true)
}
