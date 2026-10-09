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
