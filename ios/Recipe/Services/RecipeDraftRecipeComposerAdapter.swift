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
    var origin: String
}

/// DEV-428 draft-recipe composer. It applies the accepted terminal suggestions onto the
/// immutable session context (the same inputs as the backend's composeApprovedDraftFields)
/// and maps the resulting ready fields through the existing text import mapping, so vague
/// amounts, units and step text stay original instead of being guessed.
enum RecipeDraftRecipeComposerAdapter {
    /// Fills `RecipeDraftService`'s `Compose` port directly: the approved snapshot is the
    /// same shape the backend `composeApprovedDraftFields` consumes. `approve()` only ever
    /// reaches this after an accepted approval, so the selected paths are the accepted paths.
    static func compose(snapshot: RecipeDraftApprovedSnapshot) throws -> Recipe {
        guard case .proposal(_, let suggestions) = snapshot.result else {
            throw RecipeDraftComposerError.invalidApproval
        }
        guard !snapshot.selectedPaths.isEmpty else {
            throw RecipeDraftComposerError.invalidApproval
        }

        // Start from the immutable session context, then apply each accepted suggestion,
        // mirroring the backend's composeApprovedDraftFields validation order exactly.
        let context = snapshot.context
        let flags = context.reviewFields
        var fields: [String: EffectiveField] = context.fields.mapValues {
            EffectiveField(rawValue: $0.rawValue, userConfirmed: $0.userConfirmed, origin: $0.origin)
        }
        for path in snapshot.selectedPaths {
            let matches = suggestions.filter { $0.path == path }
            guard matches.count == 1, let suggestion = matches.first else {
                throw RecipeDraftComposerError.missingSuggestion(path: path)
            }
            let existing = context.fields[path]
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
            fields[path] = EffectiveField(
                rawValue: suggestion.rawValue, userConfirmed: true, origin: "AI_suggested")
        }

        // Recompute the remaining review flags exactly like the server approval RPC.
        let selected = Set(snapshot.selectedPaths)
        let remaining = context.reviewFields.filter { flag in
            if selected.contains(flag) { return false }
            guard Self.isGroup(flag) else { return true }
            let keys = fields.keys.filter { $0.hasPrefix("\(flag)[") }
            let exactFlags = context.reviewFields.filter { $0.hasPrefix("\(flag)[") }
            let resolved = keys.count > 0
                && keys.allSatisfy { fields[$0]?.userConfirmed == true }
                && exactFlags.allSatisfy { fields[$0]?.userConfirmed == true }
                && snapshot.selectedPaths.contains { $0.hasPrefix("\(flag)[") }
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

    /// Reuses RecipeDocumentParser.recipe(fromText:title:) for the step text (timers/linking stay
    /// parsed), then maps each server-approved name/amount back onto the matching ingredient so a
    /// reviewed name-only or amount-only value is never dropped in favor of the raw line.
    private static func makeRecipe(fields: [String: EffectiveField]) -> Recipe {
        let title = Self.nonempty(fields["title"]?.rawValue) ?? "Imported recipe"
        // Per-ingredient lines: prefer raw_text, then amount, then name, so a row that only
        // reviewed name/amount still lands in the recipe instead of being dropped wholesale.
        let rows = Self.ingredientRows(fields: fields)
        let steps = Self.indexed(fields, pattern: #"^steps\[(\d+)\]\.instruction$"#)

        var text = title
        if !rows.isEmpty {
            text += "\n\nIngredients\n" + rows.map(\.line).joined(separator: "\n")
        }
        if !steps.isEmpty {
            text += "\n\nInstructions\n" + steps.joined(separator: "\n")
        }
        var recipe = RecipeDocumentParser.recipe(fromText: text, title: title)
        recipe.servings = nil
        Self.applyReviewedIngredientFields(fields: fields, rows: rows, recipe: &recipe)
        return recipe
    }

    /// Builds the ordered ingredient lines used as parser input. Each index is represented once:
    /// the full raw_text when present, otherwise the amount, otherwise the name.
    private static func ingredientRows(
        fields: [String: EffectiveField]
    ) -> [(index: Int, line: String)] {
        let indices = Set(fields.keys.compactMap(Self.ingredientIndex)).sorted()
        return indices.compactMap { index in
            let rawText = Self.nonempty(fields["ingredients[\(index)].raw_text"]?.rawValue)
            let amount = Self.nonempty(fields["ingredients[\(index)].amount"]?.rawValue)
            let name = Self.nonempty(fields["ingredients[\(index)].name"]?.rawValue)
            let line = rawText ?? amount ?? name
            return line.map { (index, $0) }
        }
    }

    /// Maps a server-approved (AI_suggested) name/amount back onto the corresponding parsed
    /// ingredient so the local write matches the finalized server fields. Extracted (import)
    /// amount fields are a verbatim full line, never a fabricated amount, so they are skipped.
    private static func applyReviewedIngredientFields(
        fields: [String: EffectiveField],
        rows: [(index: Int, line: String)],
        recipe: inout Recipe
    ) {
        for (position, row) in rows.enumerated() {
            guard position < recipe.ingredients.count else { continue }
            var name = recipe.ingredients[position].name
            var amount = recipe.ingredients[position].amountText
            if let field = fields["ingredients[\(row.index)].name"],
                field.origin == "AI_suggested",
                let value = Self.nonempty(field.rawValue) {
                name = value
            }
            if let field = fields["ingredients[\(row.index)].amount"],
                field.origin == "AI_suggested",
                let value = Self.nonempty(field.rawValue) {
                amount = value
            }
            guard name != recipe.ingredients[position].name
                || amount != recipe.ingredients[position].amountText
            else { continue }
            let reviewed = RecipeIngredient.from(name: name, amountText: amount)
            recipe.ingredients[position].name = reviewed.name
            recipe.ingredients[position].amountText = reviewed.amountText
            recipe.ingredients[position].quantity = reviewed.quantity
            recipe.ingredients[position].unit = reviewed.unit
        }
    }

    /// Extracts the integer index from an `ingredients[i].<field>` path.
    private static func ingredientIndex(_ path: String) -> Int? {
        guard path.hasPrefix("ingredients["),
            let close = path.firstIndex(of: "]")
        else { return nil }
        let start = path.index(path.startIndex, offsetBy: "ingredients[".count)
        return Int(path[start..<close])
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
