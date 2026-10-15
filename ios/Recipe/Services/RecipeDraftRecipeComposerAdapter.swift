// Developer: gengyun
// Purpose: Compose an approved draft turn into a saveable Recipe, mirroring the backend
//          composeApprovedDraftFields so the local write matches the finalized server payload.

import Foundation
import RecipeCore

/// Fail-closed outcomes for an approval that cannot become a saveable recipe.
enum RecipeDraftComposerError: Error, Equatable {
    case invalidApproval
    case missingSuggestion(path: String)
    case alreadyConfirmed(path: String)
    case notReviewRelevant(path: String)
    case unresolvedFields([String])
}

/// A confirmed draft field projected for composition; mirrors the backend's raw field shape.
private struct EffectiveField {
    var rawValue: String?
    var userConfirmed: Bool
}

/// DEV-428 draft-recipe composer. It applies the accepted terminal suggestions onto the
/// immutable session context (the same inputs as the backend's composeApprovedDraftFields)
/// and maps the resulting ready fields through the existing text import mapping, so vague
/// amounts, units and step text stay original instead of being guessed.
enum RecipeDraftRecipeComposerAdapter {
    static func compose(
        session: RecipeDraftSession,
        suggestions: [RecipeDraftSuggestion],
        receipt: RecipeDraftApprovalReceipt,
        ownerID: UUID
    ) throws -> Recipe {
        // The owner is already verified by the draft API; the UUID is retained only to
        // match the Core handoff seam, and the writer applies the server recipe ID later.
        _ = ownerID

        guard receipt.action == "accept", !receipt.selectedPaths.isEmpty else {
            throw RecipeDraftComposerError.invalidApproval
        }

        // Start from the immutable session context, then apply each accepted suggestion,
        // mirroring the backend's composeApprovedDraftFields validation order exactly.
        let flags = session.context.reviewFields
        var fields: [String: EffectiveField] = session.context.fields.mapValues {
            EffectiveField(rawValue: $0.rawValue, userConfirmed: $0.userConfirmed)
        }
        for path in receipt.selectedPaths {
            let matches = suggestions.filter { $0.path == path }
            guard matches.count == 1, let suggestion = matches.first else {
                throw RecipeDraftComposerError.missingSuggestion(path: path)
            }
            let existing = session.context.fields[path]
            guard existing?.userConfirmed != true else {
                throw RecipeDraftComposerError.alreadyConfirmed(path: path)
            }
            // A brand-new field (absent from the context) must be an exact review flag.
            guard existing != nil || flags.contains(path) else {
                throw RecipeDraftComposerError.notReviewRelevant(path: path)
            }
            let reviewRelevant = flags.contains(path)
                || flags.contains { Self.isGroup($0) && path.hasPrefix("\($0)[") }
            guard reviewRelevant else {
                throw RecipeDraftComposerError.notReviewRelevant(path: path)
            }
            fields[path] = EffectiveField(rawValue: suggestion.rawValue, userConfirmed: true)
        }

        // Recompute the remaining review flags exactly like the server approval RPC.
        let selected = Set(receipt.selectedPaths)
        let remaining = session.context.reviewFields.filter { flag in
            if selected.contains(flag) { return false }
            guard Self.isGroup(flag) else { return true }
            let keys = fields.keys.filter { $0.hasPrefix("\(flag)[") }
            let exactFlags = session.context.reviewFields.filter { $0.hasPrefix("\(flag)[") }
            let resolved = keys.count > 0
                && keys.allSatisfy { fields[$0]?.userConfirmed == true }
                && exactFlags.allSatisfy { fields[$0]?.userConfirmed == true }
                && receipt.selectedPaths.contains { $0.hasPrefix("\(flag)[") }
            return !resolved
        }
        guard remaining.isEmpty else {
            throw RecipeDraftComposerError.unresolvedFields(remaining)
        }

        return Self.makeRecipe(fields: fields)
    }

    private static func isGroup(_ flag: String) -> Bool {
        flag == "ingredients" || flag == "steps"
    }

    /// Reuses RecipeDocumentParser.recipe(fromText:title:) so ingredient/step text keeps the
    /// original evidence and only explicit amounts are parsed; a vague serving count is never
    /// turned into an exact number.
    private static func makeRecipe(fields: [String: EffectiveField]) -> Recipe {
        let title = Self.nonempty(fields["title"]?.rawValue) ?? "Imported recipe"
        let rawIngredients = Self.indexed(fields, pattern: #"^ingredients\[(\d+)\]\.raw_text$"#)
        let ingredients = rawIngredients.isEmpty
            ? Self.indexed(fields, pattern: #"^ingredients\[(\d+)\]\.amount$"#)
            : rawIngredients
        let steps = Self.indexed(fields, pattern: #"^steps\[(\d+)\]\.instruction$"#)

        var text = title
        if !ingredients.isEmpty {
            text += "\n\nIngredients\n" + ingredients.joined(separator: "\n")
        }
        if !steps.isEmpty {
            text += "\n\nInstructions\n" + steps.joined(separator: "\n")
        }
        var recipe = RecipeDocumentParser.recipe(fromText: text, title: title)
        recipe.servings = nil
        return recipe
    }

    private static func indexed(
        _ fields: [String: EffectiveField],
        pattern: String
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return fields.compactMap { entry -> (Int, String)? in
            let key = entry.key
            let range = NSRange(key.startIndex..., in: key)
            guard let match = expression.firstMatch(in: key, range: range),
                let indexRange = Range(match.range(at: 1), in: key),
                let index = Int(key[indexRange]),
                let value = Self.nonempty(entry.value.rawValue)
            else {
                return nil
            }
            return (index, value)
        }
        .sorted { $0.0 < $1.0 }
        .map { $0.1 }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
