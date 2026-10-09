> **Contract version/status clarification (2026-10-09):** This document dates to the original 2026-10-08 Auth/StoreKit sync flow and is retained for its identity and privacy rules, **not a current provider/ASC availability check**. The user-facing name is Recipe Pals. Formal monthly/yearly client IDs were configured in PR #210; actual StoreKit Sandbox is OPEN #132, Auth #131, Sync #133. Premium gating described below is **a proposal until the product policy is explicitly approved**, not a currently enforced quota. AI-powered editing, private-by-default public share and invite rewards are planned separately in #238–#248; do not derive access/paywall promises from this old proposal.

# Account, Sync & Subscription Contract

Updated: 2026-10-08

## Account model

Recipe Pals needs one application account identity for cloud data. Supported V1 sign-in:
- Sign in with Apple.
- Email + password: sign up, sign in, forgot/reset password.

Do not infer that an App Store purchase identity is the same thing as a Recipe Pals account. ReciMe explicitly documents that subscription method and sign-in method can differ. A restore can recover an App Store entitlement but cannot recover recipes from the wrong Recipe Pals account.

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

## Snapshot sync implementation status

- The Supabase `cookapp` project is active. Production was verified to contain the owner-scoped `user_snapshots` table plus revision/CAS migrations through `20261008030120`.
- Production has applied `20261008050000_restrict_user_snapshot_writes_to_rpc.sql`. Live metadata confirms RLS is enabled, `authenticated` has SELECT but no direct INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER, and `anon` has no SELECT; only `authenticated` can execute the owner-checked revision RPC. The production migration history contains two records with this same name, so resolve that duplicate history only if a future migration operation reports a conflict; do not rewrite production history speculatively.
- The client persists the last successfully synchronized snapshot per account under Application Support and records which Recipe Pals account the local library is linked to. Switching accounts never silently uploads another account's local library.
- Reconnect/foreground refresh uses a three-way merge: last synchronized base + local + newest cloud snapshot. Remote-only and local-only changes merge automatically; true concurrent edits remain explicit conflicts.
- Collection membership conflicts use both Collection and Recipe identifiers. Same normalized Collection names and same meal-plan slots are surfaced as resolvable domain conflicts rather than generic validation errors.
- Automatic, Wi-Fi Only, and Manual modes update the live coordinator. Foregrounding or refreshing the same signed-in account checks for newer revisions.
- The existing Settings UI now exposes real account/status/last-sync state, Sync Now, first-sync merge/keep-local choice, and per-conflict local/cloud resolution.
- Account/cloud deletion calls the authenticated `delete-account` Edge Function; deleting local data remains a separate explicit action.
- Two-account/two-device production acceptance is still required before #29 can be considered production-verified. The deployed account-deletion function is now checked into `supabase/functions/delete-account/`; it clears the four private storage buckets before deleting the Auth user. This code was recovered from the active deployment, and no real account deletion was executed during this verification.

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
- Recipe Pals account mismatch does not imply recipes were restored.

Sync:
- first upload;
- second-device download;
- offline edit;
- retry after reconnect;
- conflict handling;
- RLS cross-user denial;
- account deletion removes server-owned data.
