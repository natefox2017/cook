// Developer: gengyun
// Purpose: Resolves independent UI-language and country preferences for the app and Share Extension.

import Foundation

/// A language offered by the iOS app. Only locales shipped in the app's String Catalog are selectable.
public struct RecipeLanguageOption: Identifiable, Sendable {
    public let id: String
    public let nativeName: String

    public init(id: String, nativeName: String) {
        self.id = id
        self.nativeName = nativeName
    }
}

public enum RecipeLanguage {
    public static let languagePreferenceKey = "recipe.preferences.language"
    public static let regionPreferenceKey = "recipe.preferences.region"
    public static let defaultLanguage = "en"
    public static let automaticRegion = "automatic"

    // This is the App Group entitlement shared by Recipe and RecipeShare.
    private static let appGroupIdentifier = "group.com.shopkivoo.recipe"

    public static let languageOptions: [RecipeLanguageOption] = [
        .init(id: "en", nativeName: "English"),
        .init(id: "de", nativeName: "Deutsch"),
        .init(id: "fr", nativeName: "Français"),
        .init(id: "es", nativeName: "Español"),
        .init(id: "it", nativeName: "Italiano"),
        .init(id: "pt", nativeName: "Português"),
        .init(id: "nl", nativeName: "Nederlands"),
        .init(id: "ja", nativeName: "日本語"),
        .init(id: "ko", nativeName: "한국어"),
        .init(id: "zh-Hans", nativeName: "简体中文"),
        .init(id: "zh-Hant", nativeName: "繁體中文"),
    ]

    /// ISO 3166 countries and territories, not languages or macro-regions.
    /// This covers European and American markets as well as Japan and South Korea.
    public static var countryIdentifiers: [String] {
        Locale.Region.isoRegions.map(\.identifier)
            .filter { code in
                code.count == 2 &&
                    code.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
            }
            .sorted()
    }

    /// Same locale calculation used by the app's reactive AppStorage values.
    public static func configuredLocale(language: String, region: String) -> Locale {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            supportedIdentifiers: Bundle.main.localizations,
            languageOverride: language,
            regionOverride: region,
            systemRegion: Locale.current.region?.identifier
        )
    }

    /// Read the shared preference only in the extension. The main app uses its own
    /// AppStorage keys so legacy installs, previews and isolated UI tests keep working.
    private static var preferences: UserDefaults {
        if Bundle.main.bundleURL.pathExtension == "appex",
            let groupDefaults = UserDefaults(suiteName: appGroupIdentifier)
        {
            return groupDefaults
        }
        return .standard
    }

    /// Recompute on each access: a saved choice must not be frozen at app launch.
    public static var active: Locale {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            supportedIdentifiers: Bundle.main.localizations,
            languageOverride: preferences.string(forKey: languagePreferenceKey),
            regionOverride: preferences.string(forKey: regionPreferenceKey),
            systemRegion: Locale.current.region?.identifier
        )
    }

    /// Mirror changes so the Share Extension displays the same user-selected language.
    /// Nothing is written into the system-wide AppleLanguages preference.
    public static func sharePreferences(language: String, region: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(language, forKey: languagePreferenceKey)
        defaults.set(region, forKey: regionPreferenceKey)
    }

    public static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let identifier = active.identifier
        let base = String(identifier.split(separator: "_", maxSplits: 1).first ?? "en")
        let candidates = [identifier.replacingOccurrences(of: "_", with: "-"), base,
                          String(base.split(separator: "-").first ?? "en")]
        let supported = Bundle.main.localizations
        let resourceID = candidates.first { candidate in
            supported.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
        let bundle = resourceID
            .flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:)) ?? Bundle.main
        let value = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: active, arguments: arguments)
    }

    /// Explicit UI-smoke-test locale wins over saved preferences. Normal first launch
    /// remains English until the user selects another language in Settings.
    static func resolve(
        arguments: [String],
        supportedIdentifiers: [String],
        languageOverride: String? = nil,
        regionOverride: String? = nil,
        systemRegion: String? = nil
    ) -> Locale {
        let supported = Set(supportedIdentifiers.filter { $0 != "Base" })
        if arguments.contains("--uitesting"),
            let index = arguments.firstIndex(of: "--uitesting-locale"),
            arguments.indices.contains(index + 1),
            supported.contains(arguments[index + 1])
        {
            return Locale(identifier: arguments[index + 1])
        }

        if arguments.contains("--uitesting") {
            return Locale(identifier: defaultLanguage)
        }

        let language = languageOverride.flatMap { supported.contains($0) ? $0 : nil }
            ?? defaultLanguage
        let selectedRegion = regionOverride == automaticRegion ? nil : regionOverride
        let region = selectedRegion ?? systemRegion
        if let region, countryIdentifiers.contains(region) {
            return Locale(identifier: "\(language)_\(region)")
        }
        return Locale(identifier: language)
    }
}
