# Localization

Updated: 2026-10-08

## Runtime policy

- **Temporary test-stage setting (2026-10-08):** RecipePouch app UI is forced to English (en), regardless of the iPhone's preferred language. This applies to the SwiftUI environment and computed strings resolved with `LocalizedStringResource(locale:)`.
- Explicit `--uitesting-locale en|zh-Hans|zh-Hant|ja` is retained solely for localization smoke tests; ordinary UI tests and normal app launches default to English.
- The Share Extension uses its own English locale. Core display errors remain in English during the test stage.
- **Before international launch:** deliberately remove this test-stage restriction and restore system-language selection for the app, Core, and Share Extension after multi-language visual QA.
- English remains the development/source language; translation catalogs are retained.

## Launch locales

Initial targets: English (en), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant), Japanese (ja), Spanish (es), French (fr), German (de), Korean (ko), Brazilian Portuguese (pt-BR).

## 2026-10-08 localization and concise-copy maintenance

- The main app must use a localized key when a shared SwiftUI row receives product copy through a runtime `String`. Raw `Text(title)` or `Button(mode.rawValue)` is not equivalent to a localizable literal. Use `LocalizedStringKey` for fixed UI copy and `String(localized:)` when a computed String is required. Keep user-authored recipe names, email addresses, account data and StoreKit product metadata unchanged.
- Profile uses short navigation titles **Account** and **Premium** without a repeated RecipePouch prefix. The uncustomized kitchen name is localized. Additional account, recipe editor, grocery, cooking and onboarding dynamic labels were routed through the catalogs.
- Redundant informational footnotes, duplicate read-only settings rows and long marketing subtitles were removed from common screens. Necessary statuses are short, ideally one line; preserve important data-deletion warnings, privacy notices and App Store renewal disclosure rather than obscuring essential terms.
- The Share Extension now has its **own** catalog, `ios/ShareExtension/Localizable.xcstrings` (11 source keys, zh-Hans/zh-Hant/ja), included in the `RecipeShare` target's Resources phase. The app catalog alone does not localize this separate extension bundle.
- UI assertions cover localized Profile defaults, Account and Premium menu labels in the four shipping locales and retain stable accessibility identifiers. This code-only pass verified catalog JSON completeness and static Swift delimiter balance; **Xcode build, iPhone/simulator screenshots, VoiceOver and exhaustive view-state runtime tests have not been executed in this environment**. Complete these before release.

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

**The four-language catalog is implemented, with full-page acceptance still in progress.**

- `ios/Recipe/Resources/Localizable.xcstrings` contains **670 source keys**; each key has zh-Hans, zh-Hant and ja values, including plural variants. The keys cover Recipes, recipe details/editing, import, Collections, groceries, meal planning, cooking, profile, Settings, account, subscription, cloud sync, privacy and help. English uses source values as the fallback. `InfoPlist.xcstrings` contains the camera permission string and app display/name values for all four locales.
- Both catalogs are registered in the **Recipe** app target. Xcode 27 built the target successfully for the iOS 27 simulator, compiling its String Catalogs. The Xcode localization export extracted additional literals and surfaced 111 non-literal extraction warnings; a source scan localized concrete dynamic/composed copy and user-visible service/core errors. Keep reviewing new UI copy as adjacent features change.
- `ios/Recipe/Info.plist` advertises only en, zh-Hans, zh-Hant and ja. es/fr/de/ko/pt-BR remain planned and are intentionally not advertised.
- UI tests keep English by default. The locale smoke explicitly passes `--uitesting-locale` for four deterministic locales. `RecipeApp.appLocale` is temporarily pinned to English in normal launches. Locale smoke tests must explicitly opt in; switching languages while running has not been verified.
- `String(localized:)` and `LocalizedStringKey` are used for composed/dynamic display copy and enum-backed labels. Accessibility identifiers, persistence values, user recipe/source text, custom collection names and StoreKit prices remain unchanged.

**Runtime evidence collected**

- `xcodebuild ... build` succeeded for `Recipe` on the `Recipe PR74 QA` iOS 27 simulator, including both catalogs.
- `testFourLocaleTabLabelsUseStringCatalog` passed for en, zh-Hans, zh-Hant and ja, checking the Recipes tab, localized recipe-count noun, Settings title and RecipePouch Account row. Four Settings screenshots show Lora Latin with system CJK glyph fallback and no visible clipping at the default size. Screenshot evidence is in `.tmp/pr74/screenshots/final-4-locale/` (temporary, untracked).
- `swift test --package-path ios/RecipeCore` ran 70 tests: 69 passed; `structuredStepsExtractExplicitCookingSignalsWithoutGuessing` failed because the roast fixture produced `[1200]` instead of `[1200, 600]`. This parser test is outside this localization change and should be tracked separately.

**Remaining for #26 / #33**

- The full UI suite is not accepted: an earlier run on the existing QA simulator had 10 failures, including one cooking-flow assertion and subsequent simulator install-coordination failures. A focused locale smoke passes on the isolated simulator.
- `testSettingsRemainReachableAtAccessibilityDynamicType` passed its navigation/button assertions at accessibility-extra-extra-extra-large. The screenshot shows long row labels wrapping inside words, including a one-character line break; this is a visual failure. UI-009 approves copy reduction only and forbids layout changes, so the row layout needs a confirmed accessibility-size design before implementation.
- VoiceOver was not operated directly. The XCTest accessibility tree found localized row labels as buttons, but this does not prove VoiceOver navigation quality. Permission prompts, dark mode, the complete Dynamic Type range, and production locale changes remain unverified.
- Not every secondary-page state has four-locale screenshot coverage. Continue checking empty/loading/error/disabled states and plural values in their visible flows. Do not interpret catalog key coverage as proof of every runtime path.
- Historical work tracked in #26 and #33 may be marked closed in GitHub; their older QA evidence is not proof that this new branch was built. Finish native accessibility and end-to-end checks before release.

Implementation guidance:
- [Apple: String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple: Preparing App text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)

Do not mark the additional planned languages or the current branch as fully verified until native build and per-page locale checks are complete.
