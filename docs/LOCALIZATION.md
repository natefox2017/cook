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

## Translation status

The application is configured for multilingual shipping and device-language selection. Existing English UI strings remain the fallback/source language. Full human-reviewed translations for every key are a release-content task; a declared locale must not be marketed as fully translated until string-catalog coverage and visual QA pass.
