// Developer: gengyun
// Purpose: Keeps the iOS app and Share Extension on one temporary QA language policy.

import Foundation

/// Centralizes the app's display locale without removing shipping translations.
/// Set `forceEnglishDuringQA` to false and complete locale QA before release.
public enum RecipeUILanguage {
    public static let forceEnglishDuringQA = true

    public static var locale: Locale {
        // Dedicated localization smoke tests may request another language.
        // Ordinary simulator and device launches must still display English.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting"),
           let index = arguments.firstIndex(of: "--uitesting-locale"),
           arguments.indices.contains(index + 1) {
            let identifier = arguments[index + 1]
            if ["en", "zh-Hans", "zh-Hant", "ja"].contains(identifier) {
                return Locale(identifier: identifier)
            }
        }

        return forceEnglishDuringQA
            ? Locale(identifier: "en")
            : .autoupdatingCurrent
    }
}
