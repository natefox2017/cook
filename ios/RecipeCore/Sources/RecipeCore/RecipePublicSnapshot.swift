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
        let full = approval.scope == .fullInstructions
        guard !full || approval.hasDistributionRights else {
            throw RecipeShareValidationError.rightsNotConfirmed
        }

        // Validate UTF-16 lengths to match the public Web reader's String.length.
        guard title.utf16.count <= 180, recipe.summary.utf16.count <= 2_000,
            Self.isWithin(recipe.servings, 1...100),
            Self.isWithin(recipe.prepMinutes, 0...10_080),
            Self.isWithin(recipe.cookMinutes, 0...10_080),
            (!full || recipe.ingredients.count <= 200),
            (!full || recipe.steps.count <= 100)
        else { throw RecipeShareValidationError.contentTooLarge }
        let ingredients: [PublicRecipeIngredient] = try full
            ? recipe.ingredients.map { ingredient in
                guard !ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    ingredient.name.utf16.count <= 180,
                    ingredient.amountText.utf16.count <= 120
                else {
                    throw RecipeShareValidationError.contentTooLarge
                }
                return PublicRecipeIngredient(
                    name: ingredient.name, amountText: ingredient.amountText)
            }
            : []
        let steps: [PublicRecipeStep] = try full
            ? recipe.steps.map { step in
                guard !step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    step.title.utf16.count <= 220,
                    step.instruction.utf16.count <= 6_000
                else {
                    throw RecipeShareValidationError.contentTooLarge
                }
                return PublicRecipeStep(
                    title: step.title, instruction: step.instruction)
            }
            : []

        // The preview cannot imply permission to publish source access tokens.
        // A private recipe always retains its original URL unchanged.
        let validSource = RecipePublicCitation.eligibleURL(recipe.sourceURL)

        let snapshot = PublicRecipeSnapshot(
            title: title, summary: recipe.summary,
            sourceURL: validSource, servings: recipe.servings,
            prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes,
            ingredients: ingredients, steps: steps
        )
        // Bound the actual escaped JSON, not just the unencoded text.
        guard try JSONEncoder().encode(snapshot).count <= 2 * 1024 * 1024 else {
            throw RecipeShareValidationError.contentTooLarge
        }
        return snapshot
    }

    private static func isWithin(_ value: Int?, _ bounds: ClosedRange<Int>) -> Bool {
        value.map(bounds.contains) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case title, summary, sourceURL, servings, prepMinutes, cookMinutes, ingredients, steps
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        // Unlike encodeIfPresent, encode writes explicit null for nil optional fields.
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(servings, forKey: .servings)
        try container.encode(prepMinutes, forKey: .prepMinutes)
        try container.encode(cookMinutes, forKey: .cookMinutes)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
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
