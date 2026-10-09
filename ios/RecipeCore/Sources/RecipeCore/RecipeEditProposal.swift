// Developer: gengyun
// Purpose: Validate and preview AI-suggested recipe edits without mutating the user's original.

import Foundation

/// The only fields a recipe-editing provider is allowed to propose changing.
/// This intentionally excludes provenance, privacy, notes, timers and source media.
public enum RecipeEditOperation: Codable, Equatable, Sendable {
    case replaceIngredient(id: UUID, name: String, amountText: String?)
    case editStep(id: UUID, instruction: String)
    case setServings(Int)
    case editSummary(String)
}

public enum RecipeEditProposalError: Error, Equatable, Sendable {
    case wrongRecipe
    case staleRecipe
    case invalidOperation
    case missingIngredient
    case missingStep
}

/// A proposal is an untrusted suggestion until the user explicitly accepts its preview.
public struct RecipeEditProposal: Codable, Equatable, Sendable {
    public let id: UUID
    public let recipeID: UUID
    public let expectedUpdatedAt: Date
    public let explanation: String
    public let operations: [RecipeEditOperation]

    public init(
        id: UUID = UUID(), recipeID: UUID, expectedUpdatedAt: Date,
        explanation: String, operations: [RecipeEditOperation]
    ) {
        self.id = id
        self.recipeID = recipeID
        self.expectedUpdatedAt = expectedUpdatedAt
        self.explanation = explanation
        self.operations = operations
    }

    /// Returns an in-memory copy. Callers must display a diff before they persist it.
    /// Exact source amounts are never guessed: explicit changes are parsed conservatively.
    public func preview(on recipe: Recipe, at date: Date = .now) throws -> Recipe {
        guard recipe.id == recipeID else { throw RecipeEditProposalError.wrongRecipe }
        guard recipe.updatedAt == expectedUpdatedAt else {
            throw RecipeEditProposalError.staleRecipe
        }
        guard !operations.isEmpty, operations.count <= 20,
            explanation.count <= 3_000
        else { throw RecipeEditProposalError.invalidOperation }

        var changed = recipe
        for operation in operations {
            switch operation {
            case let .replaceIngredient(id, rawName, rawAmount):
                guard let index = changed.ingredients.firstIndex(where: { $0.id == id }) else {
                    throw RecipeEditProposalError.missingIngredient
                }
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 160,
                    (rawAmount?.count ?? 0) <= 120
                else { throw RecipeEditProposalError.invalidOperation }
                let original = changed.ingredients[index]
                if let rawAmount {
                    let replacement = RecipeIngredient.from(
                        name: name, amountText: rawAmount,
                        category: original.category
                    )
                    // The original ingredient ID must survive links to Cooking steps.
                    changed.ingredients[index].name = replacement.name
                    changed.ingredients[index].amountText = replacement.amountText
                    changed.ingredients[index].quantity = replacement.quantity
                    changed.ingredients[index].unit = replacement.unit
                } else {
                    changed.ingredients[index].name = name
                }

            case let .editStep(id, rawInstruction):
                guard let index = changed.steps.firstIndex(where: { $0.id == id }) else {
                    throw RecipeEditProposalError.missingStep
                }
                let instruction = rawInstruction.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                guard !instruction.isEmpty, instruction.count <= 5_000 else {
                    throw RecipeEditProposalError.invalidOperation
                }
                changed.steps[index].instruction = instruction

            case let .setServings(value):
                guard (1...100).contains(value) else {
                    throw RecipeEditProposalError.invalidOperation
                }
                // Display amounts use the existing exact servings ratio, not model guesses.
                changed.servings = value

            case let .editSummary(rawSummary):
                let summary = rawSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard summary.count <= 2_000 else {
                    throw RecipeEditProposalError.invalidOperation
                }
                changed.summary = summary
            }
        }
        changed.updatedAt = date
        return changed
    }

    /// Creates a detached private variant; preview and original remain unchanged.
    public func privateVariant(
        of recipe: Recipe, at date: Date = .now, id: UUID = UUID()
    ) throws -> Recipe {
        var variant = try preview(on: recipe, at: date)
        variant.id = id
        variant.createdAt = date
        variant.isFavorite = false
        return variant
    }
}
