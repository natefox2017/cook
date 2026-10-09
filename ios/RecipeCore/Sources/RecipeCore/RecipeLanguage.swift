// Developer: gengyun
// Purpose: Selects a supported UI locale from the user's language preferences.

import Foundation

/// Resolves a supported interface language while preserving explicit locale smoke-test overrides.
public enum RecipeLanguage {
    private static let supportedIdentifiers = Bundle.main.localizations.filter {
        $0.caseInsensitiveCompare("Base") != .orderedSame
    }

    public static let active: Locale = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting"),
            let index = arguments.firstIndex(of: "--uitesting-locale"),
            arguments.indices.contains(index + 1)
        {
            let identifier = arguments[index + 1]
            if supportedIdentifiers.contains(identifier) {
                return Locale(identifier: identifier)
            }
        }

        let preferred = Bundle.preferredLocalizations(
            from: supportedIdentifiers,
            forPreferences: Locale.preferredLanguages
        )
        // The bundle's development language is the source language for unmatched preferences.
        let fallback = Bundle.main.developmentLocalization ?? "en"
        return Locale(identifier: preferred.first ?? fallback)
    }()
}
