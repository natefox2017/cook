# Cook V1 Product Completeness Specification

Updated: 2026-10-07

## Product benchmark

Cook is a private recipe utility: collect → organize → cook → shop → plan → sync. It does not add a public feed in V1.

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

Implementation status: **CLIENT FLOW IMPLEMENTED / PRODUCTION VERIFICATION PENDING**. First launch now includes the value proposition, first-use guide and Premium plan step. Email sign-up/sign-in/reset, Sign in with Apple and sign-out call the Supabase Auth service. Local-data merge policy, cloud account deletion and production provider verification remain incomplete.

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

Implementation status: **CLIENT FLOW IMPLEMENTED / APP STORE CONFIGURATION PENDING**. The first-launch paywall and Settings subscription page use StoreKit 2 products, purchases, current entitlements, restore and the system manage-subscription sheet. Product IDs/offers and sandbox/production purchase behavior still require App Store Connect verification.

### 3. Recipe library
Required:
- Persistent library, search, filters/categories, favorites, sorting, empty/no-result/loading/error states.
- Search title, ingredients, steps and notes.
- Open recipe detail.
- Collections/cookbooks are P0 in the existing product overview and need a concrete UI/data model if retained in V1.

Implementation status: **MOSTLY IMPLEMENTED**; collections/cookbooks are **NOT IMPLEMENTED**.

### 4. Add/import
Required:
- URL import.
- Manual recipe.
- Photo/camera OCR.
- Selectable-text document/PDF.
- Clipboard/text import.
- Keep source and partial result when extraction is incomplete.
- Duplicate source handling.
- Share Extension: third-party app → Share → Cook → durable receipt → return immediately.
- Social source backend fallback (caption/article/ASR/OCR/visual evidence) without fabricating quantities.

Implementation status: local URL/text/photo/PDF/manual paths are **IMPLEMENTED**; Share Extension, durable backend import worker and social-video AI pipeline are **NOT IMPLEMENTED**.

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

Implementation status: local settings/export/reset/help are **IMPLEMENTED**; account/sync/subscription/server deletion are **NOT IMPLEMENTED**.

### 10. Cloud sync
Required:
- Supabase Auth + RLS owner isolation.
- Recipes, groceries and meal plan sync.
- Last-sync/error status and retry.
- Offline local edits with deterministic conflict policy.
- Account deletion.
- Never put service role/provider secrets in the client.

Implementation status: **NOT IMPLEMENTED**.

## Navigation and UI contract

Primary navigation remains Recipes / Plan / Groceries / Profile with a floating/native Liquid Glass treatment where the OS supports it. Add is a Recipes action, not a fourth permanent tab. Cooking is full-screen and hides global navigation.

Visual requirements:
- warm cream canvas, green accent, rounded food photography/cards;
- serif-like display hierarchy + Source Sans 3 body/control typography with system/CJK fallback;
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
- register/sign in/forgot password/sign out;
- subscribe/restore/manage entitlement;
- authenticated multi-device sync;
- Share Extension durable receipt;
- TikTok/Instagram/YouTube backend AI extraction;
- delete cloud account/data;
- collections/cookbooks if kept as V1 P0.

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
- Supabase project `cookapp` is currently INACTIVE, so Auth/RLS/sync cannot be applied or integration-tested.
- Apple Developer Sign in with Apple capability/provider settings are not available in this environment.
- App Store Connect subscription product IDs/offers are not available; the app reads them from `COOK_SUBSCRIPTION_PRODUCT_IDS` and never invents price/trial terms.
- The Share Extension source exists, but its Xcode extension target/App Group entitlement/provisioning must be created with the Apple team before host-app testing.
- Social-video AI backend worker/provider credentials remain undeployed.

Therefore these areas are code-complete at the UI/contract boundary, but not production-integrated. Do not label them live until the external configuration and integration tests pass.
