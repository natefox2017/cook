> **2026-10-09 source/status note:** This is an original V1 implementation checklist, **not a live open-Issue list or release PASS**. Product branding is Recipe Pals, the approved AI-first onboarding was restored (#226), and the new **not yet implemented** AI conversation/edit, owner-consented single-recipe Web sharing, referral tracking, optional metadata and detail redesign are in [ROADMAP.md](ROADMAP.md) (#238–#248). Test-stage ordinary launches stay English; #230 controls future language/country selection. Latest issue inventory: [dated snapshot](DEVELOPMENT/CURRENT_BACKLOG_2026-10-09.md), selected-release gate #251.

# Recipe Pals V1 Product Completeness — Historical Implementation Checklist

Updated: 2026-10-09

## Product benchmark

RecipePouch is a private recipe utility: collect → organize → cook → shop → plan → sync. It does not add a public feed in V1.

Repeated patterns verified in established products:
- ReciMe: account login, multi-device recipe sync, mobile subscription, subscription status and Restore Purchase; recipe import, cookbooks, groceries and meal planning.
- Paprika: account creation/login before cloud sync; recipes, grocery lists and meal plans sync; recipe → meal planner and grocery workflows.
- Recipe Keeper: private recipe library, importing, scaling, shopping and meal planning remain the reference feature family already recorded in this repository.

## Required V1 surfaces

### 1. First launch / account
Required:
- Welcome/value proposition.
- Sign in with Apple.
- Email sign up, email sign in, forgot password.
- Explicit account identity: do not create a second account when the user meant to sign in.
- Sign out.
- Delete account and server data.
- Local data migration/linking decision when signing in on a device that already has local recipes.
- Auth errors, offline state, cancelled Apple sign-in, email verification state.

Implementation status: **IMPLEMENTED at the client/service boundary**. Email auth, password recovery, Sign in with Apple, sign-out, and account UI are wired to Supabase Auth. Production provider/delivery acceptance remains #27/#34.

### 2. Subscription
Required:
- Paywall with current App Store product names/prices/trial terms loaded from StoreKit, never hard-coded.
- Subscribe through App Store.
- Restore Purchases.
- Subscription status: active/trial/expired/not subscribed.
- Manage Subscription deep link/system sheet.
- Entitlement refresh on launch, foreground, purchase and restore.
- Account/entitlement linking must distinguish app account from Apple purchase account.
- Purchase pending/cancelled/failed and restore-no-purchase states.
- Core user data must remain readable when premium expires; premium-only creation/import limits may be enforced by product policy.

Implementation status: **IMPLEMENTED at the StoreKit client boundary**. Product loading, purchase, entitlement refresh, restore, and Manage Subscription are present; real App Store product/offer acceptance remains #28/#34.

### 3. Recipe library
Required:
- Persistent library, search, filters/categories, favorites, sorting, empty/no-result/loading/error states.
- Search title, ingredients, steps and notes.
- Open recipe detail.
- Collections/cookbooks are P0 in the existing product overview and need a concrete UI/data model if retained in V1.

Implementation status: **IMPLEMENTED locally**, including custom Collections/cookbooks with stable IDs, multi-membership, Favorites independence, persistence, filtering, and JSON export. Remote Collection sync remains part of #29.

### 4. Add/import
Required:
- URL import.
- Manual recipe.
- Photo/camera OCR.
- Selectable-text document/PDF.
- Clipboard/text import.
- Keep source and partial result when extraction is incomplete.
- Duplicate source handling.
- Share Extension: third-party app → Share → Recipe Pals → durable receipt → return immediately.
- Social source backend fallback (caption/article/ASR/OCR/visual evidence) without fabricating quantities.

Implementation status: local URL/text/photo/PDF/manual flows, an embedded Share Extension with durable local receipts, an authenticated import-job API, the queue worker and private artifact upload/download are **IMPLEMENTED IN MAIN** (including merged PRs #72, #73, #96 and #97). This establishes code boundaries, **not production acceptance**: signed host-app device tests, deployed queue/storage lifecycle, protected social-video extraction and full end-to-end processing remain unverified or incomplete.

### 5. Recipe detail/edit
Required:
- Ingredients, steps, notes, source, favorite, edit/delete.
- Safe serving scaling without inventing unknown quantities.
- Add selected ingredients to groceries.
- Add recipe directly to meal plan.
- Start cooking.
- Preserve user-confirmed edits over later background parsing.

Implementation status: client UI is **IMPLEMENTED**; server precedence is **NOT IMPLEMENTED**.

### 6. Cooking
Required:
- Focused full-screen mode.
- Previous/next/finish.
- Ingredient checklist with state retained during the cooking session.
- Serving adjustment.
- Step timers start/pause/reset; background deadline; optional notifications; expiry does not auto-advance.
- Restore interrupted session.
- Optional keep-screen-awake.

Implementation status: **IMPLEMENTED locally**.

### 7. Groceries
Required:
- Add from recipe and manually.
- Preserve source recipe references.
- Safe consolidation only for compatible explicit quantities.
- Category/aisle grouping, to-buy/bought filtering, edit/delete/clear.
- Add planned meals to groceries.
- Custom aisle ordering is post-V1 unless explicitly promoted.

Implementation status: **IMPLEMENTED locally**, except one-tap weekly-plan aggregation should remain covered by acceptance tests.

### 8. Meal plan
Required:
- Week/day navigation.
- Breakfast/lunch/dinner slots.
- Add/change/remove saved recipe.
- Open planned recipe.
- Recipe detail → plan.
- Plan → groceries.

Implementation status: **IMPLEMENTED locally**.

### 9. Profile/settings/data
Required:
- Account identity and sync status when authenticated.
- Subscription status/manage/restore.
- Notifications permission/status.
- Appearance and cooking keep-awake.
- Export local/user recipe data.
- Delete local data.
- Delete account/server data.
- Help/privacy/about/version.

Implementation status: local settings, JSON/HTML export, two local-data deletion entry points, account Auth UI, Cloud Sync UI and StoreKit purchase/restore/manage surfaces are **IMPLEMENTED IN CLIENT CODE**. The Supabase `delete-account` Edge Function is deployed. None of these are equivalent to an accepted production flow: real Apple/email provider, subscription purchase, cloud deletion and device tests remain #27–#29/#34; interrupted local erase safeguards were merged in PR #66, but interrupted-device and two-account validation remains outstanding.

### 10. Cloud sync
Required:
- Supabase Auth + RLS owner isolation.
- Recipes, groceries and meal plan sync.
- Last-sync/error status and retry.
- Offline local edits with deterministic conflict policy.
- Account deletion.
- Never put service role/provider secrets in the client.

Implementation status: **PARTIALLY IMPLEMENTED**. The active `cookapp` project has `user_snapshots`, RLS, revision/CAS migrations and account deletion infrastructure; current client offers automatic/Wi-Fi/manual modes, first-sync choice, three-way merge, error and per-conflict UI. This remains **unverified** without real two-account/two-device and interrupted-erasure tests (#18/#29/#34).

## Navigation and UI contract

Primary navigation is Recipes / Plan / Groceries / Profile with native platform treatment. Add is a Recipes action. Cooking is full-screen and hides global navigation.

Visual requirements:
- warm cream canvas, green accent, rounded food photography/cards;
- current `Lora-Regular` title/body/control/navigation typography, with system/CJK glyph fallback; older Source Sans 3 plans are superseded, and latest four-language visual acceptance remains open (#26/#33);
- native safe areas, Dynamic Type and 44pt minimum interactive targets;
- regular material/glass for navigation and compact controls, not every content card;
- every actionable row has pressed/disabled/error/loading state;
- no fake account, fake subscription, fake sync or fake AI completion.

## Static end-to-end audit

### Flows that can currently close locally
- create/import local recipe → review/edit → save → search/open;
- favorite/edit/delete recipe;
- recipe → selected groceries → check/edit/delete;
- recipe → meal plan → open/remove;
- recipe → cooking → timer/ingredients/steps → finish;
- profile → local preferences/export/reset.

### Flows that cannot currently close
- production-verified Auth/provider delivery across supported sign-in paths;
- production-verified App Store purchase/restore/entitlement behavior;
- authenticated multi-device sync;
- signed-device verification of the Share Extension durable receipt and backend handoff;
- TikTok/Instagram/YouTube backend AI extraction;
- delete cloud account/data;
- production-verified remote Collection sync across devices.

## Release gate

Do not call V1 functionally complete until every NOT IMPLEMENTED item above is either implemented and tested or explicitly removed from V1 scope in the PRD. Static source review is not a substitute for simulator/device UI validation, StoreKit sandbox testing, Supabase integration testing or Share Extension host-app testing.


## 2026-10-07 implementation pass

Implemented in branch `codex/v1-production-integrations`:
- StoreKit 2 entitlement service, transaction updates, purchase and explicit Restore Purchases.
- Subscription screen with App Store localized product data and Manage Subscription.
- Account/sign-in/sign-up/forgot-password/Sign in with Apple surfaces and explicit local-data/sync messaging.
- Owner-scoped Supabase snapshot migration with RLS policies.
- Cloud sync protocol boundary that fails explicitly while cloud configuration is unavailable.
- Share Extension durable App Group inbox source implementation.

External configuration still blocks production-complete status:
- Supabase project `cookapp` is ACTIVE_HEALTHY. Owner-scoped snapshot/RLS/revision migrations are applied; client two-account/two-device acceptance is still pending.
- Apple Developer Sign in with Apple capability/provider settings are not available in this environment.
- App Store Connect subscription product IDs/offers are not available; the app reads them from `RECIPE_SUBSCRIPTION_PRODUCT_IDS` (retained build setting) and never invents price/trial terms. The client now distinguishes verified trial, active, grace, billing retry, expired, revoked, and unavailable states, but production purchase/restore remains unverified until real IDs and a Sandbox account are supplied.
- The Share Extension target and App Group entitlement are present in the Xcode project; matching Apple team provisioning, host-app tests, and a full signed device handoff still require external validation.
- Social-video AI backend worker/provider credentials remain undeployed.

Therefore these areas are code-complete at the UI/contract boundary, but not production-integrated. Do not label them live until the external configuration and integration tests pass.
