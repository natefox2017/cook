// Developer: gengyun
// Purpose: Keep optional ingredient sections and step media linked to existing recipe IDs.

import Foundation

extension Recipe {
    /// Remove an ingredient and every reference to it without renumbering other IDs.
    public mutating func removeIngredient(id: UUID) {
        ingredients.removeAll { $0.id == id }
        pruneDanglingReferences()
    }

    /// Deleting a step never deletes unrelated private media references.
    public mutating func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
        pruneDanglingReferences()
    }

    /// Call after the editor drops empty rows so optional metadata cannot retain dead links.
    public mutating func pruneDanglingReferences() {
        let validIngredientIDs = Set(ingredients.map(\.id))
        for index in steps.indices {
            steps[index].linkedIngredientIDs.removeAll { ingredientID in
                !validIngredientIDs.contains(ingredientID)
            }
        }

        if let sections = ingredientSections {
            ingredientSections = sections.compactMap { section in
                var updated = section
                updated.ingredientIDs.removeAll { !validIngredientIDs.contains($0) }
                return updated.ingredientIDs.isEmpty ? nil : updated
            }
        }

        if let images = stepImages {
            let validStepIDs = Set(steps.map(\.id))
            stepImages = images.filter { validStepIDs.contains($0.stepID) }
        }
    }
}
