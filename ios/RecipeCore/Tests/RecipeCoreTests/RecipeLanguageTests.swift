// Developer: gengyun
// Purpose: Verifies English defaults and explicit UI-test locale selection.

import Testing

@testable import RecipeCore

@Test
func recipeLanguageDefaultsToEnglishWithoutAnExplicitLocaleOverride() {
    let locale = RecipeLanguage.resolve(
        arguments: ["--uitesting"],
        supportedIdentifiers: ["en", "zh-Hans", "zh-Hant", "ja"]
    )

    #expect(locale.identifier == "en")
}

@Test
func recipeLanguageAllowsOnlyExplicitSupportedUITestLocales() {
    let supportedIdentifiers = ["en", "zh-Hans", "zh-Hant", "ja"]
    let chineseLocale = RecipeLanguage.resolve(
        arguments: ["--uitesting", "--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: supportedIdentifiers
    )
    let unscopedChineseLocale = RecipeLanguage.resolve(
        arguments: ["--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: supportedIdentifiers
    )

    #expect(chineseLocale.identifier == "zh-Hans")
    #expect(unscopedChineseLocale.identifier == "en")
}

@Test
func userLanguageChoiceOverridesEnglishUnlessUITestForcesItsLocale() {
    let supported = ["en", "ja", "zh-Hans", "zh-Hant"]
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: supported,
        selectedIdentifier: "ja"
    ).identifier == "ja")
    #expect(RecipeLanguage.resolve(
        arguments: ["--uitesting"], supportedIdentifiers: supported,
        selectedIdentifier: "ja"
    ).identifier == "ja")
    #expect(RecipeLanguage.resolve(
        arguments: ["--uitesting", "--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: supported,
        selectedIdentifier: "ja"
    ).identifier == "zh-Hans")
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: supported,
        selectedIdentifier: "de"
    ).identifier == "en")
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: supported,
        selectedIdentifier: "xx-Invalid"
    ).identifier == "en")
}
