// Developer: gengyun
// Purpose: Provides the legacy RecipeApp recipe editor.

import SwiftUI

struct RecipeEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State var recipe: Recipe
    @State private var ingredientDraft = ""
    @State private var stepDraft = ""

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Title", text: $recipe.title)

                Stepper(
                    "Servings: (recipe.servings)",
                    value: $recipe.servings,
                    in: 1...24
                )

                Stepper(
                    "Minutes: (recipe.minutes)",
                    value: $recipe.minutes,
                    in: 0...600,
                    step: 5
                )
            }

            Section("Ingredients") {
                ForEach(recipe.ingredients) { ingredient in
                    Text("(ingredient.name)  (ingredient.amount)")
                }

                TextField(
                    "e.g. Tomatoes — 3",
                    text: $ingredientDraft
                )

                Button("Add ingredient") {
                    addIngredient()
                }
            }

            Section("Steps") {
                ForEach(recipe.steps) { step in
                    Text(step.text)
                }

                TextField(
                    "Add a step",
                    text: $stepDraft,
                    axis: .vertical
                )

                Button("Add step") {
                    addStep()
                }
            }
        }
        .navigationTitle("Edit Recipe")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(
                    recipe.title
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
    }

    private func addIngredient() {
        let parts = ingredientDraft
            .split(separator: "—", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard !parts.isEmpty, !parts[0].isEmpty else { return }

        recipe.ingredients.append(
            Ingredient(
                name: parts[0],
                amount: parts.count > 1 ? parts[1] : ""
            )
        )
        ingredientDraft = ""
    }

    private func addStep() {
        let value = stepDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else { return }

        recipe.steps.append(RecipeStep(text: value))
        stepDraft = ""
    }

    private func save() {
        let pendingStep = stepDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !pendingStep.isEmpty {
            recipe.steps.append(RecipeStep(text: pendingStep))
        }

        recipe.needsReview =
            recipe.ingredients.isEmpty || recipe.steps.isEmpty

        store.upsert(recipe)
        dismiss()
    }
}
