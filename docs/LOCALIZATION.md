> **Latest source audit (2026-10-09):** `ios/Recipe/Resources/Localizable.xcstrings` has **808 source keys** with zh-Hans/zh-Hant/ja localizations; Share Extension has 14. The older 670-key count and prior RecipePouch screenshots below are historical acceptance records, **not the current source contract**. English remains the default during testing; StoreKit and user-authored content are outside translated fixed UI labels.

# Localization

Updated: 2026-10-09

## Runtime policy

> **Scope separation (updated 2026-10-10):** [#230](https://github.com/natefox2017/cook/issues/230) now has a partially implemented manual App language and country preference. Manual choice works for the four bundled languages and takes priority over the test-stage English default; automatic system-language selection and further European/American/Korean translations remain pending. Choosing a country does not change the UI language or App Store billing region. New UI copy from #231–#248 also needs extraction/QA.



- **Temporary test-stage setting (updated 2026-10-10):** With no manual selection, Recipe Pals defaults to English (en) regardless of the iPhone's preferred language. The explicitly saved four-language choice overrides this default in the SwiftUI environment and in computed strings using `LocalizedStringResource(locale:)`.
- Explicit `--uitesting-locale en|zh-Hans|zh-Hant|ja` has highest priority for deterministic localization smoke tests. UI tests without that flag allow manual changes; they default to English when no choice was saved.
- The Share Extension owns a separate four-language catalog (en, zh-Hans, zh-Hant, ja). Its default remains English during testing; when a user explicitly selects a supported language in the main App, the App mirrors only that language identifier into its existing App Group defaults. The Extension reads that shared value rather than its isolated standard defaults; clearing the choice returns the Extension to English. This requires valid signing and App Group provisioning on a real iPhone. See [DEV-212](https://linear.app/gengyun/issue/DEV-212); no unreleased language is enabled.
- **Before international launch:** deliberately remove this test-stage restriction and restore system-language selection for the app, Core, and Share Extension after multi-language visual QA.
- English remains the development/source language; translation catalogs are retained.

## Launch locales

Initial targets: English (en), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant), Japanese (ja), Spanish (es), French (fr), German (de), Korean (ko), Brazilian Portuguese (pt-BR).

## 2026-10-08 localization and concise-copy maintenance

- The main app must use a localized key when a shared SwiftUI row receives product copy through a runtime `String`. Raw `Text(title)` or `Button(mode.rawValue)` is not equivalent to a localizable literal. Use `LocalizedStringKey` for fixed UI copy and `String(localized:)` when a computed String is required. Keep user-authored recipe names, email addresses, account data and StoreKit product metadata unchanged.
- Profile uses short navigation titles **Account** and **Premium** without a repeated Recipe Pals prefix. The uncustomized kitchen name is localized. Additional account, recipe editor, grocery, cooking and onboarding dynamic labels were routed through the catalogs.
- Redundant informational footnotes, duplicate read-only settings rows and long marketing subtitles were removed from common screens. Necessary statuses are short, ideally one line; preserve important data-deletion warnings, privacy notices and App Store renewal disclosure rather than obscuring essential terms.
- The Share Extension now has its **own** catalog, `ios/ShareExtension/Localizable.xcstrings` (11 source keys at this historical update; **14 in current main**, zh-Hans/zh-Hant/ja), included in the `RecipeShare` target's Resources phase. The app catalog alone does not localize this separate extension bundle.
- UI assertions cover localized Profile defaults, Account and Premium menu labels in the four shipping locales and retain stable accessibility identifiers. This code-only pass verified catalog JSON completeness and static Swift delimiter balance; **Xcode build, iPhone/simulator screenshots, VoiceOver and exhaustive view-state runtime tests have not been executed in this environment**. Complete these before release.

## 2026-10-09 localization source sweep

- Rebased the sweep on the latest `main` timer changes; the iOS app String Catalog now has **808** source keys, each with Simplified Chinese, Traditional Chinese and Japanese values. The Share Extension has **14** translated keys, including shared-storage errors.
- Covered new authentication code actions, empty states, cooking timers, groceries, collection views, recipe editor, subscription statuses, cloud/import/Core errors, accessibility labels and portable HTML export headings.
- Runtime-generated Core/service strings are looked up in the host app or Share Extension catalog with `RecipeLanguage.active`, preventing device-language fallback during the English-only testing stage. Static multi-branch SwiftUI labels now pass `LocalizedStringKey` explicitly.
- Existing user recipe text, persisted enum identifiers, source metadata, StoreKit names/prices and backend technical content are not automatically translated. The separate internal `admin/` React tool is outside the documented iOS localization targets.
- **Verification performed:** JSON parsing, all three locale values present, and placeholder-count checks. **Not run in this environment:** native Xcode/SwiftUI build, simulator locale screenshots, accessibility testing, Share Extension host testing, subscription checkout or export display QA. Complete those before claiming international-release readiness.

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

- `ios/Recipe/Resources/Localizable.xcstrings` contains **808 source keys**; each key has zh-Hans, zh-Hant and ja values, including plural variants. The keys cover Recipes, recipe details/editing, import, Collections, groceries, meal planning, cooking, profile, Settings, account, subscription, cloud sync, privacy and help. English uses source values as the fallback. `InfoPlist.xcstrings` contains the camera permission string and app display/name values for all four locales.
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

## Manual preferences (partial #230, 2026-10-10 source only)

The Settings hub now exposes **Language & Country**. The user-selected language
override changes the SwiftUI environment and the `RecipeLanguage.active` used by
locally formatted alerts, preserving explicit UI-test locale flags. Ordinary
test-stage default remains English; supported manual UI languages are limited to
the currently bundled en, zh-Hans, zh-Hant, ja catalogs. An unsupported locale is
never advertised as translated and safely falls back to English.

The country/region preference uses ISO regions but is separate from language and
is not a claim to change Apple/App Store billing region or content restrictions.
Additional European, American and Korean language packs, strings translation
quality, country-specific units/terms and real-device smoke remain **OPEN #230**.

## Destructive alerts and manual-language behavior (2026-10-10)

- Both local-delete entry points (Profile and Settings → Data & Privacy) and
  signed-in account/cloud deletion now use native centered SwiftUI alerts with
  an explicit Cancel action, rather than container-attached action sheets.
  The local-delete flow still requires confirmation and warns about local
  versus cloud data and subscription preservation.
- Settings → Language & Country uses a navigation-style language picker.
  Saving a choice changes the UI locale and `RecipeLanguage.active`; the
  setting persists across regular launches. In a `--uitesting` run, an
  explicit `--uitesting-locale` continues to take priority; without it, the
  user's manual choice applies. `--uitesting-reset-language` is a DEBUG-only
  test fixture reset, not a production setting.
- Source checks and UI regression cases were added for native alert placement,
  cancellation and the manual-selection path. **An iOS simulator/device run is
  still required**; a source-level test is not confirmation of rendered layout.
