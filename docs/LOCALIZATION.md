# Localization

Updated: 2026-10-08

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

**Four-language implementation is still partial:**

- `ios/Recipe/Resources/Localizable.xcstrings` contains **317 English-source keys** with actual `zh-Hans`, `zh-Hant` and `ja` values. This includes 16 import, cloud-sync, local-reset and timer-notification error/status strings added in this pass. Coverage across recipe detail/editing, groceries, meal planning, cooking, Collections, Settings, privacy, Account, StoreKit and Cloud Sync remains incomplete.
- `ios/Recipe/Resources/InfoPlist.xcstrings` translates `NSCameraUsageDescription` for the same three non-English languages. Both catalogs are registered with the **Recipe app target** in `ios/Recipe.xcodeproj/project.pbxproj`; Xcode `knownRegions` lists en/zh-Hans/zh-Hant/ja.
- `ios/Recipe/Info.plist` advertises only those four shipping locales. es/fr/de/ko/pt-BR are **planned only** and intentionally not advertised until real catalog coverage exists.
- The four Tab title values are `LocalizedStringKey`; dynamic Account/Settings labels, enum-backed recipe/grocery categories, meal slots, Appearance and Sync modes now explicitly look up localization keys. Persisted identifiers, API values, original recipe names, collections and StoreKit prices are not translated.
- UI tests pass `-AppleLanguages (en)` and `-AppleLocale en_US` for deterministic **English** regression, while the four-locale smoke test selects each supported locale and checks the Recipes tab and recipe count. Live production still follows `.autoupdatingCurrent`; a normal launch on a zh-Hans simulator displayed the Chinese first-launch title and action.

**Remaining for completion of #26:**

- The current Xcode `Recipe` target and both String Catalogs compiled successfully with Xcode 27 on an iOS 27 simulator. `testFourLocaleTabLabelsUseStringCatalog` passed on iPhone 18 Pro Max (1 test, 0 failures), checking all four locale launches. This is a focused smoke test, not full-page acceptance.
- A source extraction audit found additional UI strings outside the catalog, including secondary-screen help, confirmation copy, VoiceOver labels/hints/values and remaining error messages. `RecipeCore` errors and several computed/concatenated messages still surface English. Review each affected flow and add translations without translating stable IDs, raw recipe/evidence fields, user-generated names or provider receipts.
- Recipe count and the existing numeric labels use String Catalog plural variations. Verify 0 / 1 / many for recipes and ingredients across all four locales in visible flows.
- Screenshots showed readable Chinese and Japanese glyphs on the current Lora/system fallback at the default size. A maximum accessibility text-size screenshot of first launch wrapped Chinese title and controls without visible clipping, but its explanatory feature copy fell back to English. Verify secondary pages, narrow widths, dark mode and the full Dynamic Type range.
- VoiceOver behavior and labels, permission dialogs, and changing the device language while the production app is running remain unverified. The four-language screenshot evidence is limited to the Recipes root page.
- Keep #26 open and PR #74 draft until remaining copy and accessibility coverage are translated and the full runtime checks pass.

Implementation guidance:
- [Apple: String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple: Preparing App text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)

Do not mark this app, the extra planned languages, or #26 as fully translated before these runtime checks and remaining English-key coverage are complete.
