// Developer: gengyun
// Purpose: Validates user-reviewable AI recipe edit proposals before changing recipes.

import Foundation

public enum RecipeEditChange: Codable, Equatable, Hashable, Sendable {
    case ingredientName(id: UUID, original: String, proposed: String)
    case ingredientAmount(id: UUID, original: String, proposed: String)
    case stepInstruction(id: UUID, original: String, proposed: String)

    fileprivate var pathKey: String {
        switch self {
        case .ingredientName(let id, _, _): "ingredient:\(id):name"
        case .ingredientAmount(let id, _, _): "ingredient:\(id):amount"
        case .stepInstruction(let id, _, _): "step:\(id):instruction"
        }
    }
}

public enum RecipeEditProposalError: Error, Equatable, Sendable {
    case staleRecipe
    case emptyProposal
    case duplicatedPath
    case missingField
    case sourceChanged
    case invalidReplacement
}

public struct RecipeEditPreview: Equatable, Sendable {
    public let before: Recipe
    public let after: Recipe
    public let reasons: [String]
    public let warnings: [String]

    public var hasChanges: Bool { before != after }
}

/// A proposed edit has no side effects; the user must approve before store.upsert.
public struct RecipeEditProposal: Codable, Equatable, Sendable {
    public let recipeID: UUID
    public let basedOnUpdate: Date
    public let changes: [RecipeEditChange]
    public let reasons: [String]
    public let warnings: [String]

    public init(
        recipeID: UUID, basedOnUpdate: Date, changes: [RecipeEditChange],
        reasons: [String] = [], warnings: [String] = []
    ) {
        self.recipeID = recipeID
        self.basedOnUpdate = basedOnUpdate
        self.changes = changes
        self.reasons = reasons
        self.warnings = warnings
    }

    public func preview(on original: Recipe) throws -> RecipeEditPreview {
        guard original.id == recipeID, original.updatedAt == basedOnUpdate else {
            throw RecipeEditProposalError.staleRecipe
        }
        guard !changes.isEmpty else { throw RecipeEditProposalError.emptyProposal }
        var visited = Set<String>()
        var candidate = original
        for change in changes {
            guard visited.insert(change.pathKey).inserted else {
                throw RecipeEditProposalError.duplicatedPath
            }
            switch change {
            case .ingredientName(let id, let old, let next):
                guard let index = candidate.ingredients.firstIndex(where: { $0.id == id }) else {
                    throw RecipeEditProposalError.missingField
                }
                guard candidate.ingredients[index].name == old else {
                    throw RecipeEditProposalError.sourceChanged
                }
                guard Self.safeText(next, maximum: 240) else {
                    throw RecipeEditProposalError.invalidReplacement
                }
                candidate.ingredients[index].name = next
            case .ingredientAmount(let id, let old, let next):
                guard let index = candidate.ingredients.firstIndex(where: { $0.id == id }) else {
                    throw RecipeEditProposalError.missingField
                }
                guard candidate.ingredients[index].amountText == old else {
                    throw RecipeEditProposalError.sourceChanged
                }
                guard Self.safeText(next, maximum: 240) else {
                    throw RecipeEditProposalError.invalidReplacement
                }
                // Never infer grams/density from a natural-language amount:
                // the structured quantity is reset until safely parsed/confirmed.
                let originalCategory = candidate.ingredients[index].category
                candidate.ingredients[index] = RecipeIngredient.from(
                    name: candidate.ingredients[index].name,
                    amountText: next, category: originalCategory
                )
                candidate.ingredients[index].id = id
            case .stepInstruction(let id, let old, let next):
                guard let index = candidate.steps.firstIndex(where: { $0.id == id }) else {
                    throw RecipeEditProposalError.missingField
                }
                guard candidate.steps[index].instruction == old else {
                    throw RecipeEditProposalError.sourceChanged
                }
                guard Self.safeText(next, maximum: 8_000) else {
                    throw RecipeEditProposalError.invalidReplacement
                }
                candidate.steps[index].instruction = next
                // Timers and structured temperatures are intentionally unchanged:
                // the user must separately review any proposed cooking changes.
            }
        }
        guard candidate != original else {
            throw RecipeEditProposalError.emptyProposal
        }
        return RecipeEditPreview(
            before: original, after: candidate, reasons: reasons, warnings: warnings)
    }

    /// Call only after explicit user approval; the caller owns persistence and undo.
    public func approvedRecipe(
        from current: Recipe, at savedAt: Date = .now, asVariant: Bool = false
    ) throws -> Recipe {
        var recipe = try preview(on: current).after
        recipe.updatedAt = savedAt
        if asVariant {
            recipe.id = UUID()
            recipe.createdAt = savedAt
        }
        return recipe
    }

    private static func safeText(_ input: String, maximum: Int) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximum
            && !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
