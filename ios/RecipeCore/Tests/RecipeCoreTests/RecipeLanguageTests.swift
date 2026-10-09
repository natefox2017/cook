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
