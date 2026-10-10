// Developer: gengyun
// Purpose: Verifies English defaults and explicit UI-test locale selection.

import Foundation
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


@Test
func shareExtensionReadsHostLanguageFromAppGroupRatherThanItsOwnDefaults() throws {
    let suitePrefix = "recipe.language.tests.\(UUID().uuidString)"
    let hostSuite = suitePrefix + ".host"
    let extensionSuite = suitePrefix + ".extension"
    let groupSuite = suitePrefix + ".group"
    let host = try #require(UserDefaults(suiteName: hostSuite))
    let shareExtension = try #require(UserDefaults(suiteName: extensionSuite))
    let group = try #require(UserDefaults(suiteName: groupSuite))
    defer {
        host.removePersistentDomain(forName: hostSuite)
        shareExtension.removePersistentDomain(forName: extensionSuite)
        group.removePersistentDomain(forName: groupSuite)
    }

    host.set("ja", forKey: RecipeLanguage.preferenceKey)
    #expect(shareExtension.string(forKey: RecipeLanguage.preferenceKey) == nil)
    #expect(RecipeLanguage.selectedIdentifier(
        processDefaults: host, groupDefaults: group, isExtension: false
    ) == "ja")
    #expect(RecipeLanguage.selectedIdentifier(
        processDefaults: shareExtension, groupDefaults: group, isExtension: true
    ) == nil, "An extension cannot read the host app's standard defaults")

    // Publishing the setting makes it visible in the separate extension domain.
    RecipeLanguage.mirrorManualSelection("ja", groupDefaults: group)
    let selected = RecipeLanguage.selectedIdentifier(
        processDefaults: shareExtension, groupDefaults: group, isExtension: true)
    #expect(selected == "ja")
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: RecipeLanguage.currentlyTranslatedLanguages,
        selectedIdentifier: selected
    ).identifier == "ja")

    // A stale extension-domain preference must not defeat a newer host change.
    shareExtension.set("zh-Hans", forKey: RecipeLanguage.preferenceKey)
    host.set("zh-Hant", forKey: RecipeLanguage.preferenceKey)
    RecipeLanguage.mirrorManualSelection("zh-Hant", groupDefaults: group)
    #expect(RecipeLanguage.selectedIdentifier(
        processDefaults: shareExtension, groupDefaults: group, isExtension: true
    ) == "zh-Hant")

    // Returning to the temporary English test default must clear the mirror.
    host.removeObject(forKey: RecipeLanguage.preferenceKey)
    RecipeLanguage.mirrorManualSelection("", groupDefaults: group)
    #expect(group.object(forKey: RecipeLanguage.preferenceKey) == nil)
    #expect(RecipeLanguage.selectedIdentifier(
        processDefaults: host, groupDefaults: group, isExtension: false
    ) == nil)
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: RecipeLanguage.currentlyTranslatedLanguages,
        selectedIdentifier: RecipeLanguage.selectedIdentifier(
            processDefaults: shareExtension, groupDefaults: group, isExtension: true)
    ).identifier == "en", "Clearing the shared choice must not resurrect stale extension defaults")
}

@Test
func shareExtensionRejectsUnshippedGroupLanguageAndKeepsUITestOverride() throws {
    let suitePrefix = "recipe.language.invalid.\(UUID().uuidString)"
    let extensionSuite = suitePrefix + ".extension"
    let groupSuite = suitePrefix + ".group"
    let process = try #require(UserDefaults(suiteName: extensionSuite))
    let group = try #require(UserDefaults(suiteName: groupSuite))
    defer {
        process.removePersistentDomain(forName: extensionSuite)
        group.removePersistentDomain(forName: groupSuite)
    }

    RecipeLanguage.mirrorManualSelection("de", groupDefaults: group)
    #expect(group.string(forKey: RecipeLanguage.preferenceKey) == nil)
    group.set("de", forKey: RecipeLanguage.preferenceKey)
    let invalidChoice = RecipeLanguage.selectedIdentifier(
        processDefaults: process, groupDefaults: group, isExtension: true)
    #expect(RecipeLanguage.resolve(
        arguments: [], supportedIdentifiers: RecipeLanguage.currentlyTranslatedLanguages,
        selectedIdentifier: invalidChoice
    ).identifier == "en", "Do not advertise translations that are not released")

    RecipeLanguage.mirrorManualSelection("ja", groupDefaults: group)
    let validChoice = RecipeLanguage.selectedIdentifier(
        processDefaults: process, groupDefaults: group, isExtension: true)
    #expect(RecipeLanguage.resolve(
        arguments: ["--uitesting", "--uitesting-locale", "zh-Hans"],
        supportedIdentifiers: RecipeLanguage.currentlyTranslatedLanguages,
        selectedIdentifier: validChoice
    ).identifier == "zh-Hans")
    #expect(RecipeLanguage.selectedIdentifier(
        processDefaults: process, groupDefaults: nil, isExtension: true
    ) == nil, "Unprovisioned App Group should not crash the extension")
}
