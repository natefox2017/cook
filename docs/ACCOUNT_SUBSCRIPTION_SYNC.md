# Account, Sync & Subscription Contract

Updated: 2026-10-07

## Account model

Recipe needs one application account identity for cloud data. Supported V1 sign-in:
- Sign in with Apple.
- Email + password: sign up, sign in, forgot/reset password.

Do not infer that an App Store purchase identity is the same thing as a Recipe account. ReciMe explicitly documents that subscription method and sign-in method can differ. A restore can recover an App Store entitlement but cannot recover recipes from the wrong Recipe account.

### Session states
- signedOut
- authenticating
- needsEmailVerification
- signedIn(userID, email)
- authError(recoverable)

### Local-data linking
When a signed-out device already has local recipes and the user signs in:
1. show how many local recipes/groceries/planned meals exist;
2. offer Merge with account or Keep local until later;
3. never silently overwrite cloud or local data;
4. server IDs/ownership become authoritative only after a successful upload transaction.

## Supabase boundary

Use Supabase Auth for app identity and PostgreSQL/RLS for private data. All recipe/grocery/meal-plan/import records are owner-scoped. Service role and AI provider keys remain server-side.

Required account actions:
- create email account;
- sign in email;
- reset password;
- exchange/verify Sign in with Apple identity;
- sign out;
- refresh session;
- delete account + owned server data;
- sync status and retry.

## Subscription model

V1 premium is an auto-renewable App Store subscription implemented with StoreKit 2.

The actual product IDs, localized price, trial/intro eligibility and terms come from App Store Connect/StoreKit. Do not hard-code prices or claim a trial that App Store Connect does not return.

### Entitlement states
- loading
- free
- trial
- active
- gracePeriod
- expired
- revoked
- unavailable/error

### Required client behavior
- Read verified current entitlements on launch/foreground.
- Observe transaction updates.
- Purchase from the product returned by StoreKit.
- Finish verified successful transactions after entitlement delivery.
- Expose Restore Purchases as an explicit user action.
- Restore action calls AppStore.sync(), then refreshes current entitlements.
- Never call AppStore.sync() automatically on launch because it may show an App Store authentication prompt.
- Provide Manage Subscription using Apple’s supported subscription management surface/link.
- Pending/deferred purchase stays pending; cancelled purchase is not shown as an error entitlement.
- Unverified transactions never unlock premium.

### Account ↔ entitlement
Server may record an entitlement association for cross-platform/account policy, but the iOS client must still validate App Store entitlement. Signing out of Recipe does not cancel the Apple subscription. Restoring an Apple purchase does not choose which Recipe cloud account contains the user’s recipes.

## Paywall contract

Paywall must show:
- product display name;
- localized current price and billing period;
- trial/intro terms only when returned as eligible;
- Subscribe/Start Trial CTA derived from eligibility;
- Restore Purchases;
- Terms and Privacy;
- close/continue-free path when the feature is not mandatory for app entry.

No fake discount countdown, fake trial, hard-coded localized price or preselected consent.

## Premium gating proposal

Free keeps:
- existing recipes readable/editable;
- cooking;
- manual groceries;
- local export.

Premium candidates:
- unlimited automated/social imports;
- cloud sync;
- advanced scanning/AI;
- future shared cookbooks/family.

Final limits must be frozen in product policy before code enforcement. Expiration must not hide or destroy user-created recipes.

## Acceptance tests

Account:
- new email sign-up;
- existing email sign-in;
- wrong password;
- reset password;
- Apple sign-in success/cancel/failure;
- sign-out and re-login;
- local-data merge decision;
- delete account.

Subscription:
- products unavailable;
- free → purchase → active;
- user cancels purchase sheet;
- Ask to Buy/deferred;
- transaction verification failure;
- active entitlement survives relaunch;
- explicit restore success;
- restore with no matching purchase;
- expired/revoked entitlement;
- Manage Subscription;
- Recipe account mismatch does not imply recipes were restored.

Sync:
- first upload;
- second-device download;
- offline edit;
- retry after reconnect;
- conflict handling;
- RLS cross-user denial;
- account deletion removes server-owned data.
