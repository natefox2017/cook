// Developer: gengyun
// Purpose: Validate opt-in sharing never publishes private recipe state or unlicensed instructions.

import Foundation
import Testing
@testable import RecipeCore

@Test
func summaryOnlyRecipeIsSafeAndContainsNoPrivateNotesOrMedia() throws {
    var recipe = Recipe(
        title: "Soup", summary: "Warm soup", servings: 2,
        ingredients: [.from(name: "Carrot", amountText: "2 pieces")],
        steps: [.init(instruction: "Simmer.")],
        sourceURL: "https://example.org/soup", notes: "My private note")
    recipe.coverData = Data([1, 2, 3])
    recipe.stepImages = [
        RecipeStepImageReference(
            stepID: recipe.steps[0].id,
            privateAssetPath: "users/secret-photo.png"
        )
    ]
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let result = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    #expect(result.title == "Soup")
    #expect(result.ingredients.isEmpty)
    #expect(result.steps.isEmpty)
    #expect(result.sourceURL == "https://example.org/soup")
    let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!json.contains("private"))
    #expect(!json.contains("secret-photo"))
    #expect(!json.contains("owner_id"))
    #expect(!json.contains("coverData"))
    #expect(!json.contains("importRecord"))
}

@Test
func unlicensedOrStaleFullShareIsRejectedWithoutDataChanges() throws {
    let recipe = Recipe(
        title: "Cake",
        ingredients: [.from(name: "Flour", amountText: "100 g")],
        steps: [.init(instruction: "Bake in oven.")])
    let refused = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: false)
    #expect(throws: RecipeShareValidationError.rightsNotConfirmed) {
        _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: refused)
    }
    let stale = RecipeShareApproval(
        recipeID: recipe.id,
        expectedUpdatedAt: recipe.updatedAt.addingTimeInterval(-1),
        scope: .summaryAndSource, hasDistributionRights: false)
    #expect(throws: RecipeShareValidationError.staleRecipe) {
        _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: stale)
    }
    let accepted = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: true)
    let preview = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: accepted)
    #expect(preview.steps.map(\.instruction) == ["Bake in oven."])
    #expect(preview.ingredients.map(\.amountText) == ["100 g"])
    #expect(recipe.notes.isEmpty)
}

@Test
func malformedSourceURLNeverBecomesPublicHyperlink() throws {
    let recipe = Recipe(title: "Salad", sourceURL: "javascript:alert(1)")
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let result = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    #expect(result.sourceURL == nil)
}
