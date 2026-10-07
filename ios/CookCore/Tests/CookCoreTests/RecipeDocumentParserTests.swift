import Foundation
import Testing
@testable import CookCore

@Test func nestedSchemaPreservesEvidenceAndUnknownYield() throws {
    let html = #"<script type='application/ld+json'>{"@graph":[{"@type":"WebPage"},{"@type":["Recipe"],"name":"Lemon &amp; pasta","recipeYield":"2–4 servings","prepTime":"PT5M","cookTime":"PT10M","recipeIngredient":["2 tbsp olive oil","salt to taste","1-2 lemons"],"recipeInstructions":[{"@type":"HowToSection","itemListElement":[{"@type":"HowToStep","name":"Cook","text":"Cook the pasta."}]},"Season to taste."]}]}</script>"#
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/pasta")!))
    #expect(recipe.title == "Lemon & pasta")
    #expect(recipe.servings == nil)
    #expect(recipe.ingredients[0].quantity == 2)
    #expect(recipe.ingredients[0].name == "olive oil")
    #expect(recipe.ingredients[1].name == "salt to taste")
    #expect(recipe.ingredients[2].quantity == nil)
    #expect(recipe.steps.count == 2)
    #expect(recipe.totalMinutes == 15)
    #expect(recipe.sourceText?.contains("1-2 lemons") == true)
    #expect(recipe.sourceURL == "https://example.com/pasta")
}

@Test func nonRecipePageNeverBecomesDemoContent() {
    #expect(RecipeDocumentParser.recipe(inHTML: "<title>Private video</title>", sourceURL: URL(string: "https://example.com/video")!) == nil)
    let recipe = RecipeDocumentParser.recipe(fromText: "A little salt and cook until ready.")
    #expect(recipe.needsReview)
    #expect(recipe.ingredients.isEmpty)
    #expect(recipe.steps.isEmpty)
    #expect(recipe.sourceText == "A little salt and cook until ready.")
}

@Test func explicitTextSectionsCanBeSavedWithoutAI() {
    let recipe = RecipeDocumentParser.recipe(fromText: "Lemon dressing\nIngredients:\n2 tbsp olive oil\nSalt to taste\nDirections:\n1. Mix everything.\n2. Taste and serve.")
    #expect(recipe.title == "Lemon dressing")
    #expect(recipe.ingredients.count == 2)
    #expect(recipe.steps[0].instruction == "Mix everything.")
    #expect(recipe.needsReview == false)
}

@Test(arguments: ["file:///etc/passwd", "http://example.com", "https://localhost/", "https://127.0.0.1/", "https://192.168.1.1/", "https://[::1]/", "https://printer.local/", "https://user:password@example.com/", "https://example.com:8443/", "https://0x7f.0.0.1/", "https://0xc0.0xa8.0x1.0x1/", "https://0177.0.0.1/", "https://0x7f.1/", "https://localhost.localdomain/", "https://router.home.arpa/", "https://recipe.localhost/"])
func unsafeSourceLinksAreRejected(_ input: String) {
    #expect(RecipeDocumentParser.validatedSourceURL(input) == nil)
}

@Test func sourceTextPreservesWhitespaceAndOversizedEvidence() {
    let original = "  Soup\nIngredients:\n1 cup water\nSteps:\nHeat the water.\n  "
    #expect(RecipeDocumentParser.recipe(fromText: original).sourceText == original)

    let oversized = original + String(repeating: "x", count: RecipeDocumentParser.maximumTextCharacters) + "\nSOURCE_END"
    let recipe = RecipeDocumentParser.recipe(fromText: oversized)
    #expect(recipe.sourceText == oversized)
    #expect(recipe.needsReview)
    #expect(recipe.ingredients.isEmpty)
    #expect(recipe.steps.isEmpty)
}

@Test(arguments: [
    #"<script type='application/ld+json'>{"@type":"Recipe","name":""}</script><script type='application/ld+json'>{"@type":"Recipe","name":"Good recipe","recipeIngredient":["1 cup water"],"recipeInstructions":"Heat the water."}</script>"#,
    #"<script type='application/ld+json'>{"@graph":[{"@type":"Recipe","name":" "},{"@type":"Recipe","name":"Good recipe","recipeIngredient":["1 cup water"],"recipeInstructions":"Heat the water."}]}</script>"#,
    #"<script type='application/ld+json'>[{"@type":"Recipe","name":"<p></p>"},{"@type":"Recipe","name":"Good recipe","recipeIngredient":["1 cup water"],"recipeInstructions":"Heat the water."}]</script>"#
])
func unusableSchemaDoesNotHideALaterRecipe(_ html: String) throws {
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/recipe")!))
    #expect(recipe.title == "Good recipe")
    #expect(recipe.needsReview == false)
}

@Test(arguments: ["PT10001H5M", "PT999999999999999999999999999999H5M", "PT10001M5S"])
func invalidDurationComponentDoesNotBecomeAPartialTime(_ duration: String) throws {
    let html = "<script type='application/ld+json'>{\"@type\":\"Recipe\",\"name\":\"Recipe\",\"prepTime\":\"\(duration)\"}</script>"
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/recipe")!))
    #expect(recipe.prepMinutes == nil)
    #expect(recipe.totalMinutes == nil)
}

@Test func ordinaryPublicDomainRemainsAccepted() {
    #expect(RecipeDocumentParser.validatedSourceURL("https://recipes.example.com/dish?id=2") != nil)
}

@Test func duplicateKeyPreservesMeaningfulQuery() {
    let a = URL(string: "https://EXAMPLE.com/recipe?id=1#ingredients")!
    let b = URL(string: "https://example.com/recipe?id=1")!
    let c = URL(string: "https://example.com/recipe?id=2")!
    #expect(RecipeDocumentParser.sourceKey(a) == RecipeDocumentParser.sourceKey(b))
    #expect(RecipeDocumentParser.sourceKey(a) != RecipeDocumentParser.sourceKey(c))
}
