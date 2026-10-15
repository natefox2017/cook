// Developer: gengyun
// Purpose: Main-path coverage for reviewable translation proposals and service approval.

import Foundation
import Testing
@testable import RecipeCore

@Test
func translationPreviewProducesLocalizedCopyWithoutMutatingTheSource() throws {
    let ingredient = RecipeIngredient.from(name: "Butter", amountText: "50 g")
    let step = RecipeStep(instruction: "Melt butter in a pan.")
    let original = Recipe(
        title: "Dinner", summary: "A quick meal.",
        ingredients: [ingredient], steps: [step],
        sourceURL: "https://example.com/original", sourceName: "Author",
        updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let proposal = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "zh-Hans",
        title: "晚餐", summary: "一顿快手的餐食。",
        ingredientNames: [.init(id: ingredient.id, original: "Butter", translated: "黄油")],
        stepInstructions: [.init(id: step.id, original: "Melt butter in a pan.", translated: "在锅中融化黄油。")],
        sourceURL: original.sourceURL, sourceName: original.sourceName
    )
    let preview = try proposal.preview(on: original)
    #expect(original.title == "Dinner")
    #expect(original.ingredients[0].name == "Butter")
    #expect(preview.after.title == "晚餐")
    #expect(preview.after.ingredients[0].name == "黄油")
    #expect(preview.after.ingredients[0].amountText == "50 g")
    #expect(preview.after.ingredients[0].quantity == ingredient.quantity)
    #expect(preview.after.ingredients[0].unit == ingredient.unit)
    #expect(preview.after.steps[0].timers == original.steps[0].timers)
    #expect(preview.after.sourceURL == original.sourceURL)
    #expect(preview.after.sourceName == original.sourceName)
    #expect(preview.provenance.originalRecipeID == original.id)
    #expect(preview.provenance.targetLocale == "zh-Hans")
}

@Test
func translationRejectsStaleRecipesUnsupportedLocalesAndNumericFabrication() throws {
    let ingredient = RecipeIngredient(name: "Salt", amountText: "to taste")
    let original = Recipe(
        title: "Soup", ingredients: [ingredient],
        steps: [.init(instruction: "Mix.")],
        updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let stale = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: Date(timeIntervalSince1970: 999),
        targetLocale: "zh-Hans", title: "汤"
    )
    #expect(throws: RecipeTranslationProposalError.staleRecipe) {
        _ = try stale.preview(on: original)
    }
    let unsupported = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "de", title: "Suppe"
    )
    #expect(throws: RecipeTranslationProposalError.unsupportedLocale) {
        _ = try unsupported.preview(on: original)
    }
    // A vague amount must never be invented into an exact one.
    let fabricated = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "zh-Hans",
        ingredientAmounts: [.init(id: ingredient.id, original: "to taste", translated: "1 tsp")]
    )
    #expect(throws: RecipeTranslationProposalError.numericValueChanged) {
        _ = try fabricated.preview(on: original)
    }
    let vague = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "zh-Hans",
        ingredientAmounts: [.init(id: ingredient.id, original: "to taste", translated: "适量")]
    )
    #expect(try vague.preview(on: original).after.ingredients[0].amountText == "适量")
}

@Test
func approvedVariantIsStableAndPreservesProvenance() throws {
    let ingredient = RecipeIngredient(name: "Flour", amountText: "100 g")
    let original = Recipe(
        title: "Bread", ingredients: [ingredient],
        steps: [.init(instruction: "Knead.")],
        sourceURL: "https://example.com/bread",
        updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let proposal = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "ja",
        title: "パン",
        ingredientNames: [.init(id: ingredient.id, original: "Flour", translated: "小麦粉")],
        sourceURL: original.sourceURL
    )
    let first = try proposal.approvedVariant(from: original, at: Date(timeIntervalSince1970: 1100))
    let second = try proposal.approvedVariant(from: original, at: Date(timeIntervalSince1970: 1200))
    #expect(first.id == proposal.variantRecipeID)
    #expect(first.id == second.id)
    #expect(first.id != original.id)
    #expect(first.importRecord == nil)
    #expect(first.sourceURL == original.sourceURL)
    #expect(first.isFavorite == false)
    #expect(original.updatedAt == Date(timeIntervalSince1970: 1000))
}

@Test
func serviceApprovalSavesIdempotentlyAndLeavesSourceUntouched() async throws {
    let ingredient = RecipeIngredient(name: "Egg", amountText: "2")
    let original = Recipe(
        title: "Omelette", ingredients: [ingredient],
        steps: [.init(instruction: "Beat eggs.")],
        updatedAt: Date(timeIntervalSince1970: 1000)
    )
    let proposal = RecipeTranslationProposal(
        recipeID: original.id, basedOnUpdate: original.updatedAt,
        targetLocale: "zh-Hant",
        title: "煎蛋",
        ingredientNames: [.init(id: ingredient.id, original: "Egg", translated: "雞蛋")]
    )

    struct Provider: RecipeTranslationProviderPort {
        func translate(_ request: RecipeTranslationRequest) async throws -> RecipeTranslationProposal {
            throw CancellationError()
        }
    }
    final class Save: RecipeTranslationSavePort, @unchecked Sendable {
        var stored: [UUID: Recipe] = [:]
        func saveVariant(
            _ variant: Recipe, provenance: RecipeTranslationProvenance
        ) async throws -> Recipe {
            stored[variant.id] = variant
            return variant
        }
    }

    let save = Save()
    let service = RecipeTranslationService(provider: Provider(), save: save)
    let first = try await service.saveVariant(proposal, original: original)
    let second = try await service.saveVariant(proposal, original: original)
    #expect(first.id == second.id)
    #expect(save.stored.count == 1)
    #expect(original.title == "Omelette")
    #expect(original.ingredients[0].name == "Egg")
}
