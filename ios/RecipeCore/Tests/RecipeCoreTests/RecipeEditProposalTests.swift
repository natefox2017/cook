// Developer: gengyun
// Purpose: AI proposal safety, conflicts and reversible non-mutating previews.

import Foundation
import Testing
@testable import RecipeCore

@Test
func proposedIngredientAndStepChangesNeverMutateThePrivateRecipeUntilAccepted() throws {
    let ingredient = RecipeIngredient.from(name: "Butter", amountText: "50 g")
    let step = RecipeStep(instruction: "Melt butter in a pan.")
    let old = Recipe(
        title: "Dinner", ingredients: [ingredient], steps: [step],
        sourceURL: "https://example.com/original", sourceText: "Author's recipe",
        notes: "Personal private note", updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let patch = RecipeEditProposal(
        recipeID: old.id, basedOnUpdate: old.updatedAt,
        changes: [
            .ingredientName(
                id: ingredient.id, original: "Butter", proposed: "Olive oil"),
            .ingredientAmount(
                id: ingredient.id, original: "50 g", proposed: "to taste"),
            .stepInstruction(
                id: step.id, original: "Melt butter in a pan.",
                proposed: "Heat oil in a pan.")
        ],
        reasons: ["Substitute to avoid dairy."],
        warnings: ["Verify cooking temperature and amount."]
    )
    let preview = try patch.preview(on: old)
    #expect(old.ingredients[0].name == "Butter")
    #expect(preview.after.ingredients[0].name == "Olive oil")
    #expect(preview.after.ingredients[0].quantity == nil)
    #expect(preview.after.ingredients[0].amountText == "to taste")
    #expect(preview.after.steps[0].timers == old.steps[0].timers)
    #expect(preview.after.sourceURL == old.sourceURL)
    #expect(preview.after.sourceText == old.sourceText)
    #expect(preview.after.notes == old.notes)
    #expect(preview.reasons.count == 1)
    let variant = try patch.approvedRecipe(
        from: old, at: Date(timeIntervalSince1970: 1100), asVariant: true)
    #expect(variant.id != old.id)
    #expect(variant.createdAt == Date(timeIntervalSince1970: 1100))
    #expect(old.updatedAt == Date(timeIntervalSince1970: 1000))
}

@Test
func proposedEditsRejectStaleRevisionsUnexpectedPathsAndUnsafeText() throws {
    let ingredient = RecipeIngredient(name: "Salt", amountText: "to taste")
    let old = Recipe(
        title: "Soup", ingredients: [ingredient],
        steps: [.init(instruction: "Mix.")],
        updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let good = RecipeEditChange.ingredientName(
        id: ingredient.id, original: "Salt", proposed: "Pepper")
    let duplicate = RecipeEditProposal(
        recipeID: old.id, basedOnUpdate: old.updatedAt, changes: [good, good])
    #expect(throws: RecipeEditProposalError.duplicatedPath) {
        try duplicate.preview(on: old)
    }
    let stale = RecipeEditProposal(
        recipeID: old.id,
        basedOnUpdate: Date(timeIntervalSince1970: 999),
        changes: [good])
    #expect(throws: RecipeEditProposalError.staleRecipe) {
        try stale.preview(on: old)
    }
    let wrongOriginal = RecipeEditProposal(
        recipeID: old.id, basedOnUpdate: old.updatedAt,
        changes: [.ingredientName(id: ingredient.id, original: "Sugar", proposed: "Pepper")])
    #expect(throws: RecipeEditProposalError.sourceChanged) {
        try wrongOriginal.preview(on: old)
    }
    let unknown = RecipeEditProposal(
        recipeID: old.id, basedOnUpdate: old.updatedAt,
        changes: [.ingredientName(id: UUID(), original: "Salt", proposed: "Pepper")])
    #expect(throws: RecipeEditProposalError.missingField) {
        try unknown.preview(on: old)
    }
    let blank = RecipeEditProposal(
        recipeID: old.id, basedOnUpdate: old.updatedAt,
        changes: [.ingredientAmount(id: ingredient.id, original: "to taste", proposed: " ")])
    #expect(throws: RecipeEditProposalError.invalidReplacement) {
        try blank.preview(on: old)
    }
}

@Test
func aiEditProposalHasBoundedOperationsAndNoSharedImportJobForVariants() throws {
    let ingredient = RecipeIngredient.from(name: "Flour", amountText: "100 g")
    var recipe = Recipe(title: "Bread", ingredients: [ingredient],
        steps: [.init(instruction: "Knead")], sourceURL: "https://example.org/bread",
        notes: "Personal")
    let evidence = RecipeImportJobResponse.Result(
        recipeID: recipe.id, status: "ready",
        source: .init(inputType: "url"), fields: [:])
    recipe.importRecord = RecipeImportRecord(jobID: UUID(), result: evidence)
    recipe.isFavorite = true
    let change = RecipeEditChange.ingredientName(
        id: ingredient.id, original: "Flour", proposed: "Wheat flour")
    let oversized = RecipeEditProposal(
        recipeID: recipe.id, basedOnUpdate: recipe.updatedAt,
        changes: Array(repeating: change, count: 31))
    #expect(throws: RecipeEditProposalError.oversizedProposal) {
        try oversized.preview(on: recipe)
    }
    let overlongReason = RecipeEditProposal(
        recipeID: recipe.id, basedOnUpdate: recipe.updatedAt,
        changes: [change], reasons: [String(repeating: "x", count: 301)])
    #expect(throws: RecipeEditProposalError.oversizedProposal) {
        try overlongReason.preview(on: recipe)
    }
    let valid = RecipeEditProposal(
        recipeID: recipe.id, basedOnUpdate: recipe.updatedAt, changes: [change])
    let variant = try valid.approvedRecipe(from: recipe, asVariant: true)
    #expect(variant.id != recipe.id)
    #expect(variant.importRecord == nil)
    #expect(variant.isFavorite == false)
    #expect(variant.sourceURL == recipe.sourceURL)
    #expect(variant.notes == recipe.notes)
    #expect(recipe.importRecord != nil)
}
