// Developer: gengyun
// Purpose: Validate opt-in sharing never publishes private recipe state or unlicensed instructions.

import Foundation
import Testing
@testable import RecipeCore

@Test
func summaryOnlyRecipeIsSafeAndContainsNoPrivateNotesOrMedia() throws {
    var recipe = Recipe(
        title: "Soup", summary: "Warm soup", servings: 2,
        ingredients: [.from(name: "Carrot", amountText: "2 pieces")],
        steps: [.init(instruction: "Simmer.")],
        sourceURL: "https://example.org/soup", notes: "My private note")
    recipe.coverData = Data([1, 2, 3])
    recipe.stepImages = [
        RecipeStepImageReference(
            stepID: recipe.steps[0].id,
            privateAssetPath: "users/secret-photo.png"
        )
    ]
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let result = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    #expect(result.title == "Soup")
    #expect(result.ingredients.isEmpty)
    #expect(result.steps.isEmpty)
    #expect(result.sourceURL == "https://example.org/soup")
    let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    #expect(!json.contains("private"))
    #expect(!json.contains("secret-photo"))
    #expect(!json.contains("owner_id"))
    #expect(!json.contains("coverData"))
    #expect(!json.contains("importRecord"))
}

@Test
func unlicensedOrStaleFullShareIsRejectedWithoutDataChanges() throws {
    let recipe = Recipe(
        title: "Cake",
        ingredients: [.from(name: "Flour", amountText: "100 g")],
        steps: [.init(instruction: "Bake in oven.")])
    let refused = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: false)
    #expect(throws: RecipeShareValidationError.rightsNotConfirmed) {
        _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: refused)
    }
    let stale = RecipeShareApproval(
        recipeID: recipe.id,
        expectedUpdatedAt: recipe.updatedAt.addingTimeInterval(-1),
        scope: .summaryAndSource, hasDistributionRights: false)
    #expect(throws: RecipeShareValidationError.staleRecipe) {
        _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: stale)
    }
    let accepted = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: true)
    let preview = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: accepted)
    #expect(preview.steps.map(\.instruction) == ["Bake in oven."])
    #expect(preview.ingredients.map(\.amountText) == ["100 g"])
    #expect(recipe.notes.isEmpty)
}

@Test
func malformedSourceURLNeverBecomesPublicHyperlink() throws {
    let recipe = Recipe(title: "Salad", sourceURL: "javascript:alert(1)")
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let result = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    #expect(result.sourceURL == nil)
}

@Test
func publicSnapshotSerializesExactlyEightFieldsIncludingNulls() throws {
    let recipe = Recipe(
        title: "Private soup", servings: nil, prepMinutes: nil, cookMinutes: nil)
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let preview = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    let payload = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as? [String: Any])
    let requiredFields: Set<String> = [
        "title", "summary", "sourceURL", "servings",
        "prepMinutes", "cookMinutes", "ingredients", "steps",
    ]
    #expect(Set(payload.keys) == requiredFields)
    for field in ["sourceURL", "servings", "prepMinutes", "cookMinutes"] {
        #expect(payload[field] is NSNull)
    }
    #expect((payload["ingredients"] as? [Any])?.isEmpty == true)
    #expect((payload["steps"] as? [Any])?.isEmpty == true)
    #expect(try JSONDecoder().decode(
        PublicRecipeSnapshot.self, from: JSONEncoder().encode(preview)) == preview)
}

@Test
func publicSnapshotAcceptsNumberBoundariesAndOmitsPrivateSteps() throws {
    let privateRecipe = Recipe(
        title: "Summary", servings: 100, prepMinutes: 0, cookMinutes: 10_080,
        ingredients: Array(repeating: .from(name: "", amountText: ""), count: 201),
        steps: Array(repeating: .init(instruction: " "), count: 101))
    let before = privateRecipe
    let summaryApproval = RecipeShareApproval(
        recipeID: privateRecipe.id, expectedUpdatedAt: privateRecipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false)
    let summary = try PublicRecipeSnapshot.preview(
        of: privateRecipe, approvedBy: summaryApproval)
    #expect(summary.servings == 100)
    #expect(summary.prepMinutes == 0)
    #expect(summary.cookMinutes == 10_080)
    #expect(summary.ingredients.isEmpty)
    #expect(summary.steps.isEmpty)
    #expect(privateRecipe == before)

    let fullRecipe = Recipe(
        title: "Full", servings: 1, prepMinutes: 10_080, cookMinutes: 0,
        ingredients: [.from(name: "Rice", amountText: "1 cup")],
        steps: [.init(title: "Boil", instruction: "Boil the water.")])
    let fullApproval = RecipeShareApproval(
        recipeID: fullRecipe.id, expectedUpdatedAt: fullRecipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: true)
    let full = try PublicRecipeSnapshot.preview(of: fullRecipe, approvedBy: fullApproval)
    #expect(full.servings == 1)
    #expect(full.steps.count == 1)
    #expect(full.ingredients.count == 1)
}

@Test
func publicSnapshotRejectsOutOfRangeNumbers() {
    let invalid: [(Int?, Int?, Int?)] = [
        (0, nil, nil), (101, nil, nil),
        (nil, -1, nil), (nil, 10_081, nil),
        (nil, nil, -1), (nil, nil, 10_081),
    ]
    for (servings, prep, cook) in invalid {
        let recipe = Recipe(
            title: "Numbers", servings: servings, prepMinutes: prep, cookMinutes: cook)
        let approval = RecipeShareApproval(
            recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
            scope: .summaryAndSource, hasDistributionRights: false)
        #expect(throws: RecipeShareValidationError.contentTooLarge) {
            _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
        }
    }
}

@Test
func publicSnapshotRejectsWhitespaceOnlyFullInstructions() {
    let recipes = [
        Recipe(
            title: "Blank ingredient",
            ingredients: [.from(name: " \n ", amountText: "1")],
            steps: [.init(instruction: "Stir.")]),
        Recipe(
            title: "Blank step",
            ingredients: [.from(name: "Onion", amountText: "1")],
            steps: [.init(title: "Slice", instruction: " \t ")]),
    ]
    for recipe in recipes {
        let before = recipe
        let approval = RecipeShareApproval(
            recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
            scope: .fullInstructions, hasDistributionRights: true)
        #expect(throws: RecipeShareValidationError.contentTooLarge) {
            _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
        }
        #expect(recipe == before)
    }
}

@Test
func publicSnapshotRejectsUTF16OverlongEmojiEvenWhenCharacterCountFits() {
    let emoji = "🧑‍🍳"
    let summaryRecipes = [
        Recipe(title: String(repeating: emoji, count: 91)),
        Recipe(title: "Summary", summary: String(repeating: emoji, count: 1_001)),
    ]
    for recipe in summaryRecipes {
        let approval = RecipeShareApproval(
            recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
            scope: .summaryAndSource, hasDistributionRights: false)
        #expect(throws: RecipeShareValidationError.contentTooLarge) {
            _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
        }
    }
    let fullRecipes = [
        Recipe(
            title: "Ingredient",
            ingredients: [.from(name: String(repeating: emoji, count: 91), amountText: "")],
            steps: [.init(instruction: "Cook.")]),
        Recipe(
            title: "Step",
            ingredients: [.from(name: "Pasta", amountText: "1 cup")],
            steps: [.init(instruction: String(repeating: emoji, count: 1_250))]),
    ]
    for recipe in fullRecipes {
        let approval = RecipeShareApproval(
            recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
            scope: .fullInstructions, hasDistributionRights: true)
        #expect(throws: RecipeShareValidationError.contentTooLarge) {
            _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
        }
    }
}

@Test
func publicSnapshotRejectsEncodedJSONLargerThanGuestLimit() {
    // JSON escapes null scalars to six bytes, exceeding 2 MiB after encoding.
    let escapedNull = String(UnicodeScalar(0)!)
    let recipe = Recipe(
        title: "JSON size",
        steps: Array(
            repeating: RecipeStep(instruction: String(repeating: escapedNull, count: 4_000)),
            count: 100))
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: true)
    #expect(throws: RecipeShareValidationError.contentTooLarge) {
        _ = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    }
}
