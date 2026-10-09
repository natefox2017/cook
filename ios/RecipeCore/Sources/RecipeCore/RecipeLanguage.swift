// Developer: gengyun
// Purpose: Resolves test-stage English or a deliberate supported manual app-language choice.

import Foundation

/// Locale policy is shared by SwiftUI, service errors and the Share extension.
/// In test-stage normal launches the default remains English. A user's explicit
/// supported choice wins outside test runs; UI tests can force their own fixture.
public enum RecipeLanguage {
    public static let preferenceKey = "recipe.languageOverride"
    public static let currentlyTranslatedLanguages: [String] = [
        "en", "zh-Hans", "zh-Hant", "ja",
    ]
    private static let supportedIdentifiers = Bundle.main.localizations.filter {
        $0.caseInsensitiveCompare("Base") != .orderedSame
    }

    public static var active: Locale {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            supportedIdentifiers: supportedIdentifiers,
            selectedIdentifier: UserDefaults.standard.string(forKey: preferenceKey)
        )
    }

    /// Core is a Swift package; UI localization resources belong to the host.
    public static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let translation: String
        if let path = Bundle.main.path(forResource: active.identifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            translation = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        } else {
            translation = key
        }
        guard !arguments.isEmpty else { return translation }
        return String(format: translation, locale: active, arguments: arguments)
    }

    public static func resolve(
        arguments: [String], supportedIdentifiers: [String],
        selectedIdentifier: String? = nil
    ) -> Locale {
        if arguments.contains("--uitesting") {
            if let index = arguments.firstIndex(of: "--uitesting-locale"),
                arguments.indices.contains(index + 1),
                supportedIdentifiers.contains(arguments[index + 1])
            {
                return Locale(identifier: arguments[index + 1])
            }
            return Locale(identifier: "en")
        }

        if let selectedIdentifier,
            supportedIdentifiers.contains(selectedIdentifier),
            currentlyTranslatedLanguages.contains(selectedIdentifier)
        {
            return Locale(identifier: selectedIdentifier)
        }

        return Locale(identifier: "en")
    }
}
