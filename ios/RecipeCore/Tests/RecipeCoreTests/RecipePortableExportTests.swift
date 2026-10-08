// Developer: gengyun
// Purpose: Verifies portable recipe exports, offline HTML, and untrusted text handling.

import Foundation
import Testing
@testable import RecipeCore

@Test func portableJSONPreservesSourceAndCollectionMemberships() throws {
    let ingredient = RecipeIngredient.from(
        name: "塩 & sugar",
        amountText: "to taste",
        category: .pantry
    )
    let recipe = Recipe(
        title: "日本語の料理",
        servings: nil,
        ingredients: [ingredient],
        steps: [RecipeStep(instruction: "Add only as needed.")],
        sourceURL: "https://example.com/recipes?name=ramen&ref=1",
        sourceText: "Raw notes & exact wording.",
        sourceName: "Original author",
        isFavorite: true,
        notes: "Personal note"
    )
    let collection = RecipeCollection(name: "Family & Friends")
    let membership = RecipeCollectionMembership(
        recipeID: recipe.id,
        collectionID: collection.id
    )
    let snapshot = RecipeLibrarySnapshot(
        recipes: [recipe],
        collections: [collection],
        collectionMemberships: [membership]
    )

    let data = try RecipePortableExport.json(
        snapshot: snapshot,
        exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(RecipePortableArchive.self, from: data)

    #expect(decoded.format == "recipepouch.recipes")
    #expect(decoded.version == 1)
    #expect(decoded.recipes.count == 1)
    #expect(decoded.recipes[0].ingredients[0].amountText == "to taste")
    #expect(decoded.recipes[0].sourceText == recipe.sourceText)
    #expect(decoded.recipes[0].isFavorite)
    #expect(decoded.collections.map(\.id) == [collection.id])
    #expect(decoded.collectionMemberships == [membership])
}

@Test func offlineHTMLDisplaysExactAmountsAndEscapesUntrustedContent() throws {
    let recipe = Recipe(
        title: "汤 & <script>alert('x')</script>",
        servings: 2,
        ingredients: [
            RecipeIngredient.from(
                name: "Tomatoes <ripe>",
                amountText: "少许 / to taste"
            )
        ],
        steps: [
            RecipeStep(
                title: "Heat <high>",
                instruction: "Stir & simmer until done.",
                temperature: CookingTemperature(text: "medium-high heat")
            )
        ],
        sourceURL: "javascript:alert('not-a-link')",
        sourceText: "<img src=\"x\" onerror=\"alert(1)\">",
        notes: "Keep the original 1–2 minute range."
    )
    let snapshot = RecipeLibrarySnapshot(recipes: [recipe])

    let data = RecipePortableExport.html(snapshot: snapshot)
    let html = try #require(String(data: data, encoding: .utf8))

    #expect(html.hasPrefix("<!doctype html>"))
    #expect(html.contains("<meta charset=\"utf-8\">"))
    #expect(html.contains("汤 &amp; &lt;script&gt;"))
    #expect(html.contains("少许 / to taste"))
    #expect(html.contains("&lt;img src=&quot;x&quot;"))
    #expect(html.contains("medium-high heat"))
    #expect(html.contains("1–2 minute range"))
    #expect(html.contains("javascript:alert(&#39;not-a-link&#39;)"))
    #expect(!html.contains("href=\"javascript:"))
    #expect(!html.contains("<script>alert("))
    #expect(html.contains("photos, attachments, shopping lists, meal plans"))
}

@Test func portableHTMLHandlesEmptyLibraryWithoutMediaOrAppPreferences() throws {
    let data = RecipePortableExport.html(snapshot: RecipeLibrarySnapshot())
    let html = try #require(String(data: data, encoding: .utf8))

    #expect(html.contains("No saved recipes in this export."))
    #expect(html.contains("RecipePouch Recipes"))
    #expect(!html.contains("<article"))
}

@Test
func offlineHTMLAssociatesCollectionsOnlyWithTheirRecipes() throws {
    let first = Recipe(title: "Apple pie")
    let second = Recipe(title: "Banana bread")
    let alpha = RecipeCollection(name: "Alpha")
    let zeta = RecipeCollection(name: "Zeta")

    let snapshot = RecipeLibrarySnapshot(
        recipes: [first, second],
        collections: [zeta, alpha],
        collectionMemberships: [
            RecipeCollectionMembership(recipeID: first.id, collectionID: zeta.id),
            RecipeCollectionMembership(recipeID: first.id, collectionID: alpha.id)
        ]
    )

    let html = try #require(
        String(data: RecipePortableExport.html(snapshot: snapshot), encoding: .utf8)
    )
    let secondArticle = try #require(html.range(of: "<article id=\\"recipe-2\\">"))
    let appleArticle = html[..<secondArticle.lowerBound]
    let bananaArticle = html[secondArticle.lowerBound...]

    #expect(appleArticle.contains("<strong>Collections:</strong> Alpha, Zeta"))
    #expect(!bananaArticle.contains("<strong>Collections:</strong>"))
}
