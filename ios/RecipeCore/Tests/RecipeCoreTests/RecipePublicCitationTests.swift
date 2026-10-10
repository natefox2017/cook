// Developer: gengyun
// Purpose: Ensure public recipe citations cannot expose credentials or private source links.

import Foundation
import Testing
@testable import RecipeCore

@Test
func publicCitationAllowsOnlyKnownPublicSourceLookups() {
    #expect(
        RecipePublicCitation.eligibleURL("https://example.org/recipes/soup")
            == "https://example.org/recipes/soup"
    )
    #expect(
        RecipePublicCitation.eligibleURL("https://www.youtube.com/watch?v=abc123")
            == "https://www.youtube.com/watch?v=abc123"
    )
    #expect(
        RecipePublicCitation.eligibleURL("https://example.org/recipe?p=42&id=2")
            == "https://example.org/recipe?p=42&id=2"
    )
    #expect(
        RecipePublicCitation.eligibleURL("https://recipes.example.com/recipe")
            == "https://recipes.example.com/recipe"
    )
}

@Test
func publicCitationRejectsCredentialsAndUnknownQueryParameters() {
    for url in [
        "https://alice:password@example.org/recipe",
        "https://example.org/recipe?access_token=private",
        "https://example.org/recipe?api_key=s3cr3t",
        "https://example.org/recipe?signature=abcd",
        "https://example.org/recipe?unknown=user-secret",
        "https://example.org/recipe#signed-session",
    ] {
        #expect(RecipePublicCitation.eligibleURL(url) == nil)
    }
}

@Test
func publicCitationExcludesLocalAndNonHTTPSAddresses() {
    for url in [
        "http://example.org/recipe",
        "https://localhost/recipe",
        "https://printer.local/recipe",
        "https://127.0.0.1/recipe",
        "https://[::1]/recipe",
        "https://example.org:8443/recipe",
        "javascript:alert(1)",
    ] {
        #expect(RecipePublicCitation.eligibleURL(url) == nil)
    }
}

@Test
func publicCitationRejectsTrailingDotsAndLocalDomainAliases() {
    for url in [
        "https://localhost./recipe",
        "https://printer.local./recipe",
        "https://PrInTeR.LoCaL./recipe",
        "https://example.org./recipe",
        "https://router.localhost/recipe",
        "https://ROUTER.LoCaLhOsT/recipe",
        "https://localhost.localdomain/recipe",
        "https://printer.localdomain/recipe",
    ] {
        #expect(RecipePublicCitation.eligibleURL(url) == nil)
    }
}

@Test
func publicCitationKeepsOriginalDataPrivateWhenMalformed() {
    let original = "https://example.org/recipe?token=not-public"
    let recipe = Recipe(title: "Soup", sourceURL: original)
    let approval = RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false
    )
    let preview = try? PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
    #expect(preview?.sourceURL == nil)
    #expect(recipe.sourceURL == original)
}
