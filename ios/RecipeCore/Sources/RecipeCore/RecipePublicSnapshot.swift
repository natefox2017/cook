// Developer: gengyun
// Purpose: Create an explicit, rights-filtered public recipe payload; never serialize Recipe itself.

import Foundation

public enum RecipeShareScope: String, Codable, Equatable, Sendable {
    case summaryAndSource
    case fullInstructions
}

/// Public publication is never inferred from a local save, import or AI draft.
public struct RecipeShareApproval: Codable, Equatable, Sendable {
    public let recipeID: UUID
    public let expectedUpdatedAt: Date
    public let scope: RecipeShareScope
    public let hasDistributionRights: Bool

    public init(
        recipeID: UUID, expectedUpdatedAt: Date,
        scope: RecipeShareScope, hasDistributionRights: Bool
    ) {
        self.recipeID = recipeID
        self.expectedUpdatedAt = expectedUpdatedAt
        self.scope = scope
        self.hasDistributionRights = hasDistributionRights
    }
}

public enum RecipeShareValidationError: Error, Equatable, Sendable {
    case staleRecipe
    case wrongRecipe
    case rightsNotConfirmed
    case missingTitle
    case contentTooLarge
}

public struct PublicRecipeIngredient: Codable, Equatable, Sendable {
    public let name: String
    public let amountText: String
}

public struct PublicRecipeStep: Codable, Equatable, Sendable {
    public let title: String
    public let instruction: String
}

/// The only payload that a future *separate* authenticated publishing endpoint may
/// serialize to public storage. It contains no owner ID, private media or notes.
public struct PublicRecipeSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let summary: String
    public let sourceURL: String?
    public let servings: Int?
    public let prepMinutes: Int?
    public let cookMinutes: Int?
    public let ingredients: [PublicRecipeIngredient]
    public let steps: [PublicRecipeStep]

    public static func preview(
        of recipe: Recipe, approvedBy approval: RecipeShareApproval
    ) throws -> PublicRecipeSnapshot {
        guard recipe.id == approval.recipeID else {
            throw RecipeShareValidationError.wrongRecipe
        }
        guard recipe.updatedAt == approval.expectedUpdatedAt else {
            throw RecipeShareValidationError.staleRecipe
        }
        let title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RecipeShareValidationError.missingTitle }
        guard title.count <= 180, recipe.summary.count <= 2_000,
            recipe.ingredients.count <= 200, recipe.steps.count <= 100
        else { throw RecipeShareValidationError.contentTooLarge }

        let full = approval.scope == .fullInstructions
        guard !full || approval.hasDistributionRights else {
            throw RecipeShareValidationError.rightsNotConfirmed
        }
        let ingredients: [PublicRecipeIngredient] = try full
            ? recipe.ingredients.map { ingredient in
                guard ingredient.name.count <= 180, ingredient.amountText.count <= 120 else {
                    throw RecipeShareValidationError.contentTooLarge
                }
                return PublicRecipeIngredient(
                    name: ingredient.name, amountText: ingredient.amountText)
            }
            : []
        let steps: [PublicRecipeStep] = try full
            ? recipe.steps.map { step in
                guard step.title.count <= 220, step.instruction.count <= 6_000 else {
                    throw RecipeShareValidationError.contentTooLarge
                }
                return PublicRecipeStep(
                    title: step.title, instruction: step.instruction)
            }
            : []

        // Preserve attribution only for a syntactically valid public Web URL.
        let validSource: String?
        if let raw = recipe.sourceURL, let components = URLComponents(string: raw),
            let scheme = components.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            components.host != nil, components.user == nil, components.password == nil
        {
            validSource = raw
        } else {
            validSource = nil
        }

        return PublicRecipeSnapshot(
            title: title, summary: recipe.summary,
            sourceURL: validSource, servings: recipe.servings,
            prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes,
            ingredients: ingredients, steps: steps
        )
    }

    private init(
        title: String, summary: String, sourceURL: String?,
        servings: Int?, prepMinutes: Int?, cookMinutes: Int?,
        ingredients: [PublicRecipeIngredient], steps: [PublicRecipeStep]
    ) {
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.steps = steps
    }
}
