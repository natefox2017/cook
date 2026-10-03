# Cook iOS

Native SwiftUI app, iOS 18 minimum. Open `Cook.xcodeproj`, or regenerate it with `xcodegen generate --spec project.yml` from this directory. Select your own signing team for device installation.

NavigationStack, toolbar buttons, TabView, sheets, forms and SF Symbols use system components. iOS 26 uses the native Liquid Glass controls and floating tab bar; iOS 18–25 retain their native presentation. Warm content surfaces remain solid. Headings use the system serif font; no proprietary Claude fonts are bundled.

## Localization

English is the development language. `CookApp/Localizable.xcstrings` is the single translation catalog. SwiftUI literals and Foundation `String(localized:)` are extracted with `SWIFT_EMIT_LOC_STRINGS`. User recipe content and original sources remain verbatim. Never force the environment locale or use translated strings as persistence identifiers. Add a language in Xcode and translate catalog entries, including plural variations and accessibility labels. No other language is currently translated. Native system controls follow the device language.

Numeric ingredient input currently recognizes English decimal notation only; ambiguous quantities remain raw text. Future locale-aware editing must normalize an explicit number separately from the preserved source, without guessing quantities.

## Current capabilities

Local recipes, photo covers, original sources, favorites, search, servings, groceries and cooking timers persist or operate locally. Captured URLs/text/images/PDFs are saved locally. Automatic parsing, backend sync, accounts and Share Extension are not connected; captured content is never reported as successfully parsed. Cooking timers catch up by deadline after suspension but do not schedule background notifications.

Run `swift test --package-path .` for local model, persistence and timer tests on macOS. Build with `xcodebuild -project Cook.xcodeproj -scheme Cook -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. Generic builds do not establish visual or device acceptance.
