# Supabase Auth Setup

This app connects to the existing `cookapp` Supabase project. The iOS target uses
only the project's publishable key; service-role and provider secrets must stay
in Supabase or another server-side secret store.

## Redirect URL

The app continues to handle the registered `cook://auth/callback` URL for email
confirmation and password recovery. Keep this URI in the Supabase Auth redirect
allowlist and in `ios/Recipe/Info.plist` until the provider configuration is migrated.

## Email and password

Configure the project's email provider and confirmation policy in Supabase Auth.
When email confirmation is enabled, registration returns a verification-needed
state until the user follows the email link. Password reset returns to the same
app callback and the recovered password is submitted through Supabase Auth.

## Sign in with Apple

The client exchanges Apple's identity token with Supabase Auth and sends the raw
nonce used for the Apple request. Before enabling the Apple action, enable the
**Sign in with Apple** capability for the existing App ID (`com.modelhub.cook`) and
its Xcode target, ensure the provisioning profile carries that capability, and
configure the corresponding Apple provider in Supabase Auth. Keep any Apple
private key and provider secrets in provider configuration; never add them to
the app.
The native account screen is wired to the Auth service. A visible Apple button
does not mean the provider is enabled; the live project state below currently
blocks Apple sign-in.

## Client integration status

- Auth client is pinned to `supabase-swift` 2.55.3.
- Sessions are stored in Keychain and Supabase refreshes an expired stored
  session before emitting the initial auth state.
- The service supports email sign-up/sign-in, password reset/update, Apple token
  exchange, session refresh, callback handling, and sign-out.
- Production sign-up, email delivery, Apple sign-in, and password-recovery flows
  still require end-to-end verification against the configured providers.

## Live provider check

Checked 2026-10-08 against project `cookapp` (`semsjyrqjnumpvanibip`): the
project reports `ACTIVE_HEALTHY`. Its public Auth settings report email
authentication enabled, email auto-confirm disabled, and the Apple provider
disabled. New email accounts therefore require confirmation, but successful
message delivery has not been tested. The settings endpoint returned a null
redirect allowlist, so the exact `cook://auth/callback` allowlist entry is not
verified. No Apple provider secret or email credential is stored in the iOS
client; the target contains the Sign in with Apple entitlement, while the
Apple Developer capability and provisioning profile have not been checked.

This is configuration evidence only. No test account was created and no email,
Apple credential, recovery link, or password was submitted. Real provider flows,
Keychain restore, and cold/warm callback handling remain unverified.
