// Developer: gengyun
// Purpose: Resolves test-stage English or a deliberate supported manual app-language choice.

import Foundation

/// Locale policy is shared by SwiftUI, service errors and the Share extension.
/// In test-stage normal launches the default remains English. A user's explicit
/// supported choice wins unless a UI test explicitly forces its own fixture.
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
            selectedIdentifier: selectedIdentifier(
                processDefaults: .standard,
                groupDefaults: UserDefaults(suiteName: RecipeShareInbox.appGroupID),
                isExtension: Bundle.main.bundleURL.pathExtension == "appex"
            )
        )
    }

    /// An .appex has a different standard defaults container from its containing app.
    /// The host owns the choice; stale extension-private defaults are never a fallback.
    public static func selectedIdentifier(
        processDefaults: UserDefaults, groupDefaults: UserDefaults?, isExtension: Bool
    ) -> String? {
        if isExtension {
            return groupDefaults?.string(forKey: preferenceKey)
        }
        return processDefaults.string(forKey: preferenceKey)
    }

    /// Mirror only the language code; never copy accounts, recipes or country.
    /// Missing App Group provisioning must not break the primary app's settings.
    public static func mirrorManualSelection(
        _ identifier: String,
        groupDefaults: UserDefaults? = UserDefaults(suiteName: RecipeShareInbox.appGroupID)
    ) {
        guard let groupDefaults else { return }
        if currentlyTranslatedLanguages.contains(identifier) {
            groupDefaults.set(identifier, forKey: preferenceKey)
        } else {
            // Empty (test-stage English default) and unsupported languages reset.
            groupDefaults.removeObject(forKey: preferenceKey)
        }
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
        // Explicit UI-test locales remain deterministic. Otherwise a deliberate
        // manual choice must work even in a UI-test launch.
        if arguments.contains("--uitesting"),
            let index = arguments.firstIndex(of: "--uitesting-locale"),
            arguments.indices.contains(index + 1),
            supportedIdentifiers.contains(arguments[index + 1]),
            currentlyTranslatedLanguages.contains(arguments[index + 1])
        {
            return Locale(identifier: arguments[index + 1])
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
