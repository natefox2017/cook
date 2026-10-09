# Recipe — Agent Instructions

Use this file as the repository-wide guide for coding agents. Keep changes scoped to the user's request, preserve unrelated work, and follow the current project documentation.

## Naming Contract

- The technical project, Xcode project, target, Swift module, shared package, folders, files, and code identifiers use **Recipe** naming.
- The user-facing product brand is **Recipe Pals**. Technical names and legacy data identifiers keep their existing compatibility contracts.
- Primary paths are:
  - `ios/Recipe.xcodeproj`
  - `ios/Recipe/`
  - `ios/RecipeCore/`
  - `ios/RecipeUITests/`
  - `ios/ShareExtension/`
- Do not create new `Cook*` technical types, targets, modules, source folders, or filenames.
- Preserve compatibility for existing users. Legacy bundle identifiers, URL schemes, persisted files, and `cook.*` keys may be read or migrated when changing them would lose existing data or break deployed integrations.
- New local preference/session keys use the `recipe.*` namespace. Migration code must continue to understand supported legacy `cook.*` values.

## Project Overview

Recipe is the native iOS codebase for Recipe Pals, a private recipe collection and cooking app. V1 focuses on collecting recipes from third-party sources, organizing them privately, and using them for cooking, shopping, and simple meal planning. The backend uses Supabase for authenticated sync and asynchronous import services.

## Source of Truth

Read the relevant documents before substantial product or architecture changes:

- `docs/PRODUCT_BASELINE_V1.md` — product scope and priorities
- `docs/USER_FLOWS.md` — user journeys
- `docs/DESIGN_SYSTEM.md` — visual direction and UI conventions
- `docs/ARCHITECTURE.md` — system boundaries
- `docs/RECIPE_IMPORT_PIPELINE.md` — import lifecycle
- `docs/DATA_MODEL.md` — data model
- `docs/DEVELOPMENT_STANDARD.md` — collaboration and delivery conventions

`docs/UI_DESIGN_APPROVALS.md` records UI directions and decisions. It is not a separate development gate when the user has directly requested implementation. Follow the user's current explicit instructions when they supersede older documentation.

## Code Style and Comments

- **Never compress Swift declarations, view builders, closures, or control flow onto one line.** Source must remain readable in a normal code review.
- Format all touched Swift before committing. Prefer standard Swift formatting: 4-space indentation, one declaration or statement per line, readable trailing closures, and wrapped argument lists when they become long.
- Every Swift source/test file must begin with a short English file header:
  - `// Developer: gengyun`
  - `// Purpose: <one concise sentence describing the file>`
- Comments must be written in English.
- Add comments for non-obvious invariants, compatibility migrations, security boundaries, concurrency, persistence, and intentionally conservative parsing. Do not narrate obvious syntax.
- Public or shared APIs should use descriptive identifiers and concise documentation comments when behavior is not self-evident.
- Do not use mass comments as a substitute for clear names and structure.
- When touching previously minified code, expand and format the entire affected declaration/file rather than adding more compact code around it.

## Product Rules

- The normal collection flow is: share from a third-party app, choose Recipe Pals, receive an acknowledgment, and return to the source app.
- The Share Extension receives and queues input, then finishes promptly. It must not wait for full parsing or AI processing.
- Import complete information automatically. Send only missing, anomalous, or low-confidence fields to a review flow.
- Keep manual recipe entry as a fallback.
- Preserve original source URL, source platform, and available author/title metadata.
- Do not add a community feed, public posts, follows, likes, comments, creator profiles, or a public recipe marketplace to V1.
- Never turn vague amounts such as “to taste,” “a little,” “about,” or “unknown” into invented exact values.

## Architecture and Code Boundaries

- iOS app and Share Extension: SwiftUI and native iOS APIs.
- Backend: Supabase Postgres, Edge Functions, Storage, and Queues/pgmq.
- AI providers are called by the backend through an OpenAI-compatible provider layer. Never put provider secrets or service-role keys in the client.
- Do not introduce a second UI framework, database, or queue unless the task explicitly requires it.
- Keep imports asynchronous and idempotent. Preserve partial results and source evidence when parsing fails.
- Validate fetched URLs and redirects; protect import services from SSRF, private-network access, oversized downloads, and excessive processing time.

## Repository Map

- `ios/Recipe/` — iOS app, screens, design helpers, and services
- `ios/RecipeCore/` — shared domain models and local persistence
- `ios/RecipeUITests/` — native UI regression tests
- `ios/ShareExtension/` — native share extension
- `supabase/` — backend configuration, migrations, and functions
- `docs/` — product, design, architecture, and implementation references

## Change Workflow

- Keep `main` PR-only. Use a focused branch for implementation.
- **Before a PR, rebase/merge the current `origin/main`** and compare against the latest accepted onboarding, branding, navigation and purchase contracts. Do not restore older screen implementations from an old branch merely to resolve conflicts.
- **Create a regular (non-Draft) PR after the task is complete.** Our trusted GitHub Actions workflow merges ordinary clean same-repo PRs automatically, with no GitHub UI click. Do not ask the user to press **Ready for review** for completed work.
- Draft PRs are only for genuine work in progress. If a completed PR was already opened as Draft, append the exact completion marker `<!-- auto-ready: complete -->` to its PR body, or apply the `auto-ready` label; the workflow promotes it and merges it without a manual UI click. Do not set either marker before work is complete.
- Do not overwrite an approved design with copy/layout taken from stale history. The first onboarding story remains **OnboardingAI / Create with AI** and Premium retains the AI feature row unless the user expressly approves a change. The merge workflow blocks those regressions and obsolete user-facing RecipePouch naming.

- GitHub Issues are the project task entry point. Keep issue status aligned with the actual merged code.
- Freeze shared API/schema decisions before parallel work; avoid simultaneous edits to the same core file.
- Inspect the current implementation before changing it. Do not apply review comments mechanically.
- Make the smallest safe change that satisfies the request. Preserve existing behavior and user data.
- Do not remove failing tests just to make checks pass. Do not commit secrets, access tokens, passwords, or private credentials.
- Keep UI changes consistent with `docs/DESIGN_SYSTEM.md` and the existing app.
- User-facing copy follows product language/localization rules. Source identifiers and technical documentation use consistent Recipe naming.

## Language During Development

- Until the user explicitly approves multilingual release, default to English for all user-facing Recipe Pals UI regardless of the iPhone's preferred language.
- Keep four-language String Catalogs intact. Only explicit UI-locale smoke-test launch arguments may select a non-English locale.
- When computing displayed strings, use a `LocalizedStringResource` with the app's explicit locale. A bare `String(localized:)` can fall back to the device language even when SwiftUI's locale is overridden.
- Do not globally override system `AppleLanguages` or remove translation resources as a test shortcut.

## CI Policy

- Keep CI intentionally minimal.
- The private GitHub Free repository uses one lightweight trusted merge workflow to squash-merge eligible normal PRs directly; marked-complete Drafts may be promoted automatically. Never use `gh pr merge --auto`, which depends on paid native auto-merge protection.
- Keep unmarked Draft PRs, change requests, unresolved review threads, and unmergeable PRs out of automatic merges. Do not check out or execute PR code with the write-enabled merge token. The merge workflow validates approved UI and naming contracts by treating PR-head files as **untrusted data** and executing only trusted-base validators.
- Do not reintroduce per-PR Xcode builds, simulator runs, Swift tests, or documentation CI unless the user explicitly requests them.
- Required status names may remain as compatibility gates, but they must not pretend to validate work they do not actually validate.
- Run substantive build/tests manually when needed and report exactly what was executed.

## Build and Verification

Core tests:

```sh
swift test --package-path ios/RecipeCore
```

iOS simulator tests:

```sh
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO test
```

For UI changes, inspect the affected flow in a simulator when the environment permits. The minimum deployment target is iOS 18.0. Do not claim simulator, signing, backend, StoreKit, or end-to-end verification based only on static source review.
