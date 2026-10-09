// Developer: gengyun
// Purpose: Keeps the interface in English unless a UI test explicitly selects another locale.

import Foundation

/// Uses English by default and permits non-English locales only for explicit UI smoke tests.
public enum RecipeLanguage {
    private static let supportedIdentifiers = Bundle.main.localizations.filter {
        $0.caseInsensitiveCompare("Base") != .orderedSame
    }

    public static let active = resolve(
        arguments: ProcessInfo.processInfo.arguments,
        supportedIdentifiers: supportedIdentifiers
    )


    /// Resolves app and extension catalog strings using the explicit test-stage locale.
    /// Core is a Swift package without its own translations; the host bundle owns them.
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

    static func resolve(arguments: [String], supportedIdentifiers: [String]) -> Locale {
        if arguments.contains("--uitesting"),
            let index = arguments.firstIndex(of: "--uitesting-locale"),
            arguments.indices.contains(index + 1)
        {
            let identifier = arguments[index + 1]
            if supportedIdentifiers.contains(identifier) {
                return Locale(identifier: identifier)
            }
        }

        return Locale(identifier: "en")
    }
}
