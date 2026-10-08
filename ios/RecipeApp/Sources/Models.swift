// Developer: gengyun
// Purpose: Defines the lightweight data model used by the legacy RecipeApp prototype.

import Foundation

struct Ingredient: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: String
    var aisle: String = "Other"
}

struct RecipeStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var seconds: Int?
}

struct Recipe: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var sourceURL: String?
    var servings: Int
    var minutes: Int
    var isFavorite: Bool
    var needsReview: Bool
    var ingredients: [Ingredient]
    var steps: [RecipeStep]
}

struct GroceryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: String
    var aisle: String = "Other"
    var checked: Bool
    var recipeID: UUID?
}

struct MealPlanEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var meal: String
    var recipeID: UUID
    var servings: Int
}

struct PersistedState: Codable {
    var recipes: [Recipe]
    var groceries: [GroceryItem]
    var mealPlan: [MealPlanEntry] = []
}
