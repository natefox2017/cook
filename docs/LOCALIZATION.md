# Localization

Updated: 2026-10-07

## Runtime policy

- UI automation/development acceptance runs with English locale (en) for deterministic labels and screenshots.
- Production does not force a language. SwiftUI receives Locale.autoupdatingCurrent, so the app follows the iPhone user's preferred language.
- English is the development region and fallback language.

## Launch locales

Initial targets: English (en), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant), Japanese (ja), Spanish (es), French (fr), German (de), Korean (ko), Brazilian Portuguese (pt-BR).

## Implementation rules

1. User-facing SwiftUI literals remain localizable; do not use them as persistence identifiers.
2. Accessibility identifiers stay stable English machine identifiers and are never localized.
3. Persist enum/database values separately from localized display labels.
4. Use locale-aware FormatStyle for dates, numbers, quantities and currency.
5. StoreKit product names/prices/offers come from StoreKit localized metadata.
6. Server/API errors map to localizable client messages.
7. Recipe titles and source text remain in the user's/source language; Recipe does not silently translate imported recipes.
8. English is the required test locale. Additional locale QA covers truncation, CJK fallback, pluralization and Dynamic Type before release.

## Translation status (2026-10-08, Issue #26)

**First implementation slice, not full language acceptance:**

- `ios/Recipe/Resources/Localizable.xcstrings` contains **104 explicit English-source UI keys**, each with actual `zh-Hans`, `zh-Hant` and `ja` values. This covers the four tab names, common Recipes/Settings/Account/StoreKit/Cloud Sync actions and basic empty/error labels; it does not prove complete page coverage.
- `ios/Recipe/Resources/InfoPlist.xcstrings` translates `NSCameraUsageDescription` for the same three non-English languages. Both catalogs are registered with the **Recipe app target** in `ios/Recipe.xcodeproj/project.pbxproj`; Xcode `knownRegions` lists en/zh-Hans/zh-Hant/ja.
- `ios/Recipe/Info.plist` advertises only those four shipping locales. es/fr/de/ko/pt-BR are **planned only** and intentionally not advertised until real catalog coverage exists.
- The four Tab title values are `LocalizedStringKey`; dynamic Account mode + SettingsRow labels now explicitly look up localization keys. Persisted identifiers, API values, original recipe names, collections and StoreKit prices are not translated.
- UI tests pass `-AppleLanguages (en)` and `-AppleLocale en_US` for deterministic **English** regression, while a dedicated smoke case selects each of four locale identifiers and checks its Recipes tab label. Live production still follows `.autoupdatingCurrent`.

**Remaining for completion of #26:**

- Build the current target on macOS/Xcode to let Xcode extract all English SwiftUI strings, compare extracted keys with catalog and provide complete translations for four Tab pages, settings, account/subscription, imports, meal planning, cooking and every confirmation/error/disabled/permission/accessibility state.
- Localize dynamic enum labels, `Text(String)` helpers, Core/Services errors, computed strings and arbitrary plural counts. Do not translate stable IDs, raw recipe/evidence fields, user-generated names or provider receipts.
- Replace manual `1 Recipe / n Recipes` concatenation with an Xcode string-catalog plural variation and validate 0/1/many in all languages.
- Verify CJK font glyph fallback, Japanese/Chinese truncation at small widths, Dynamic Type, dark mode, VoiceOver and iOS system dialogs.
- Run `swift test --package-path ios/RecipeCore` and the current Xcode `Recipe` scheme tests in English plus a separate locale smoke run. These commands were **not executed in this source-only PR**.

Implementation guidance:
- [Apple: String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple: Preparing App text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)

Do not mark this app, the extra planned languages, or #26 as fully translated before these runtime checks and remaining English-key coverage are complete.
