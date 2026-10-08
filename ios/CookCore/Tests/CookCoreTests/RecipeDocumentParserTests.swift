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


@Test func structuredStepsExtractExplicitCookingSignalsWithoutGuessing() throws {
    let html = #"<script type='application/ld+json'>{"@type":"Recipe","name":"Roast chicken","recipeIngredient":["500 g chicken","2 tbsp olive oil","salt to taste"],"recipeInstructions":[{"@type":"HowToStep","name":"Roast","text":"Rub chicken with olive oil. Roast at 200°C for 20 minutes, turn, then cook 10 minutes more."},{"@type":"HowToStep","name":"Rest","text":"Rest until ready to carve."}]}</script>"#
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/chicken")!))
    let roast = recipe.steps[0]
    #expect(roast.temperature?.text == "200°C")
    #expect(roast.timers.map(\.durationSeconds) == [1_200, 600])
    #expect(roast.linkedIngredientIDs.contains(recipe.ingredients[0].id))
    #expect(roast.linkedIngredientIDs.contains(recipe.ingredients[1].id))
    #expect(recipe.steps[1].timers.isEmpty)
    #expect(recipe.steps[1].temperature == nil)
}

@Test(arguments: [
    "Simmer for 10-15 minutes over medium heat.",
    "Simmer for 10 to 15 minutes over medium heat.",
    "Simmer 10 minutes to 15 minutes over medium heat.",
    "Simmer between 10 minutes and 15 minutes over medium heat.",
    "Simmer for about 10 minutes over medium heat.",
    "Simmer for roughly 10 minutes over medium heat.",
    "Simmer for up to 10 minutes over medium heat.",
    "Bake for 10 minutes, or until golden.",
    "Bake for 10 minutes or until golden.",
    "Bake for 10 minutes until golden.",
    "Bake for at least 10 minutes.",
    "Bake for no more than 10 minutes.",
    "Bake for 10 minutes or longer.",
    "Bake for 10 minutes minimum.",
    "Bake for 10 minutes at least.",
    "Bake for 10 minutes at most.",
    "Bake for 10 minutes no more than.",
    "Bake for 10 minutes no less than.",
    "Bake for 10 minutes (or longer).",
    "Bake for 10 minutes (minimum).",
    "Bake for 10 minutes (at least)." 
])
func ambiguousTimesDoNotBecomeFakePreciseTimers(_ instruction: String) throws {
    let escaped = instruction.replacingOccurrences(of: "\"", with: "\\\"")
    let html = "<script type='application/ld+json'>{\"@type\":\"Recipe\",\"name\":\"Soup\",\"recipeIngredient\":[\"1 l water\"],\"recipeInstructions\":[{\"@type\":\"HowToStep\",\"text\":\"\(escaped)\"}]}</script>"
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/soup")!))
    #expect(recipe.steps[0].timers.isEmpty)
    #expect(recipe.steps[0].temperature?.text.lowercased() == "medium heat")
}

@Test func legacySingleTimerStepDecodesIntoTimerCollection() throws {
    let id = UUID()
    let json = #"{"id":"\#(id.uuidString)","title":"Bake","instruction":"Bake until golden.","durationSeconds":600}"#
    let step = try JSONDecoder().decode(RecipeStep.self, from: Data(json.utf8))
    #expect(step.timers.count == 1)
    #expect(step.timers[0].id == id)
    #expect(step.timers[0].durationSeconds == 600)

    let roundTrip = try JSONDecoder().decode(RecipeStep.self, from: JSONEncoder().encode(step))
    #expect(roundTrip == step)
}


@Test func compoundHourMinuteDurationBecomesOneTimer() throws {
    let html = #"<script type='application/ld+json'>{"@type":"Recipe","name":"Braise","recipeIngredient":["500 g beef"],"recipeInstructions":[{"@type":"HowToStep","name":"Braise","text":"Braise for 1 hour 30 minutes at 180°C."}]}</script>"#
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/braise")!))
    #expect(recipe.steps[0].timers.count == 1)
    #expect(recipe.steps[0].timers[0].durationSeconds == 5_400)
}


@Test(arguments: [
    "Braise for about 1 hour 30 minutes.",
    "Braise for 1 hour 30 minutes to 2 hours.",
    "Braise for at least 1 hour 30 minutes."
])
func ambiguousCompoundDurationDoesNotLeakInnerTimers(_ instruction: String) throws {
    let escaped = instruction.replacingOccurrences(of: "\"", with: "\\\"")
    let html = "<script type='application/ld+json'>{\"@type\":\"Recipe\",\"name\":\"Braise\",\"recipeIngredient\":[\"500 g beef\"],\"recipeInstructions\":[{\"@type\":\"HowToStep\",\"text\":\"\(escaped)\"}]}</script>"
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/braise")!))
    #expect(recipe.steps[0].timers.isEmpty)
}


@Test func mixedTimerFormatsPreserveSourceOrder() throws {
    let html = #"<script type='application/ld+json'>{"@type":"Recipe","name":"Timing","recipeIngredient":["1 cup water"],"recipeInstructions":[{"@type":"HowToStep","name":"Cook","text":"Rest 10 minutes, then bake 1 hour 30 minutes, then cool 5 minutes."}]}</script>"#
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/timing")!))
    #expect(recipe.steps[0].timers.map(\.durationSeconds) == [600, 5_400, 300])
}

@Test func extractedTimerCountIsGloballyCappedAtTwelve() throws {
    let compounds = Array(repeating: "Cook 1 hour 30 minutes.", count: 12).joined(separator: " ")
    let instruction = compounds + " Then rest 5 minutes."
    let escaped = instruction.replacingOccurrences(of: "\"", with: "\\\"")
    let html = "<script type='application/ld+json'>{\"@type\":\"Recipe\",\"name\":\"Many timers\",\"recipeIngredient\":[\"1 cup water\"],\"recipeInstructions\":[{\"@type\":\"HowToStep\",\"text\":\"\(escaped)\"}]}</script>"
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/many")!))
    #expect(recipe.steps[0].timers.count == 12)
    #expect(recipe.steps[0].timers.allSatisfy { $0.durationSeconds == 5_400 })
}

@Test func parenthesizedUntilConditionDoesNotBecomeTimer() throws {
    let html = #"<script type='application/ld+json'>{"@type":"Recipe","name":"Bake","recipeIngredient":["1 cup flour"],"recipeInstructions":[{"@type":"HowToStep","text":"Bake for 10 minutes (or until golden)."}]}</script>"#
    let recipe = try #require(RecipeDocumentParser.recipe(inHTML: html, sourceURL: URL(string: "https://example.com/bake")!))
    #expect(recipe.steps[0].timers.isEmpty)
}
