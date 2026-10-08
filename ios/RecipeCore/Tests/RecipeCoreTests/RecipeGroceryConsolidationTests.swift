// Developer: gengyun
// Purpose: Guards grocery consolidation behavior after switching to indexed lookups.

import Foundation
import Testing
@testable import RecipeCore

@Test @MainActor
func repeatedIngredientsCombineWithTheFirstEligibleRow() throws {
    let flourA = RecipeIngredient.from(name: "  Flour", amountText: "100 g")
    let flourB = RecipeIngredient.from(name: "flour  ", amountText: "50 g")
    let recipe = Recipe(title: "Bread", ingredients: [flourA, flourB])
    let store = RecipeStore()
    try store.upsert(recipe)

    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [flourA.id, flourB.id]
    )

    #expect(store.groceries.count == 1)
    #expect(store.groceries.first?.quantity == 150)
    #expect(store.groceries.first?.recipeIDs == [recipe.id])
}

@Test @MainActor
func checkedRowsStayIntactWhenAnEligibleUncheckedRowExists() throws {
    let recipeIngredient = RecipeIngredient.from(name: "FLOUR", amountText: "100 g")
    let recipe = Recipe(title: "Cake", ingredients: [recipeIngredient])
    let store = RecipeStore()
    try store.upsert(recipe)
    let bought = GroceryItem(
        name: "Flour", amountText: "10 g", quantity: 10,
        unit: "g", isChecked: true
    )
    let available = GroceryItem(
        name: " Flour ", amountText: "5 g", quantity: 5, unit: "g"
    )
    try store.upsertGrocery(bought)
    try store.upsertGrocery(available)

    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [recipeIngredient.id]
    )

    #expect(store.groceries.count == 2)
    #expect(store.groceries.first(where: { $0.id == bought.id })?.quantity == 10)
    #expect(store.groceries.first(where: { $0.id == available.id })?.quantity == 105)
}

@Test @MainActor
func disabledConsolidationAndCaseSensitiveUnitsRemainUnchanged() throws {
    let smallUnit = RecipeIngredient.from(name: "Salt", amountText: "1 t")
    let largeUnit = RecipeIngredient.from(name: "salt", amountText: "2 T")
    let recipe = Recipe(title: "Sauce", ingredients: [smallUnit, largeUnit])
    let store = RecipeStore()
    try store.upsert(recipe)

    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [smallUnit.id, largeUnit.id]
    )
    #expect(store.groceries.count == 2)

    try store.addToGroceries(
        recipeID: recipe.id,
        servings: nil,
        ingredientIDs: [smallUnit.id, largeUnit.id],
        consolidateCompatibleIngredients: false
    )
    #expect(store.groceries.count == 4)
}
