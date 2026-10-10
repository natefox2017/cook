// Developer: gengyun
// Purpose: Hide structurally invalid or unattributed nutrition claims without altering saved data.

import Foundation

public extension RecipeNutrition {
    /// This checks display integrity, not the truth of an external nutrition claim.
    /// Older optional metadata remains stored even when the card cannot show it.
    var hasDisplayablePerServingValues: Bool {
        let attribution = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard perServings == 1,
              !attribution.isEmpty,
              attribution.count <= 300,
              !attribution.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            return false
        }

        let values = [caloriesKcal, proteinGrams, carbohydratesGrams, fatGrams]
            .compactMap { $0 }
        return !values.isEmpty && values.allSatisfy { !$0.isNaN && $0 >= 0 }
    }
}
