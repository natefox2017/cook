// Developer: gengyun
// Purpose: Tests ingredient amount display, exact scaling, and preservation of ambiguous source values.

import Foundation
import Testing

@testable import RecipeCore

@Test(arguments: [
    "to taste", "a little", "1-2 tbsp", "1 – 2 tbsp",
    "1 to 2 cups", "about 1 cup", "1 cup (optional)",
    "1/0 cup", "1/3 cup", "2/3 cup", "1/7 cup", "2 1/3 cups", "1,5 cups",
    "99999999999999999999999999999999999999 1/2 cups",
    "123456789012345678901234567890123456789 g", "",
])
func ambiguousAmountsStayExactlyAsWritten(text: String) {
    let ingredient = RecipeIngredient.from(name: "Ingredient", amountText: text)
    #expect(ingredient.quantity == nil)
    #expect(ingredient.amountText == text)
    #expect(ingredient.displayAmount(multiplier: 3) == text)
}

@Test
func explicitFractionsDecimalsAndUnitsScaleWithoutChangingSource() {
    for text in ["1 1/2 cups", "1½ cups", "1.5 cups"] {
        let ingredient = RecipeIngredient.from(name: "Flour", amountText: text)
        #expect(ingredient.quantity == Decimal(string: "1.5"))
        #expect(ingredient.unit == "cups")
        #expect(ingredient.displayAmount(multiplier: 2) == "3 cups")
        #expect(ingredient.amountText == text)
    }
    let half = RecipeIngredient.from(name: "Oil", amountText: "½ tbsp")
    #expect(half.quantity == Decimal(string: "0.5"))
    #expect(half.displayAmount(multiplier: 3) == "1.5 tbsp")
    #expect(RecipeIngredient.from(name: "Oil", amountText: ".5 tbsp").quantity == half.quantity)
    #expect(RecipeIngredient.from(name: "Oil", amountText: "3/6 tbsp").quantity == half.quantity)
    #expect(RecipeIngredient.from(name: "Oil", amountText: "6/3 tbsp").quantity == 2)
    #expect(RecipeIngredient.from(name: "Oil", amountText: "0/3 tbsp").quantity == 0)
    let zero = RecipeIngredient.from(name: "Salt", amountText: "0 g")
    #expect(zero.quantity == 0)
    #expect(zero.displayAmount(multiplier: 2) == "0 g")
}

@Test
func incompleteRecipesAreReviewableAndTimeCannotOverflow() {
    var recipe = Recipe(title: "")
    #expect(recipe.needsReview)
    #expect(recipe.totalMinutes == nil)
    recipe.title = "A saved source"
    recipe.ingredients = [.from(name: "Salt", amountText: "to taste")]
    recipe.steps = [RecipeStep(instruction: "Season as desired.")]
    #expect(!recipe.needsReview)
    recipe.prepMinutes = 10
    #expect(recipe.totalMinutes == 10)
    recipe.cookMinutes = 20
    #expect(recipe.totalMinutes == 30)
    recipe.prepMinutes = .max
    #expect(recipe.totalMinutes == nil)
}

@Test
func portionPreviewUsesExactRatioInsteadOfARoundedMultiplier() {
    let threeCups = RecipeIngredient.from(name: "Flour", amountText: "3 cups")
    #expect(threeCups.displayAmount(servings: 1, originalServings: 3) == "1 cups")
    let oneCup = RecipeIngredient.from(name: "Flour", amountText: "1 cup")
    #expect(oneCup.displayAmount(servings: 1, originalServings: 3) == "1 cup × 1/3")
    #expect(oneCup.amountText == "1 cup")
    let twoCups = RecipeIngredient.from(name: "Flour", amountText: "2 cups")
    #expect(twoCups.displayAmount(servings: 1, originalServings: 3) == "2 cups × 1/3")
    let enormous = RecipeIngredient(
        name: "Flour", amountText: "source amount",
        quantity: .greatestFiniteMagnitude, unit: "g")
    #expect(
        enormous.displayAmount(servings: 2, originalServings: 1)
            == "\(enormous.displayAmount()) × 2/1")
}

@Test
func portionPreviewKeepsUnspecifiedAndQualitativeAmounts() {
    let unknown = RecipeIngredient.from(name: "Salt", amountText: "适量")
    #expect(unknown.displayAmount(servings: 1, originalServings: 3) == "适量")
    #expect(unknown.displayAmount(servings: nil, originalServings: nil) == "适量")
    let numeric = RecipeIngredient.from(name: "Flour", amountText: "2 cups")
    #expect(numeric.displayAmount(servings: 4, originalServings: nil) == "2 cups")
}
