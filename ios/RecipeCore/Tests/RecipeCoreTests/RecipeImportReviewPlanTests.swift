// Developer: gengyun
// Purpose: Verify review prompts are grounded in server review fields, never model guesses.

import Foundation
import Testing
@testable import RecipeCore

@Test
func missingFieldsGetAtMostThreeQuestionsAndKeepEvidenceIDs() {
    let evidenceID = UUID()
    let result = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "url"),
        fields: [
            "ingredients[0].name": .init(
                rawValue: "Garlic", evidenceIDs: [evidenceID], origin: "extracted"),
            "title": .init(rawValue: "", userConfirmed: true, origin: "user_provided")
        ],
        reviewFields: ["title", "ingredients", "steps", "servings", "unknown_flag"]
    )
    let questions = RecipeImportReviewPlan.questions(from: result)
    #expect(questions.map(\.id) == ["ingredients", "steps", "servings"])
    #expect(questions[0].evidenceIDs == [evidenceID])
    #expect(RecipeImportReviewPlan.questions(from: result, maximum: 1).count == 1)
    #expect(RecipeImportReviewPlan.questions(from: result, maximum: 0).isEmpty)
}

@Test
func completeImportOrNoFlagDoesNotInventReviewQuestions() {
    let source = RecipeImportJobResponse.Source(inputType: "url")
    let ready = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "ready", source: source, fields: [:],
        reviewFields: ["ingredients", "steps"])
    #expect(RecipeImportReviewPlan.questions(from: ready).isEmpty)
    let partial = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review", source: source, fields: [:],
        reviewFields: ["structured_data", "artifact_text"])
    #expect(RecipeImportReviewPlan.questions(from: partial).isEmpty)
}

@Test
func oneConfirmedIngredientCannotHideOtherMissingIngredientQuestions() {
    let result = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review", source: .init(inputType: "text"),
        fields: [
            "ingredients[0].name": .init(
                rawValue: "Flour", userConfirmed: true, origin: "user_provided"),
            "ingredients[1].name": .init(
                rawValue: nil, userConfirmed: false, origin: "extracted")
        ],
        reviewFields: ["ingredients[1].name", "steps"]
    )
    #expect(RecipeImportReviewPlan.questions(from: result).map(\.id) ==
        ["ingredients", "steps"])
}

@Test
func missingIndexedIngredientFieldIsNotHiddenByConfirmedSibling() {
    let evidenceID = UUID()
    let confirmed = RecipeImportJobResponse.Field(
        rawValue: "Garlic", evidenceIDs: [evidenceID],
        userConfirmed: true, origin: "user_provided"
    )
    let result = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "text"),
        fields: ["ingredients[0].name": confirmed],
        reviewFields: ["ingredients[1].name", "steps", "servings"]
    )

    let questions = RecipeImportReviewPlan.questions(from: result)
    #expect(questions.map(\.id) == ["ingredients", "steps", "servings"])
    #expect(questions[0].evidenceIDs == [evidenceID])
    #expect(RecipeImportReviewPlan.questions(from: result, maximum: 2).map(\.id) ==
        ["ingredients", "steps"])
}

@Test
func confirmedSpecificReviewPathsAndStaleGroupFlagsAreStillIgnored() {
    let confirmed = RecipeImportJobResponse.Field(
        rawValue: "Flour", userConfirmed: true, origin: "user_provided"
    )
    let fields = ["ingredients[0].name": confirmed]
    let exact = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "text"), fields: fields,
        reviewFields: ["ingredients[0].name"]
    )
    let group = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "text"), fields: fields,
        reviewFields: ["ingredients"]
    )
    #expect(RecipeImportReviewPlan.questions(from: exact).isEmpty)
    #expect(RecipeImportReviewPlan.questions(from: group).isEmpty)

    let mixed = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "text"), fields: fields,
        reviewFields: ["ingredients[0].name", "ingredients[2].amount"]
    )
    #expect(RecipeImportReviewPlan.questions(from: mixed).map(\.id) == ["ingredients"])
}

@Test
func missingReviewPathKeepsSortedSiblingEvidenceWithoutCreatingNewData() {
    let earlier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let later = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let result = RecipeImportJobResponse.Result(
        recipeID: UUID(), status: "needs_review",
        source: .init(inputType: "url"),
        fields: [
            "ingredients[0].name": .init(
                rawValue: "Onion", evidenceIDs: [later],
                userConfirmed: true, origin: "user_provided"
            ),
            "ingredients[1].name": .init(
                rawValue: "Pepper", evidenceIDs: [earlier, later],
                userConfirmed: true, origin: "user_provided"
            ),
        ],
        reviewFields: ["ingredients[2].amount", "unknown_flag"]
    )
    let questions = RecipeImportReviewPlan.questions(from: result)
    #expect(questions.map(\.id) == ["ingredients"])
    #expect(questions[0].evidenceIDs == [earlier, later])
    #expect(RecipeImportReviewPlan.questions(from: result, maximum: 0).isEmpty)
}
