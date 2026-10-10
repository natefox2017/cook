# Localization

> This document defines the **long-term localization contract** for Recipe Pals, not a task list or QA status report. Translation scope and ongoing acceptance are managed in [Linear DEV-88](https://linear.app/gengyun/issue/DEV-88); release evidence belongs to [DEV-49](https://linear.app/gengyun/issue/DEV-49). For typography and concise-copy requirements see [Design System](DESIGN_SYSTEM.md).

## Runtime language and region policy

- Until multilingual release is explicitly approved, the default app language is **English (`en`)** regardless of the iPhone's preferred language. Do not rewrite global `AppleLanguages` or remove translation resources to force this default.
- Currently enabled manual UI languages are `en`, `zh-Hans`, `zh-Hant` and `ja`. A supported language explicitly chosen by the user overrides the English default. An empty, unsupported or stale preference falls back to English.
- During a `--uitesting` launch, a valid `--uitesting-locale` argument has priority over manual selection; UI tests without a forced locale still respect the saved manual choice. A locale must exist in the app bundle and in `RecipeLanguage.currentlyTranslatedLanguages` to be selected.
- A production switch to automatic device-language selection needs a separate approved release decision and full language QA. Merely adding a translation must not silently change test-stage default behavior.
- Language and country/region are independent preferences. Changing country does **not** change the app's language, account country, subscription billing region or Apple's StoreKit storefront. Use locale-aware formatting, but do not equate a user country override with a billing entitlement.

### Existing implementation; no second language store

- `ios/RecipeCore/Sources/RecipeCore/RecipeLanguage.swift` owns the policy: `preferenceKey`, `currentlyTranslatedLanguages`, `selectedIdentifier`, `resolve` and `mirrorManualSelection`. The host App reads its own `UserDefaults.standard`. A Share Extension has different standard defaults and must not treat them as the host's preference.
- `ios/Recipe/RecipeApp.swift` injects the resolved locale into SwiftUI's environment and mirrors only an eligible manual language code into the existing App Group. `ios/Recipe/Features/SettingsHubView.swift` / `LocalePreferencesView` owns the existing language picker and independent `recipe.countryOverride`.
- `ios/ShareExtension/ShareViewController.swift` uses `RecipeLanguage.active`. In an `.appex`, `RecipeLanguage.selectedIdentifier` reads `UserDefaults(suiteName: RecipeShareInbox.appGroupID)`. Clearing or changing to an unsupported code removes the mirrored override; it never copies recipes, credentials or other user data into shared localization settings.
- Signed app and Share Extension builds need valid App Group provisioning for the cross-process preference to work on an actual iPhone. Source code and translation coverage are not proof of device success; integration acceptance belongs to [DEV-212](https://linear.app/gengyun/issue/DEV-212).

## String Catalog resources and shipping locales

Keep fixed UI text in Apple's existing **String Catalog** resources:

| Target | Resource path | Responsibility |
| --- | --- | --- |
| Recipe app | `ios/Recipe/Resources/Localizable.xcstrings` | Fixed screens, navigation, cooking, errors, settings, paywall, accessibility |
| Recipe app | `ios/Recipe/Resources/InfoPlist.xcstrings` | Localized bundle identity and permission reasons |
| Recipe Share Extension | `ios/ShareExtension/Localizable.xcstrings` | Sharing receipt, errors, recovery and cancellation |
| Recipe Share Extension | `ios/ShareExtension/InfoPlist.xcstrings` | Extension bundle identity |

English remains the source/fallback language. Only `en`, `zh-Hans`, `zh-Hant` and `ja` are enabled. Additional target languages include `de`, `fr`, `es`, `it`, `nl`, `pt-BR` and `ko`; partial translations are not proof of a complete or released locale.

Enabling another language requires all four relevant catalogs to cover all source strings with valid plurals and formatting; updates to `ios/Recipe/Info.plist` `CFBundleLocalizations` and necessary Extension declarations; an update to `RecipeLanguage.currentlyTranslatedLanguages`, the existing `LocalePreferencesView` picker, targeted tests and actual signed-device review. Never advertise a locale before these steps, and never delete previously supported translations. A locale's catalog contents are distinct from its effective runtime selection.

## Translation and UI text requirements

- Use localizable SwiftUI literals or `LocalizedStringKey` for fixed labels. For a dynamically produced `String`, resolve it with `String(localized: LocalizedStringResource(..., locale: RecipeLanguage.active))` to honor the explicit app locale rather than the phone language. Apply the same principle to Core/service/import error presentation and alert text.
- Keep format placeholders (`%@`, `%lld` and positional arguments), plural forms, value types and argument order correct. Use `Locale` and `FormatStyle` for times, quantities, numbers, currencies and dates; avoid string concatenation that assumes English grammar.
- Do **not** translate user-authored recipe titles, source text, original ingredients, custom names, account emails, machine-readable enum/database values, or stable English `accessibilityIdentifier` strings. Apple's localized StoreKit product names, offers and prices are not fixed app string translations.
- Localize accessibility announcements and visible actions. Validate VoiceOver, Dynamic Type, long French/German strings, CJK fallback, dark mode and native navigation. Use concise title labels such as `About`, `Help & Support` and `Premium` without redundant branding suffixes.
- Preserve complete meaning in destructive-action confirmations, subscription renewal/pricing disclosures, privacy permissions and actionable errors. Do not remove material text to satisfy an informal one-line preference. The Share Extension uses its own bundle; adding a string only to the App does not localize the Extension.

## Required checks and acceptance boundary

For a complete repository checkout, run static coverage and Core regressions:

```sh
python3 scripts/audit_localizations.py --strict
swift test --package-path ios/RecipeCore
```

The strict script audits **declared shipping locales** only; it does not certify unenabled candidate locales or UI presentation. Before enabling a new locale, compare source key coverage and placeholder/plural correctness across all four catalogs and ensure existing locales are unchanged.

On macOS with a suitable installed Simulator, use the actual Xcode scheme and destination, for example:

```sh
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO test
```

Release QA should additionally exercise a signed iPhone and hosted Share Sheet: all four tabs, onboarding, details/cooking/timers/notifications, language selection and restart, App Group mirroring, country preference independence, deletion alerts, sign-in and StoreKit, VoiceOver, Dynamic Type and dark mode. Native build, Simulator, signed-device, staging and production results are distinct; CI/PR merge does not equal real-device or release acceptance.

Record actual test commands, source revision, test fixtures, environment, PASS/FAIL/NOT RUN and evidence **in [DEV-88](https://linear.app/gengyun/issue/DEV-88) or [DEV-49](https://linear.app/gengyun/issue/DEV-49)**. Never maintain transient test results, screenshots, bug inventories or task checklists in this specification.
