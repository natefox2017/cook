// Developer: gengyun
// Purpose: Ensure generated recipe edit proposals cannot overwrite unapproved user data.

import Foundation
import Testing
@testable import RecipeCore

@Test
func proposedSubstitutionIsAReviewableCopyWithStableIngredientLink() throws {
    let ingredient = RecipeIngredient.from(name: "Butter", amountText: "50 g")
    let step = RecipeStep(
        instruction: "Melt the butter.",
        linkedIngredientIDs: [ingredient.id]
    )
    let original = Recipe(
        title: "Sauce", servings: 2, ingredients: [ingredient], steps: [step],
        sourceURL: "https://example.test/original",
        sourceText: "Original owner's recipe",
        notes: "Private family note"
    )
    let proposal = RecipeEditProposal(
        recipeID: original.id, expectedUpdatedAt: original.updatedAt,
        explanation: "Replace butter with olive oil.",
        operations: [
            .replaceIngredient(id: ingredient.id, name: "Olive oil", amountText: nil),
            .editStep(id: step.id, instruction: "Warm the olive oil."),
            .setServings(4)
        ]
    )
    let preview = try proposal.preview(on: original)
    #expect(original.ingredients[0].name == "Butter")
    #expect(original.servings == 2)
    #expect(preview.ingredients[0].name == "Olive oil")
    #expect(preview.ingredients[0].id == ingredient.id)
    #expect(preview.ingredients[0].amountText == "50 g")
    #expect(preview.steps[0].linkedIngredientIDs == [ingredient.id])
    #expect(preview.steps[0].instruction == "Warm the olive oil.")
    #expect(preview.steps[0].id == step.id)
    #expect(preview.servings == 4)
    #expect(preview.sourceText == original.sourceText)
    #expect(preview.sourceURL == original.sourceURL)
    #expect(preview.notes == original.notes)
    let decoded = try JSONDecoder().decode(
        RecipeEditProposal.self, from: JSONEncoder().encode(proposal))
    #expect(decoded == proposal)
}

@Test
func invalidOrStaleSuggestionsCannotChangeExistingRecipe() throws {
    let recipe = Recipe(
        title: "Toast", ingredients: [.from(name: "Bread", amountText: "2 slices")],
        steps: [.init(instruction: "Toast it.")])
    let wrong = RecipeEditProposal(
        recipeID: UUID(), expectedUpdatedAt: recipe.updatedAt,
        explanation: "Test", operations: [.setServings(4)])
    #expect(throws: RecipeEditProposalError.wrongRecipe) {
        _ = try wrong.preview(on: recipe)
    }
    let stale = RecipeEditProposal(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt.addingTimeInterval(-1),
        explanation: "Test", operations: [.setServings(4)])
    #expect(throws: RecipeEditProposalError.staleRecipe) {
        _ = try stale.preview(on: recipe)
    }
    let invented = RecipeEditProposal(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        explanation: "Test",
        operations: [.replaceIngredient(id: UUID(), name: "Sugar", amountText: "5 g")])
    #expect(throws: RecipeEditProposalError.missingIngredient) {
        _ = try invented.preview(on: recipe)
    }
    #expect(recipe.ingredients[0].name == "Bread")
    let excessive = RecipeEditProposal(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        explanation: "Test", operations: [.setServings(0)])
    #expect(throws: RecipeEditProposalError.invalidOperation) {
        _ = try excessive.preview(on: recipe)
    }
}

@Test
func recipeVariantRetainsSourceButNeverOverwritesOriginal() throws {
    let original = Recipe(title: "Salad", sourceURL: "https://example.test/salad")
    let proposal = RecipeEditProposal(
        recipeID: original.id, expectedUpdatedAt: original.updatedAt,
        explanation: "Make more servings.", operations: [.setServings(3)])
    let variantID = UUID()
    let variant = try proposal.privateVariant(of: original, id: variantID)
    #expect(variant.id == variantID)
    #expect(variant.sourceURL == original.sourceURL)
    #expect(variant.isFavorite == false)
    #expect(original.id != variant.id)
    #expect(original.servings != 3)
}
