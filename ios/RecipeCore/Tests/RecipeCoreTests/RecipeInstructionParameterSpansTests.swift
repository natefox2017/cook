// Developer: gengyun
// Purpose: Verify evidence-only tappable step fragments without rewriting recipe instructions.

import Foundation
import Testing

@testable import RecipeCore

@Test
func inlineStepLinksOnlyRecordedIngredientTemperatureAndTimer() {
    let garlic = RecipeIngredient(name: "garlic", amountText: "2 cloves")
    let unlinked = RecipeIngredient(name: "salt", amountText: "to taste")
    let timer = RecipeStepTimer(label: "Bake", durationSeconds: 1_200)
    let instruction = "Stir garlic, then bake at 180°C for 20 min. 🥘"
    let step = RecipeStep(
        instruction: instruction,
        linkedIngredientIDs: [garlic.id],
        temperature: CookingTemperature(text: "180°C"),
        timers: [timer]
    )

    let spans = RecipeInstructionParameterSpans.spans(
        for: step, ingredients: [garlic, unlinked]
    )

    #expect(spans.map(\.text).joined() == instruction)
    #expect(spans.filter { $0.parameter == .ingredient(garlic.id) }.map(\.text) == ["garlic"])
    #expect(spans.filter { $0.parameter == .temperature }.map(\.text) == ["180°C"])
    #expect(spans.filter { $0.parameter == .timer(timer.id) }.map(\.text) == ["20 min"])
    #expect(!spans.contains { $0.parameter == .ingredient(unlinked.id) })
    #expect(step.instruction == instruction)
}

@Test
func mixedCJKAndEmojiStepTextPreservesGraphemeBoundaries() {
    let water = RecipeIngredient(name: "水", amountText: "少许")
    let scallions = RecipeIngredient(name: "青葱", amountText: "to taste")
    let step = RecipeStep(
        instruction: "🥣加入水、青葱，搅拌 👩🏽‍🍳。再加２杯米。",
        linkedIngredientIDs: [water.id, scallions.id]
    )
    let spans = RecipeInstructionParameterSpans.spans(
        for: step, ingredients: [water, scallions]
    )
    #expect(spans.map(\.text).joined() == step.instruction)
    #expect(spans.filter { $0.parameter == .ingredient(water.id) }.map(\.text) == ["水"])
    #expect(spans.filter { $0.parameter == .ingredient(scallions.id) }.map(\.text) == ["青葱"])
    #expect(spans.filter { $0.parameter != nil }.count == 2)
}

@Test
func ambiguousIngredientNamesAndEnglishSubstringsRemainPlain() {
    let salt = RecipeIngredient(name: "salt")
    let seaSalt = RecipeIngredient(name: "sea salt")
    let step = RecipeStep(
        instruction: "Use sea salt; avoid salted butter.",
        linkedIngredientIDs: [salt.id, seaSalt.id]
    )
    let spans = RecipeInstructionParameterSpans.spans(
        for: step, ingredients: [salt, seaSalt]
    )
    #expect(spans.map(\.text).joined() == step.instruction)
    #expect(spans.allSatisfy { $0.parameter == nil })

    let first = RecipeIngredient(name: "Sugar")
    let second = RecipeIngredient(name: "sugar")
    let duplicate = RecipeStep(
        instruction: "Add sugar.", linkedIngredientIDs: [first.id, second.id]
    )
    #expect(RecipeInstructionParameterSpans.spans(
        for: duplicate, ingredients: [first, second]
    ).allSatisfy { $0.parameter == nil })
}

@Test
func mismatchedOrUnstructuredValuesCannotCreateInlineLinks() {
    let garlic = RecipeIngredient(name: "garlic")
    let timer = RecipeStepTimer(label: "Bake", durationSeconds: 1_200)
    let step = RecipeStep(
        instruction: "Add garlic for about 20 min, at 180°C.",
        temperature: CookingTemperature(text: "medium-high"),
        timers: [timer]
    )
    #expect(RecipeInstructionParameterSpans.spans(
        for: step, ingredients: [garlic]
    ).allSatisfy { $0.parameter == nil })

    let exact = RecipeStep(
        instruction: "Bake for 20 min or 30 min.",
        timers: [
            RecipeStepTimer(label: "A", durationSeconds: 1_200),
            RecipeStepTimer(label: "B", durationSeconds: 1_200),
        ]
    )
    #expect(RecipeInstructionParameterSpans.spans(
        for: exact, ingredients: []
    ).allSatisfy { $0.parameter == nil })
}

@Test
func exactHoursSecondsAndForPrefixAreRecognized() {
    let hour = RecipeStepTimer(label: "Rest", durationSeconds: 3_600)
    let seconds = RecipeStepTimer(label: "Whisk", durationSeconds: 20)
    let step = RecipeStep(
        instruction: "Rest for 1 hour, then whisk for 20 secs.",
        timers: [hour, seconds]
    )
    let spans = RecipeInstructionParameterSpans.spans(
        for: step, ingredients: []
    )
    #expect(spans.map(\.text).joined() == step.instruction)
    #expect(spans.filter { $0.parameter == .timer(hour.id) }.map(\.text) == ["1 hour"])
    #expect(spans.filter { $0.parameter == .timer(seconds.id) }.map(\.text) == ["20 secs"])
}

@Test
func rangedTimerExpressionsAndConflictingNumbersAreNotLinked() {
    let timer = RecipeStepTimer(label: "Bake", durationSeconds: 1_200)
    for raw in ["Bake 10–20 min", "Bake 10-20 min", "Bake about 20 minutes",
                "Bake 10 to 20 min", "Bake 25 min", "Bake 1.5 min"] {
        let step = RecipeStep(instruction: raw, timers: [timer])
        let spans = RecipeInstructionParameterSpans.spans(for: step, ingredients: [])
        #expect(spans.map(\.text).joined() == raw)
        #expect(spans.allSatisfy { $0.parameter == nil }, "Unexpected match: \(raw)")
    }
}

@Test
func denseLinkedIngredientsUseBoundedFallbackWithoutDroppingSourceText() {
    let ingredients = (0..<16).map {
        RecipeIngredient(name: "item\($0)")
    }
    let instruction = (0..<10).flatMap { _ in
        ingredients.map(\.name)
    }.joined(separator: " ")
    let step = RecipeStep(
        instruction: instruction, linkedIngredientIDs: ingredients.map(\.id)
    )
    let spans = RecipeInstructionParameterSpans.spans(
        for: step, ingredients: ingredients
    )
    #expect(spans == [RecipeInstructionSpan(text: instruction)])
}

@Test
func enormousOrEmptyInstructionsFallBackWithoutParserWork() {
    let ingredient = RecipeIngredient(name: "salt")
    for source in ["", String(repeating: "salt ", count: 900)] {
        let step = RecipeStep(
            instruction: source, linkedIngredientIDs: [ingredient.id]
        )
        let spans = RecipeInstructionParameterSpans.spans(
            for: step, ingredients: [ingredient]
        )
        #expect(spans == [RecipeInstructionSpan(text: source)])
    }
}
