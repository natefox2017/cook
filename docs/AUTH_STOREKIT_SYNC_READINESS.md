> **HISTORICAL configuration snapshot (2026-10-09).** This document verified `main@8e552e6` at its own timestamp and is **not the latest product-ID/provider availability inventory**. After this snapshot, [PR #210](https://github.com/natefox2017/cook/pull/210) configured Debug/Release product IDs `com.shopkivoo.recipe.pro.monthly` and `com.shopkivoo.recipe.pro.yearly`; #132 records the signed **Xcode local StoreKitTest** evidence, but real ASC Sandbox/TestFlight remains unverified. Recheck live Apple/Google/email settings under #131; do not assume provider state is unchanged. Current release gate: #251.

# Auth, StoreKit and snapshot integration readiness

Checked 2026-10-09 against main `8e552e64f7c672373d4c6290817ee6882d3c2cd1`.
Tracks [#131](https://github.com/natefox2017/cook/issues/131),
[#132](https://github.com/natefox2017/cook/issues/132) and
[#133](https://github.com/natefox2017/cook/issues/133). These issues remain open;
the local HTTP evidence below does not complete their device acceptance.

## Verified configuration at historical baseline `8e552e6` (not a live status claim)

- Public `GET https://semsjyrqjnumpvanibip.supabase.co/auth/v1/settings` with
  the app's publishable key returned Apple **disabled**, Google **disabled**,
  email **enabled**, signup enabled and email auto-confirm disabled. No account
  was created and no mail was requested on this hosted project.
- The app and `Info.plist` agree on `cook://auth/callback`. Public settings do
  not expose the redirect allowlist or SMTP/templates. The existing local CLI
  management token returned 401 on a read-only configuration request; these
  fields remain unverified, not presumed absent.
- A locally built app's embedded provisioning profile contains team
  `WT475Q2P69`, `WT475Q2P69.com.shopkivoo.recipe`, Sign in with Apple `Default`,
  App Group `group.com.shopkivoo.recipe` and the supplied iPhone device ID.
  The profile was created 2026-10-09 and expires 2027-10-09. This verifies the
  profile, not Apple credential exchange or the current installed binary.
- `RecipeSubscriptionProductIDs` resolves from
  `RECIPE_SUBSCRIPTION_PRODUCT_IDS`; the legacy setting remains supported.
  Neither was assigned in the **historical checked-in build settings at this snapshot**; later PR #210 added formal IDs to Debug and Release. No ASC key file was
  found in the standard local key directories and no ASC API connector is
  available in this task. The earlier #132 browser inventory is historical
  evidence; it is not a fresh ASC API inventory.
- The only checked-in StoreKit product is the local-only monthly fixture
  `com.recipepouch.localtest.premium.monthly` with test price `4.99`. It is
  neither a formal product ID nor an approved price. The approved paywall
  offers Monthly and Annual; no formal prices or introductory offer have
  been found in repository docs or #28/#132.

## Reviewable external configuration actions

These actions have **not** been applied. Read current configuration and preserve
all unrelated provider IDs, redirects and settings before any approved update.
Do not paste credentials into GitHub, documentation or chat.

### Native Apple

In `cookapp` Authentication → Providers → Apple, enable Apple and include
`com.shopkivoo.recipe` in Client IDs. The app uses native
`ASAuthorizationAppleIDCredential` followed by Supabase `signInWithIdToken`
with its raw nonce. This path does **not** require a Services ID, client secret,
Key ID or `.p8` key. Keep nonce verification enabled. The existing team/profile
evidence above satisfies the local capability prerequisite.

If a separate **web OAuth** path is later requested, it requires a Services ID
linked to the primary App ID, domain `semsjyrqjnumpvanibip.supabase.co`, return
URL `https://semsjyrqjnumpvanibip.supabase.co/auth/v1/callback`, team
`WT475Q2P69`, and a Sign in with Apple Key ID/private `.p8` to sign a client-secret
JWT for that Services ID. Keep the private key server-side and rotate the
client secret within six months. This is not a dependency of the current
native iOS path. See [Supabase's native Swift and web Apple configuration](https://supabase.com/docs/guides/auth/social-login/auth-apple).

### Google and email

- Identify an existing **Web application** Google OAuth client. The repository,
  environment variable names and standard local config do not provide its
  Client ID/secret reference; this is a specific missing configuration source.
  The current app uses the browser OAuth flow, not Google's native SDK.
- Its authorized redirect URI must include
  `https://semsjyrqjnumpvanibip.supabase.co/auth/v1/callback`. Configure the
  audience/test users and `openid`, email and profile scopes, then enable Google
  in Supabase with the Web Client ID and secret stored in the secure provider
  form. See [Google configuration](https://supabase.com/docs/guides/auth/social-login/auth-google).
- Inspect Supabase URL Configuration and add the exact `cook://auth/callback`
  redirect if absent, preserving existing entries. This is the app-return URI,
  distinct from Google's HTTPS redirect above.
- Inspect the Magic Link template: the primary numeric-code screen requires
  `{{ .Token }}` in the email. Inspect confirmation and recovery links and
  custom SMTP sender/credentials, delivery limits and test-recipient policy.
  A new Free-plan project using default SMTP may not permit template changes;
  use supported custom SMTP rather than claiming that a saved template will
  necessarily deliver. See [email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
  and [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

### App Store Connect

Read the team-selected ASC app for bundle `com.shopkivoo.recipe` and check
membership, Paid Apps Agreement, tax/banking and product availability. Reuse
existing app/subscription records when present. If none exist, creation needs
the account owner's explicit approval and required app metadata.

Freeze these fields before creating products: subscription group, exact
immutable monthly/annual product IDs, reference names, one-month/one-year
durations, subscription level, storefront availability, base currency/price
point, English display names/descriptions, review screenshot/contact notes,
and any explicitly approved introductory offer. At the **historical 8e552 snapshot** there was no source of truth for formal IDs/price/trial. Later configuration is documented in #132/PR #210; current availability/trial terms must still be obtained from the real App Store Connect/Sandbox metadata, not the local fixture.
Keep prices/eligibility displayed by the app sourced from StoreKit. See
[Apple's subscription setup](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/).

Once actual IDs exist, build with
`RECIPE_SUBSCRIPTION_PRODUCT_IDS='<monthly-id>,<annual-id>'` and inspect the
built app's resolved plist before installation. This can be supplied to
`xcodebuild` without editing `project.pbxproj`. Create/use a Sandbox Apple
Account and sandbox/TestFlight build for purchases; never use a real paid
account for acceptance. Record product ID, storefront, transaction environment
and verified entitlement; check purchase/cancel/pending/restore and the
lifecycle matrix in #132. Restore uses the App Store account and does not
select or restore a Recipe cloud account.

## Runnable isolated HTTP evidence

Run `python3 scripts/verify_auth_sync_local.py` from the repository. Requires
Python 3, Docker and Supabase CLI (verified with 2.120.0). The harness creates
its own project under `.tmp/auth-sync-local`, uses API `127.0.0.1:56721` and
Mailpit `127.0.0.1:56724`, copies five existing snapshot migrations unchanged,
and uses real local GoTrue/PostgREST/PostgreSQL. It does not accept hosted URLs
or credentials and disables proxies/redirect following on HTTP requests.

Reports contain check names, commit, runtime versions and migration hashes,
never passwords, mail tokens, JWTs or user addresses. The private startup log
may contain disposable local CLI keys and must stay in ignored `.tmp`. The
`finally` cleanup stops only this randomly named local project and deletes its
test data volumes. Before rerunning, rename/remove the prior **disposable**
`.tmp/auth-sync-local` directory; existing config is never overwritten.

The local run verifies email confirmation, wrong password, numeric email OTP
(including first-time signup and incorrect/reused codes), PKCE recovery and wrong verifier, password
update, refresh and signout, A/B identity separation and A→B switching,
independent A/A2 downloads, cross-owner/anonymous/unauthorized-write denial,
and concurrent CAS with exactly one winner plus safe stale/retry behavior.
Mailpit captures all emails locally. Its code template is a local fixture and
does not establish hosted SMTP/template configuration.

Executed on 2026-10-09: **54/54 checks PASS** with GoTrue v2.197.0,
PostgREST v16.4 and PostgreSQL 17.11.0.004. The test project's containers and
volumes were removed; the unrelated `issue-140-runtime` stack was preserved.
The earlier OTP extension run hit GoTrue's email send interval; the harness
now respects that interval before additional messages. A later startup attempt
hit another task's occupied ports, so this harness moved to the dedicated
567xx ports above. Neither attempt is counted as a passing run.

This does not run the Swift SDK, Keychain, `CloudSyncCoordinator`, RecipeStore
merge/conflict UI, local erase, Storage or account-deletion function. It does
not exercise real Apple/Google, hosted email delivery, StoreKit or two physical
devices. The coordinator retains ownership of the one connected phone.

## Remaining device actions

After approved provider/email configuration and disposable identities exist,
the coordinator must run #131 on the signed iPhone: real email OTP/password/
confirmation/recovery, warm and killed-process callback, Apple private-email
success/cancel/relogin and Google success/cancel/switch, session restoration
and signout. Do not count a protocol verifier exchange as iOS cold-start PASS.

For #133, use two independently authenticated app clients against a controlled
test backend. Exercise first-sync consent, local/remote/offline changes,
explicit conflict choices, account switching, manual/Wi-Fi/automatic modes,
interrupted local erase and controlled account/cloud deletion. One iPhone
plus two HTTP clients cannot meet the two-device UI acceptance bar.
