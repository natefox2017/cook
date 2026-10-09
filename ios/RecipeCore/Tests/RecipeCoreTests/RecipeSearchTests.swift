// Developer: gengyun
// Purpose: Verifies short-circuit recipe searches and collection-specific search scope.

import Foundation
import Testing

@testable import RecipeCore

@Test
func recipeSearchMatchesVisibleRecipeFields() {
    let recipe = Recipe(
        title: "Tomato Soup",
        summary: "Weeknight comfort food",
        ingredients: [RecipeIngredient(name: "Fresh basil")],
        steps: [RecipeStep(title: "Simmer", instruction: "Warm the stock")],
        sourceText: "Private source metadata",
        notes: "Family favorite"
    )

    #expect(RecipeSearch.matches(recipe, query: " tomato "))
    #expect(RecipeSearch.matches(recipe, query: "WEEKNIGHT"))
    #expect(RecipeSearch.matches(recipe, query: "BASIL"))
    #expect(RecipeSearch.matches(recipe, query: "family"))
    #expect(RecipeSearch.matches(recipe, query: "Simmer Warm"))
    #expect(RecipeSearch.matches(recipe, query: "stock"))
    #expect(RecipeSearch.matches(recipe, query: "   "))
}

@Test
func collectionSearchExcludesStepsAndUnsearchedSourceMetadata() {
    let recipe = Recipe(
        title: "Soup",
        summary: "Simple",
        ingredients: [RecipeIngredient(name: "Carrot")],
        steps: [RecipeStep(title: "Simmer", instruction: "Add stock")],
        sourceText: "Source tracking code"
    )

    #expect(RecipeSearch.matches(recipe, query: "carrot", includeSteps: false))
    #expect(!RecipeSearch.matches(recipe, query: "simmer", includeSteps: false))
    #expect(!RecipeSearch.matches(recipe, query: "stock", includeSteps: false))
    #expect(!RecipeSearch.matches(recipe, query: "tracking code"))
    #expect(RecipeSearch.matches(recipe, query: "Simmer", includeSteps: true))
}
