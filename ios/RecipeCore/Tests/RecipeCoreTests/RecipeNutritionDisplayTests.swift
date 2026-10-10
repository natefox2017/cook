// Developer: gengyun
// Purpose: Verify optional nutrition never displays absent, invalid or implausibly sourced numbers.

import Foundation
import Testing
@testable import RecipeCore

@Test
func validAttributedNutritionDisplaysOnlyForOneServingBasis() {
    let label = RecipeNutrition(
        caloriesKcal: 250, proteinGrams: 12,
        perServings: 1, source: "Product nutrition label"
    )
    #expect(label.hasDisplayablePerServingValues)

    let twoServings = RecipeNutrition(
        caloriesKcal: 250, perServings: 2, source: "Product nutrition label"
    )
    #expect(!twoServings.hasDisplayablePerServingValues)
}

@Test
func missingNutritionFactsOrAttributionAreNotRendered() {
    let missingFacts = RecipeNutrition(perServings: 1, source: "User note")
    #expect(!missingFacts.hasDisplayablePerServingValues)

    let missingSource = RecipeNutrition(
        proteinGrams: 5, perServings: 1, source: "   "
    )
    #expect(!missingSource.hasDisplayablePerServingValues)

    let unknownBasis = RecipeNutrition(
        proteinGrams: 5, source: "Product nutrition label"
    )
    #expect(!unknownBasis.hasDisplayablePerServingValues)
}

@Test
func negativeAndNaNNutritionCannotBecomeDisplayedFacts() {
    let negative = RecipeNutrition(
        caloriesKcal: -5, proteinGrams: 3,
        perServings: 1, source: "Product nutrition label"
    )
    #expect(!negative.hasDisplayablePerServingValues)

    let notANumber = RecipeNutrition(
        proteinGrams: Decimal.nan,
        perServings: 1, source: "Product nutrition label"
    )
    #expect(!notANumber.hasDisplayablePerServingValues)
}

@Test
func zeroIsValidWhenExplicitlyAttributedButControlTextIsNot() {
    let zero = RecipeNutrition(
        caloriesKcal: 0, perServings: 1, source: "Product nutrition label"
    )
    #expect(zero.hasDisplayablePerServingValues)

    let invalidAttribution = RecipeNutrition(
        fatGrams: 0, perServings: 1, source: "Label\nInjected text"
    )
    #expect(!invalidAttribution.hasDisplayablePerServingValues)

    let overlyLong = RecipeNutrition(
        fatGrams: 0, perServings: 1, source: String(repeating: "x", count: 301)
    )
    #expect(!overlyLong.hasDisplayablePerServingValues)
}
