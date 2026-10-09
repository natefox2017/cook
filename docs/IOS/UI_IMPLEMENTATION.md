# UI implementation — 2026-10-07

## Scope and authorization

> **2026-10-09 current UI contract:** first-launch page 1 is AI-first (`OnboardingAI`, `Create with AI`); Premium has a left-aligned AI feature and uses Recipe Pals naming. PR #226 restored this after PR #223 temporarily replaced it. New implementation must not rely on stale draft/screenshots without reading the current main and approved UI records.

The user requested: “你帮我把 ui 界面功能写好提交上去”. This authorizes implementing and submitting this UI work. It does not retrospectively approve every historical design frame or authorize merging unrelated pending PRs.

The current implementation uses the `Recipe` technical project/module naming and the **Recipe Pals** user-facing product brand, with Recipes / Plan / Groceries / Profile navigation. It reuses PR #10's IngredientAmount implementation and tests. The historical three-tab proposal was superseded by the four-tab native navigation; the extra recommendation home was not added.

Historical PENDING rows remain unchanged. This PR provides the concrete implementation for review; future visual changes continue to use the existing design process.

## Implemented client paths

| Area | Actual behavior |
| --- | --- |
| Recipes | Persistent library; search titles/ingredients/steps/notes; categories, favorites, custom Collections, needs-review; sorting; stable-ID navigation; empty and no-result states; explicit samples. |
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

RecipeStore owns one versioned Codable snapshot in Application Support. Existing installs are migrated from the legacy `Cook/library.json` location to `Recipe/library.json` without deleting the source file. Each mutation validates a copy, atomically writes it, then publishes the observable state. Write failures do not publish unsaved changes. An unreadable/unsupported file stays in place and blocks further writes, including reset; retry reloads it.

Original sources and unknown amounts remain intact. Explicit quantities use Decimal and the existing safe amount helper. Ranges and “to taste” remain textual; inexact ratios are expressed rather than fabricated as long decimals. Unit spellings are not silently converted. Recipe deletion cleans plan entries and grocery source references but retains grocery tasks.

The local library remains authoritative offline. Supabase snapshot synchronization is implemented at the client service boundary but awaits real two-account/device acceptance (#29/#34). Portable JSON + offline HTML recipe export and a full local snapshot JSON option are available; none is a user-restorable in-app backup.

## Design and accessibility

- SwiftUI navigation and tab bars retain tab history and platform safe areas. iOS 26 uses system Liquid Glass; iOS 18 uses the older native appearance.
- Warm cream surfaces, green actions and rounded food photos; glass is reserved for navigation and small controls.
- **Current font implementation uses Lora** (`Lora-Regular` for titles, body, controls, UIKit navigation and tabs; `Lora-Variable.ttf` is registered in Info.plist). Older Source Sans 3 documentation predates later typography changes. Do not restore Source Sans 3 without the user's explicit direction or a current approved reference.
- Larger accessibility text switches the grid to one column. Controls have meaningful labels and practical touch areas. Four-language text/typography acceptance is still pending #26/#33.
- Clearly labeled sample recipes reuse existing design photography. User imports never receive invented sample imagery.
- Native screenshots, animation, signing and VoiceOver acceptance require an actual Xcode run; static inspection cannot prove them.

## Build and validation

The native `ios/Recipe.xcodeproj` contains App and UI-test targets, a local RecipeCore package and shared Recipe scheme. No generator or additional UI framework is required.

```sh
swift test --package-path ios/RecipeCore
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  -resultBundlePath TestResults/Recipe.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

These commands are manual verification commands. Repository CI is intentionally limited to lightweight PR auto-merge compatibility statuses and does not run Xcode, Simulator, Swift Test, or documentation validation. Never treat the CI gate as proof that the app compiled or passed UI tests.

Core/UI test files remain in the repository for manual or release validation. Simulator/device results must be reported only when actually executed. Physical installation requires selecting a development team; no signing identity is guessed.

## Integration boundaries

This delivers the native UI and local client. It does not deploy Supabase or replace the pending backend import contract. Production verification for authentication, cross-device sync/conflict resolution, social-video/audio AI extraction, durable background workers, and the iOS Share Extension remains integration work tracked by the release Issues. No credentials or production endpoints are guessed.

The webpage adapter reads public recipe markup, does not pass paywalls/sign-in walls, and does not advertise universal social-platform support. It rejects non-HTTPS, credentials, custom ports and obvious local/IP URL forms and checks redirects. It is not the production server's complete SSRF/DNS policy. The future worker still requires the protections in ARCHITECTURE.md and the import-contract review.

## External references

Established products repeat collect → find → cook/shop; they informed the functional checks:

- [Paprika's iOS guide](https://www.paprikaapp.com/help/ios/): editing, portions, ingredient selection, groceries and cooking.
- [ReciMe's getting-started guide](https://recime.app/help/en/articles/11596272-how-can-i-get-the-most-out-of-recime): importing, collections, groceries and servings.
- [Apple NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) and [persistent storage](https://developer.apple.com/documentation/swiftui/persistent-storage): native navigation and persistence.
- [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): native functional layers and compatibility.
- [Schema.org Recipe](https://schema.org/Recipe) and [recipe-scrapers](https://docs.recipe-scrapers.com/getting-started/advanced-usage/): structured data shapes; the Python scraper framework is not added as a client dependency.
- [GitHub macOS 26 inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md): the actual Xcode and simulator combination.
