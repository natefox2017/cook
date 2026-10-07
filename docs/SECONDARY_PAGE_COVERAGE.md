# Secondary Page Coverage

Updated: 2026-10-07

This document is the UI completeness checklist for the current codebase. Production services are intentionally allowed to remain unconfigured until the later production test pass.

## Profile / Settings

- Profile overview — implemented.
- Edit local profile — implemented.
- Settings hub — implemented.
- First launch — implemented: welcome/value proposition → first-use recipe import guide → App Store-backed Premium plan page → explicit free continue path.
- Getting Started — implemented as a reusable Settings page after onboarding.
- Cook Account — implemented client actions: email sign in/sign up/password reset/Sign in with Apple/sign out; production Supabase email delivery and Apple provider behavior still require integration verification.
- Subscription — implemented first-launch paywall + Settings management UI + StoreKit 2 service: localized products, purchase, verified entitlement status, restore and manage; real App Store products/offers still require sandbox/production verification.
- Cloud Sync — implemented settings/status/mode page; production Supabase connection deferred.
- Notifications — implemented.
- Appearance — implemented.
- Cooking preferences — implemented.
- Grocery preferences — implemented.
- Meal Plan preferences — implemented.
- Data & Privacy — implemented: export, local delete, cloud delete entry, stored-data explanation, privacy summary.
- Help & Support — implemented: import, cooking, meal/shop, subscription, sync and import-review troubleshooting.
- About — implemented: version, licenses, acknowledgements, EULA.
- Collections — implemented secondary page shell + Favorites; cloud collection membership deferred.

## Recipes

- Library/search/filter/sort/empty/no-result — implemented.
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
- Cloud collection membership/sync.

No screen should claim those production services succeeded while they are unconfigured.


## 2026-10-07 navigation / click audit

Corrections applied after static path review:
- Root navigation is now four tabs: Recipes / Plan / Groceries / Profile.
- Fixed a literal escaped newline in CookApp.swift that could prevent compilation.
- Injected SubscriptionStore into the SwiftUI environment so both first-launch paywall and Settings subscription surfaces use one entitlement source.
- Removed a no-op Sync Now button.
- Replaced a fake always-on appearance toggle with truthful read-only state.
- Unconfigured account/auth controls are visibly disabled instead of accepting taps that only show placeholder messages.
- Cloud account deletion is visibly unavailable until sign-in instead of acting like a working destructive action.
- Display titles use the serif system design; Source Sans 3 remains the body/control font, matching the design direction.
