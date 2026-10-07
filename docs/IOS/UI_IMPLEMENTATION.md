# UI implementation — 2026-10-07

## Scope and authorization

The user requested: “你帮我把 ui 界面功能写好提交上去”. This authorizes implementing and submitting this UI work. It does not retrospectively approve every historical design frame or authorize merging unrelated pending PRs.

This change starts from main commit `3df9064aebb70526d15592763b9b85dff1e7f1ed`, follows V1 Recipes / Groceries / Profile navigation and the saved Cook design resources. It reuses PR #10's IngredientAmount implementation and tests. The five-entry recommendation home is not added to the three-tab baseline.

Historical PENDING rows remain unchanged. This PR provides the concrete implementation for review; future visual changes continue to use the existing design process.

## Implemented client paths

| Area | Actual behavior |
| --- | --- |
| Recipes | Persistent library; search titles/ingredients/steps/notes; categories, favorites, needs-review; sorting; stable-ID navigation; empty and no-result states; explicit samples. |
| Details | Recipe content and source; full ingredients/steps; quantities; favorites; editing; confirmed deletion; selected ingredients and portions to groceries. |
| Editing | Value draft; title and numeric validation; arbitrary amount wording preserved; ingredients/steps/photos/notes; original source retained; ready or needs-review save; discard confirmation. |
| Web import | HTTPS, bounded size/time, redirect URL checks; actual Schema.org Recipe extraction; source deduplication; failures offer retaining the link and adding details. |
| Text/documents | Explicit ingredient/instruction headings; complete original text; plain text and selectable-text PDF; explicit limits; unstructured text stays a draft. |
| Photos | System Photos picker and camera permission; local Apple Vision OCR; selected photo retained when recognition is incomplete; no invented quantities or steps. |
| Cooking | Full-screen steps; previous/next/finish; ingredients and portions; deadline-based start/pause/reset; saved sessions; optional authorized notifications; keep-awake restored on exit. Expiry does not advance a step. |
| Groceries | Category groups and collapse; All/To buy/Bought; actual counts; checked state; manual add/edit; source references; confirmed delete/clear. Only compatible explicit amounts merge. |
| Meal plan | Week/date and breakfast/lunch/dinner slots; choose saved recipes, confirm replacement, view and remove meals. |
| Profile | Local name/email, appearance, keep-awake, actual notification permission, help, version, JSON export and confirmed local reset. No fictitious account. |

## Persistence and failures

CookStore owns one versioned Codable snapshot in application support. Each mutation validates a copy, atomically writes it, then publishes the observable state. Write failures do not publish unsaved changes. An unreadable/unsupported file stays in place and blocks further writes, including reset; retry reloads it.

Original sources and unknown amounts remain intact. Explicit quantities use Decimal and the existing safe amount helper. Ranges and “to taste” remain textual; inexact ratios are expressed rather than fabricated as long decimals. Unit spellings are not silently converted. Recipe deletion cleans plan entries and grocery source references but retains grocery tasks.

Data is local to this installation. JSON export is user-driven; cloud backup and JSON restoration are not claimed.

## Design and accessibility

- SwiftUI navigation and tab bars retain tab history and platform safe areas. iOS 26 uses system Liquid Glass; iOS 18 uses the older native appearance.
- Warm cream surfaces, green actions and rounded food photos; glass is reserved for navigation and small controls.
- Source Sans 3 is bundled with its OFL license. Larger accessibility text switches the grid to one column. Controls have meaningful labels and practical touch areas.
- Clearly labeled sample recipes reuse existing design photography. User imports never receive invented sample imagery.
- Native screenshots, animation, signing and VoiceOver acceptance require an actual Xcode run; static inspection cannot prove them.

## Build and validation

The native `ios/Cook.xcodeproj` contains App and UI-test targets, a local CookCore package and shared Cook scheme. No generator or additional UI framework is required.

```sh
swift test --package-path ios/CookCore
xcodebuild -project ios/Cook.xcodeproj -scheme Cook \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  -resultBundlePath TestResults/Cook.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

iOS CI now runs these commands instead of the prior echo-only placeholder. The result bundle retains UI screenshots. Core tests cover persistence, write failure, corrupt files, favorites/shopping/plans, source preservation, ambiguous quantities, scaling, timer recovery and parser variants. UI tests exercise navigation, shopping, manual creation/search and cooking controls.

Local inspection checked resource paths, plist/XML syntax, font names, images and whitespace. The PR's macOS check is authoritative for compilation/simulator status; queued or failed checks are not passes.

CI uses its available iPhone 17 Pro Max / iOS 26.2 simulator. The requested iPhone 18 Pro Max remains a device-specific visual acceptance target and is not claimed as tested here. Physical installation requires selecting a development team; no signing identity is guessed.

## Integration boundaries

This delivers the native UI and local client. It does not deploy Supabase or replace the pending backend import contract. Authentication, cross-device sync, social-video/audio AI extraction, durable background workers and the iOS Share Extension remain integration tasks. No credentials or production endpoints are guessed.

The webpage adapter reads public recipe markup, does not pass paywalls/sign-in walls, and does not advertise universal social-platform support. It rejects non-HTTPS, credentials, custom ports and obvious local/IP URL forms and checks redirects. It is not the production server's complete SSRF/DNS policy. The future worker still requires the protections in ARCHITECTURE.md and the import-contract review.

## External references

Established products repeat collect → find → cook/shop; they informed the functional checks:

- [Paprika's iOS guide](https://www.paprikaapp.com/help/ios/): editing, portions, ingredient selection, groceries and cooking.
- [ReciMe's getting-started guide](https://recime.app/help/en/articles/11596272-how-can-i-get-the-most-out-of-recime): importing, collections, groceries and servings.
- [Apple NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) and [persistent storage](https://developer.apple.com/documentation/swiftui/persistent-storage): native navigation and persistence.
- [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): native functional layers and compatibility.
- [Schema.org Recipe](https://schema.org/Recipe) and [recipe-scrapers](https://docs.recipe-scrapers.com/getting-started/advanced-usage/): structured data shapes; the Python scraper framework is not added as a client dependency.
- [GitHub macOS 26 inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md): the actual Xcode and simulator combination.
