// Developer: gengyun
// Purpose: Tests safe ingredient amount parsing and scaling.

import Foundation
import Testing

@testable import RecipeCore

@Test(arguments: ["适量", "少许", "未知", "", "1-2 汤匙"])
func qualitativeSourceIsNeverInvented(text: String) throws {
    let amount = try IngredientAmount(originalText: text)
    #expect(try amount.scaled(by: 3) == amount)
    #expect(amount.value == nil)
}

@Test func scalingPreservesEvidenceAndUnit() throws {
    let amount = try IngredientAmount(
        originalText: "半汤匙", value: Decimal(string: "0.5")!, unit: "汤匙")
    let scaled = try amount.scaled(by: 3)
    #expect(scaled.value == Decimal(string: "1.5"))
    #expect(scaled.originalText == "半汤匙")
    #expect(scaled.unit == "汤匙")
    #expect(amount.value == Decimal(string: "0.5"))
}

@Test(arguments: [Decimal.zero, Decimal(-1), Decimal.nan])
func invalidFactorsAreRejected(factor: Decimal) throws {
    let amount = try IngredientAmount(originalText: "适量")
    #expect(throws: IngredientAmount.ValidationError.invalidScale) { try amount.scaled(by: factor) }
}

@Test(arguments: [Decimal(-1), Decimal.nan])
func invalidValuesAreRejected(value: Decimal) {
    #expect(throws: IngredientAmount.ValidationError.invalidValue) {
        try IngredientAmount(originalText: "source", value: value)
    }
}

@Test func overflowIsRejected() throws {
    let amount = try IngredientAmount(
        originalText: "source", value: Decimal.greatestFiniteMagnitude)
    #expect(throws: IngredientAmount.ValidationError.arithmeticFailure) {
        try amount.scaled(by: 10)
    }
}

@Test func zeroRemainsZero() throws {
    let amount = try IngredientAmount(originalText: "0 g", value: 0, unit: "g")
    #expect(try amount.scaled(by: 2).value == 0)
}
