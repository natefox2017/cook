// Developer: gengyun
// Purpose: Validates user-reviewable AI recipe translations as an independent snapshot diff.

import CryptoKit
import Foundation

/// Translation targets are intentionally narrower than UI languages. Only these
/// four locales may be produced; any other identifier fails closed.
public enum RecipeTranslationTarget: String, Codable, CaseIterable, Hashable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"

    /// Defaults to the app's explicit language when it is translatable, otherwise English.
    public static func defaultTarget(localeIdentifier: String?) -> RecipeTranslationTarget {
        guard let localeIdentifier, let target = RecipeTranslationTarget(rawValue: localeIdentifier) else {
            return .english
        }
        return target
    }
}

/// One translated field bound to a stable ingredient or step id. The id preserves
/// the source-to-translation mapping even when the surrounding recipe changes.
public struct RecipeTranslationFieldChange: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let original: String
    public let translated: String

    public init(id: UUID, original: String, translated: String) {
        self.id = id
        self.original = original
        self.translated = translated
    }
}

public enum RecipeTranslationProposalError: Error, Equatable, Sendable {
    case staleRecipe
    case emptyProposal
    case unsupportedLocale
    case duplicatedField
    case missingField
    case sourceChanged
    case countChanged
    case orderChanged
    case invalidReplacement
    case numericValueChanged
    case oversizedProposal
}

/// Generated-marker record kept alongside a saved translation variant so the new
/// recipe can be traced back to its private source instead of the AI translation.
public struct RecipeTranslationProvenance: Codable, Equatable, Hashable, Sendable {
    public let originalRecipeID: UUID
    public let targetLocale: String
    public let sourceURL: String?
    public let sourceName: String?
    public let generatedAt: Date

    public init(
        originalRecipeID: UUID,
        targetLocale: String,
        sourceURL: String?,
        sourceName: String?,
        generatedAt: Date
    ) {
        self.originalRecipeID = originalRecipeID
        self.targetLocale = targetLocale
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.generatedAt = generatedAt
    }
}

public struct RecipeTranslationPreview: Equatable, Sendable {
    public let before: Recipe
    public let after: Recipe
    public let provenance: RecipeTranslationProvenance

    public var hasChanges: Bool { before != after }
}

/// A proposed translation has no side effects; the user must approve before saving.
/// It is a standalone diff and never extends the edit-patch `RecipeEditChange` enum.
public struct RecipeTranslationProposal: Codable, Equatable, Sendable {
    public let recipeID: UUID
    public let basedOnUpdate: Date
    public let targetLocale: String
    public let title: String
    public let summary: String
    public let ingredientNames: [RecipeTranslationFieldChange]
    /// Only vague amounts are translatable; precise numbers and structured units stay put.
    public let ingredientAmounts: [RecipeTranslationFieldChange]
    public let stepInstructions: [RecipeTranslationFieldChange]
    public let stepTitles: [RecipeTranslationFieldChange]
    /// Provenance is preserved verbatim so the translation is never mistaken for original text.
    public let sourceURL: String?
    public let sourceName: String?

    public init(
        recipeID: UUID,
        basedOnUpdate: Date,
        targetLocale: String,
        title: String = "",
        summary: String = "",
        ingredientNames: [RecipeTranslationFieldChange] = [],
        ingredientAmounts: [RecipeTranslationFieldChange] = [],
        stepInstructions: [RecipeTranslationFieldChange] = [],
        stepTitles: [RecipeTranslationFieldChange] = [],
        sourceURL: String? = nil,
        sourceName: String? = nil
    ) {
        self.recipeID = recipeID
        self.basedOnUpdate = basedOnUpdate
        self.targetLocale = targetLocale
        self.title = title
        self.summary = summary
        self.ingredientNames = ingredientNames
        self.ingredientAmounts = ingredientAmounts
        self.stepInstructions = stepInstructions
        self.stepTitles = stepTitles
        self.sourceURL = sourceURL
        self.sourceName = sourceName
    }

    /// Generated-marker record; the caller owns persisting it next to the variant.
    public func provenance(generatedAt: Date = .now) -> RecipeTranslationProvenance {
        RecipeTranslationProvenance(
            originalRecipeID: recipeID,
            targetLocale: targetLocale,
            sourceURL: sourceURL,
            sourceName: sourceName,
            generatedAt: generatedAt
        )
    }

    /// Deterministic variant id from (original recipe, target locale) so re-translating
    /// and saving the same recipe never creates a duplicate variant.
    public var variantRecipeID: UUID {
        Self.variantRecipeID(recipeID: recipeID, targetLocale: targetLocale)
    }

    public static func variantRecipeID(recipeID: UUID, targetLocale: String) -> UUID {
        let canonical = "recipe-translation:\(recipeID.uuidString.lowercased()):\(targetLocale)"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let bytes = digest.withUnsafeBytes { Array($0.prefix(16)) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public func preview(on original: Recipe) throws -> RecipeTranslationPreview {
        guard RecipeTranslationTarget(rawValue: targetLocale) != nil else {
            throw RecipeTranslationProposalError.unsupportedLocale
        }
        guard original.id == recipeID, original.updatedAt == basedOnUpdate else {
            throw RecipeTranslationProposalError.staleRecipe
        }
        guard !title.isEmpty || !summary.isEmpty
            || !ingredientNames.isEmpty || !ingredientAmounts.isEmpty
            || !stepInstructions.isEmpty || !stepTitles.isEmpty
        else {
            throw RecipeTranslationProposalError.emptyProposal
        }
        guard ingredientNames.count <= 200, ingredientAmounts.count <= 200,
            stepInstructions.count <= 200, stepTitles.count <= 200
        else {
            throw RecipeTranslationProposalError.oversizedProposal
        }

        var candidate = original

        if !title.isEmpty {
            guard Self.safeText(title, maximum: 240) else {
                throw RecipeTranslationProposalError.invalidReplacement
            }
            candidate.title = title
        }
        if !summary.isEmpty {
            guard Self.safeText(summary, maximum: 4_000) else {
                throw RecipeTranslationProposalError.invalidReplacement
            }
            candidate.summary = summary
        }

        // Ingredient names cover every ingredient in order; the stable id mapping
        // forbids reordering, dropping, or adding a field mid-translation.
        if !ingredientNames.isEmpty {
            guard ingredientNames.count == original.ingredients.count else {
                throw RecipeTranslationProposalError.countChanged
            }
            var seen = Set<UUID>()
            for (index, change) in ingredientNames.enumerated() {
                let ingredient = original.ingredients[index]
                guard seen.insert(change.id).inserted else {
                    throw RecipeTranslationProposalError.duplicatedField
                }
                guard change.id == ingredient.id else {
                    throw RecipeTranslationProposalError.orderChanged
                }
                guard change.original == ingredient.name else {
                    throw RecipeTranslationProposalError.sourceChanged
                }
                guard Self.safeText(change.translated, maximum: 240) else {
                    throw RecipeTranslationProposalError.invalidReplacement
                }
                candidate.ingredients[index].name = change.translated
            }
        }

        // Vague-amount translations keep structured quantity/unit untouched and must
        // never invent or drop a number (e.g. "to taste" must not become "1 tsp").
        for change in ingredientAmounts {
            guard let index = candidate.ingredients.firstIndex(where: { $0.id == change.id }) else {
                throw RecipeTranslationProposalError.missingField
            }
            guard candidate.ingredients[index].amountText == change.original else {
                throw RecipeTranslationProposalError.sourceChanged
            }
            guard Self.safeText(change.translated, maximum: 240) else {
                throw RecipeTranslationProposalError.invalidReplacement
            }
            guard Self.preservesNumericTokens(change.original, change.translated) else {
                throw RecipeTranslationProposalError.numericValueChanged
            }
            // quantity/unit and every other structured field stay exactly as the original.
            candidate.ingredients[index].amountText = change.translated
        }

        // Step instructions cover every step in order and preserve numbers so a
        // temperature or duration in prose is never silently altered.
        if !stepInstructions.isEmpty {
            guard stepInstructions.count == original.steps.count else {
                throw RecipeTranslationProposalError.countChanged
            }
            var seen = Set<UUID>()
            for (index, change) in stepInstructions.enumerated() {
                let step = original.steps[index]
                guard seen.insert(change.id).inserted else {
                    throw RecipeTranslationProposalError.duplicatedField
                }
                guard change.id == step.id else {
                    throw RecipeTranslationProposalError.orderChanged
                }
                guard change.original == step.instruction else {
                    throw RecipeTranslationProposalError.sourceChanged
                }
                guard Self.safeText(change.translated, maximum: 8_000) else {
                    throw RecipeTranslationProposalError.invalidReplacement
                }
                guard Self.preservesNumericTokens(change.original, change.translated) else {
                    throw RecipeTranslationProposalError.numericValueChanged
                }
                // timers and structured temperatures remain on the untouched step.
                candidate.steps[index].instruction = change.translated
            }
        }

        for change in stepTitles {
            guard let index = candidate.steps.firstIndex(where: { $0.id == change.id }) else {
                throw RecipeTranslationProposalError.missingField
            }
            guard candidate.steps[index].title == change.original else {
                throw RecipeTranslationProposalError.sourceChanged
            }
            guard Self.safeText(change.translated, maximum: 240) else {
                throw RecipeTranslationProposalError.invalidReplacement
            }
            candidate.steps[index].title = change.translated
        }

        guard candidate != original else {
            throw RecipeTranslationProposalError.emptyProposal
        }
        return RecipeTranslationPreview(before: original, after: candidate, provenance: provenance())
    }

    /// Call only after explicit user approval; the caller owns persistence and quota settlement.
    public func approvedVariant(from original: Recipe, at savedAt: Date = .now) throws -> Recipe {
        var variant = try preview(on: original).after
        variant.id = variantRecipeID
        variant.createdAt = savedAt
        variant.updatedAt = savedAt
        variant.isFavorite = false
        // A translation is a distinct private recipe, not another import-job result.
        variant.importRecord = nil
        // Persist the lineage on the variant itself so a saved recipe can recover its
        // private source, target locale, and explicit translation provenance.
        variant.translationProvenance = provenance(generatedAt: savedAt)
        return variant
    }

    private static func safeText(_ input: String, maximum: Int) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximum
            && !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static let numberRegex = try? NSRegularExpression(
        pattern: #"(\d+/\d+|\d+(?:\.\d+)?|\.\d+)"#,
        options: []
    )

    /// Numbers in translated prose must be a permutation of the source numbers.
    private static func numericTokens(_ text: String) -> [String] {
        guard let numberRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return numberRegex.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[tokenRange])
        }
    }

    private static func preservesNumericTokens(_ original: String, _ translated: String) -> Bool {
        numericTokens(original).sorted() == numericTokens(translated).sorted()
    }
}
