// Developer: gengyun
// Purpose: Verifies the independent language/region choices and UI-test locale compatibility.

import Testing

@testable import RecipeCore

@Test
func recipeLanguageDefaultsToEnglishWithoutAnExplicitLocaleOverride() {
    let locale = RecipeLanguage.resolve(
        arguments: ["--uitesting"],
        supportedIdentifiers: ["en", "zh-Hans", "zh-Hant", "ja"],
        systemRegion: "GB"
    )

    #expect(locale.identifier == "en")
}

@Test
func recipeLanguageUsesDeviceRegionWhenNoCountryWasSelected() {
    let locale = RecipeLanguage.resolve(
        arguments: [],
        supportedIdentifiers: ["en", "de", "fr"],
        systemRegion: "GB"
    )
    #expect(locale.identifier == "en_GB")
}

@Test
func recipeLanguageAllowsOnlyExplicitSupportedUITestLocales() {
    let supportedIdentifiers = ["en", "zh-Hans", "zh-Hant", "ja"]
    let chineseLocale = RecipeLanguage.resolve(
        arguments: ["--uitesting", "--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: supportedIdentifiers,
        languageOverride: "en",
        regionOverride: "FR"
    )
    let unscopedChineseLocale = RecipeLanguage.resolve(
        arguments: ["--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: supportedIdentifiers
    )

    #expect(chineseLocale.identifier == "zh-Hans")
    #expect(unscopedChineseLocale.identifier == "en")
}

@Test
func selectedLanguageAndCountryAreIndependent() {
    let supported = ["en", "fr", "de", "ja", "ko"]
    let frenchInCanada = RecipeLanguage.resolve(
        arguments: [],
        supportedIdentifiers: supported,
        languageOverride: "fr",
        regionOverride: "CA",
        systemRegion: "US"
    )
    let germanInJapan = RecipeLanguage.resolve(
        arguments: [],
        supportedIdentifiers: supported,
        languageOverride: "de",
        regionOverride: "JP",
        systemRegion: "US"
    )
    #expect(frenchInCanada.language.languageCode?.identifier == "fr")
    #expect(frenchInCanada.region?.identifier == "CA")
    #expect(germanInJapan.language.languageCode?.identifier == "de")
    #expect(germanInJapan.region?.identifier == "JP")
}

@Test
func unsupportedOrInvalidChoicesFallBackSafely() {
    let supported = ["en", "fr", "ja"]
    let fallback = RecipeLanguage.resolve(
        arguments: [],
        supportedIdentifiers: supported,
        languageOverride: "xx",
        regionOverride: "invalid",
        systemRegion: "US"
    )
    let automatic = RecipeLanguage.resolve(
        arguments: [],
        supportedIdentifiers: supported,
        languageOverride: "ja",
        regionOverride: RecipeLanguage.automaticRegion,
        systemRegion: "KR"
    )
    #expect(fallback.identifier == "en_US")
    #expect(automatic.identifier == "ja_KR")
    #expect(RecipeLanguage.countryIdentifiers.contains("GB"))
    #expect(RecipeLanguage.countryIdentifiers.contains("DE"))
    #expect(RecipeLanguage.countryIdentifiers.contains("JP"))
    #expect(RecipeLanguage.countryIdentifiers.contains("KR"))
}
