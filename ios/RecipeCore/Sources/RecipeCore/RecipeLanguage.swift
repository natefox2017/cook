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
