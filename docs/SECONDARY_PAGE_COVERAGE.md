# Secondary Page Coverage

Updated: 2026-10-08

This document is the UI completeness checklist for the current codebase. Production services are intentionally allowed to remain unconfigured until the later production test pass.

## First launch

- Welcome / value proposition — implemented.
- First-use recipe saving guide — implemented and reusable from Profile.
- Optional Premium plan step — implemented with App Store product data, Restore Purchases, legal links, and a visible Continue Free path.
- Production follows the device locale; UI automation remains English and bypasses first launch.

## Profile / Settings

- Profile overview — implemented.
- Edit local profile — implemented.
- Settings hub — implemented.
- RecipePouch Account — implemented UI + Supabase Auth actions: sign in/sign up/forgot password/password recovery/Sign in with Apple/sign out; provider delivery still requires production verification.
- Subscription — implemented UI + StoreKit 2 service: products/purchase/status/restore/manage; real App Store products deferred.
- Cloud Sync — implemented settings/status/mode page; production Supabase connection deferred.
- Notifications — implemented.
- Appearance — implemented.
- Cooking preferences — keep-screen-awake is saved; timer notifications open the shared permission-aware screen instead of bypassing denied iOS permission.
- Grocery preferences — consolidation now controls newly added recipe ingredients; source-name visibility controls the grocery rows without deleting source IDs.
- Meal Plan preferences — System Default / Sunday / Monday now change week order, range and planned-meal count consistently.
- Data & Privacy — export and cloud delete entry implemented. Local-only deletion consistency and signed-in sync isolation still tracked in #18.
- Help & Support — implemented: import, cooking, meal/shop, subscription, sync and import-review troubleshooting.
- About — implemented: version, licenses, acknowledgements, EULA.
- Collections — implemented locally: create/rename/delete, multi-membership, Favorites kept separate, real counts, collection detail/search, recipe membership management and recipe-library filtering; remote sync remains #29.

## Recipes

- Library/search/filter/sort/empty/no-result — implemented, including custom Collection filters.
- Add recipe menu — implemented.
- URL/text/PDF/photo/camera/manual intake — implemented locally.
- Import error/partial-review state — implemented.
- Recipe detail — implemented.
- Edit recipe — implemented.
- Ingredient selection → groceries — implemented.
- Recipe → meal plan — implemented.
- Source/original text — implemented.
- Delete/favorite — implemented.
- Cooking full-screen — implemented.
- Cooking step workspace — implemented locally: step-linked ingredients with serving-aware amounts, temperature/heat cues, completed-step progress, multiple timers per step, cross-step/manual timer management, session recovery and keep-awake behavior.
- Cooking ingredients checklist/timers/session recovery — implemented.

## Groceries

- All/to-buy/bought states — implemented.
- Group/collapse — implemented.
- Manual add/edit/delete — implemented.
- Recipe source references — implemented.
- Clear bought — implemented.
- Empty states — implemented.

## Meal Plan

- Week/date navigation — implemented.
- Breakfast/lunch/dinner — implemented.
- Add/change/remove recipe — implemented.
- Open planned recipe — implemented.
- Recipe detail → plan — implemented.

## Deferred production-only verification

The following are not UI omissions. They require production configuration and are intentionally deferred:
- Supabase Auth, email delivery, Apple provider and RLS integration test.
- App Store Connect product IDs, offers, StoreKit sandbox/production purchase and restore.
- Share Extension target signing/App Group host-app test.
- Backend social-video AI processing and provider credentials.
- Production-verified cloud Collection membership/sync (#29/#34).

No screen should claim those production services succeeded while they are unconfigured.


## 2026-10-07 navigation / click audit

Corrections applied after static path review:
- Root navigation is now four tabs: Recipes / Plan / Groceries / Profile.
- Fixed a literal escaped newline in RecipeApp.swift that could prevent compilation.
- Injected SubscriptionStore into the SwiftUI environment so Subscription does not crash on access.
- Removed a no-op Sync Now button.
- Replaced a fake always-on appearance toggle with truthful read-only state.
- Unconfigured account/auth controls are visibly disabled instead of accepting taps that only show placeholder messages.
- Cloud account deletion is visibly unavailable until sign-in instead of acting like a working destructive action.
- Display titles use the serif system design; Source Sans 3 remains the body/control font, matching the design direction.
