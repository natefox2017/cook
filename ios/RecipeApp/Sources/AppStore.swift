// Developer: gengyun
// Purpose: Stores and persists data for the legacy RecipeApp prototype.

import Foundation
import Observation

@Observable
final class AppStore {
    private(set) var recipes: [Recipe] = []
    private(set) var groceries: [GroceryItem] = []
    private(set) var mealPlan: [MealPlanEntry] = []

    var lastError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.fileURL = fileURL
            ?? base.appendingPathComponent("recipe-state.json")

        load()

        if recipes.isEmpty {
            recipes = Self.samples
        }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else {
            return
        }

        recipes[index].isFavorite.toggle()
        save()
    }

    func upsert(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }

        save()
    }

    func importURL(_ rawValue: String) -> Recipe? {
        let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let url = URL(string: text),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            lastError = "Enter a valid http or https link."
            return nil
        }

        if let existing = recipes.first(where: {
            $0.sourceURL == url.absoluteString
        }) {
            return existing
        }

        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web"
        let recipe = Recipe(
            title: "Imported from \(host)",
            sourceURL: url.absoluteString,
            servings: 2,
            minutes: 0,
            isFavorite: false,
            needsReview: true,
            ingredients: [],
            steps: []
        )

        upsert(recipe)
        return recipe
    }

    func addGroceries(from recipe: Recipe, servings: Int) {
        let factor = Double(servings) / Double(max(recipe.servings, 1))

        for ingredient in recipe.ingredients {
            let amount = factor == 1
                ? ingredient.amount
                : ingredient.amount + " × " + String(format: "%.1f", factor)

            let alreadyExists = groceries.contains {
                $0.name.caseInsensitiveCompare(ingredient.name) == .orderedSame
                    && $0.recipeID == recipe.id
            }

            guard !alreadyExists else { continue }

            groceries.append(
                GroceryItem(
                    name: ingredient.name,
                    amount: amount,
                    aisle: ingredient.aisle,
                    checked: false,
                    recipeID: recipe.id
                )
            )
        }

        save()
    }

    func addManualGrocery(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        groceries.append(
            GroceryItem(
                name: value,
                amount: "",
                checked: false,
                recipeID: nil
            )
        )
        save()
    }

    func plan(
        recipeID: UUID,
        date: Date,
        meal: String,
        servings: Int
    ) {
        mealPlan.removeAll {
            $0.date.sameDay(as: date) && $0.meal == meal
        }

        mealPlan.append(
            MealPlanEntry(
                date: date,
                meal: meal,
                recipeID: recipeID,
                servings: servings
            )
        )
        save()
    }

    func unplan(_ id: UUID) {
        mealPlan.removeAll { $0.id == id }
        save()
    }

    func addPlannedGroceries() {
        for entry in mealPlan {
            guard let recipe = recipes.first(where: {
                $0.id == entry.recipeID
            }) else {
                continue
            }

            addGroceries(from: recipe, servings: entry.servings)
        }
    }

    func toggleGrocery(_ id: UUID) {
        guard let index = groceries.firstIndex(where: { $0.id == id }) else {
            return
        }

        groceries[index].checked.toggle()
        save()
    }

    func clearChecked() {
        groceries.removeAll(where: \.checked)
        save()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            return
        }

        recipes = state.recipes
        groceries = state.groceries
        mealPlan = state.mealPlan
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let state = PersistedState(
                recipes: recipes,
                groceries: groceries,
                mealPlan: mealPlan
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Changes could not be saved."
        }
    }

    static let samples: [Recipe] = [
        Recipe(
            title: "Tomato Basil Pasta",
            sourceURL: nil,
            servings: 2,
            minutes: 25,
            isFavorite: true,
            needsReview: false,
            ingredients: [
                Ingredient(name: "Spaghetti", amount: "200 g"),
                Ingredient(name: "Tomatoes", amount: "3"),
                Ingredient(name: "Basil", amount: "a handful")
            ],
            steps: [
                RecipeStep(
                    text: "Boil the pasta until al dente.",
                    seconds: 480
                ),
                RecipeStep(
                    text: "Cook tomatoes until softened.",
                    seconds: 300
                ),
                RecipeStep(
                    text: "Toss with basil and serve.",
                    seconds: nil
                )
            ]
        ),
        Recipe(
            title: "Lemon Roast Chicken",
            sourceURL: nil,
            servings: 4,
            minutes: 55,
            isFavorite: false,
            needsReview: false,
            ingredients: [
                Ingredient(name: "Chicken thighs", amount: "4"),
                Ingredient(name: "Lemon", amount: "1")
            ],
            steps: [
                RecipeStep(text: "Season the chicken.", seconds: nil),
                RecipeStep(
                    text: "Roast until browned and cooked through.",
                    seconds: 2_100
                )
            ]
        )
    ]
}

extension Date {
    func sameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}
