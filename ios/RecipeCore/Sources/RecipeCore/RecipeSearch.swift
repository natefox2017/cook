// Developer: gengyun
// Purpose: Matches saved recipes against search terms without building large temporary strings.

import Foundation

/// Shared search logic for the recipe library and collection detail views.
/// The library includes cooking steps; collections retain their existing
/// title, summary, notes, and ingredient search behavior.
public enum RecipeSearch {
    public static func matches(
        _ recipe: Recipe,
        query rawQuery: String,
        includeSteps: Bool = true
    ) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        if recipe.title.localizedStandardContains(query)
            || recipe.summary.localizedStandardContains(query)
            || recipe.notes.localizedStandardContains(query) {
            return true
        }

        if recipe.ingredients.contains(where: { $0.name.localizedStandardContains(query) }) {
            return true
        }

        guard includeSteps else { return false }
        return recipe.steps.contains { step in
            // Preserve searches spanning a step title and its instruction.
            "\(step.title) \(step.instruction)".localizedStandardContains(query)
        }
    }
}
