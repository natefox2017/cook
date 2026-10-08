# Supabase Auth Setup

This app connects to the existing `cookapp` Supabase project. The iOS target uses
only the project's publishable key; service-role and provider secrets must stay
in Supabase or another server-side secret store.

## Redirect URL

The current app callback is `recipe_app://auth/callback`; `cook://auth/callback`
remains registered for compatibility. The live allowlist was reconciled with the
repository configuration and has no remaining differences. The project Site URL
is temporarily `https://www.google.com`, as requested for the current link test.
Native OAuth and password recovery requests specify the app callback directly.

## Email code and password sign-in

The account screen uses one flow for sign-in and account creation. A new email
address can create an account after code verification. Existing users can choose
an email code or password sign-in. Password recovery returns to the app callback
and submits the new password through Supabase Auth. The reset acknowledgment
stays generic because Supabase does not reveal whether the email belongs to an
account ([password-based Auth docs](https://supabase.com/docs/guides/auth/passwords)).

The client sends email OTP with `shouldCreateUser: true` and verifies the entered
code with type `email`. For hosted Supabase, the **Magic Link** email template must
include `{{ .Token }}` to deliver a numeric code; a template that uses only
`{{ .ConfirmationURL }}` sends a link instead. The live template has not yet been
changed or verified, so code delivery remains blocked until that template is set.

The Swift client uses PKCE for callback-based flows. Recovery callbacks are
generic code exchanges rather than recovery-specific auth events, so the app
keeps a local pending-recovery marker across restarts and consumes it after a
valid callback. The PKCE verifier remains in local auth storage; recovery links
must be opened on the device that requested them. See the
[Supabase PKCE flow docs](https://supabase.com/docs/guides/auth/sessions/pkce-flow).

## Apple and Google sign-in

The unified account screen exposes Apple and Google sign-in. Apple uses the
native authorization sheet and exchanges its identity token with Supabase Auth;
Google uses Supabase's OAuth flow and the app callback. Provider credentials
remain server-side. Both providers must be enabled in Supabase Auth before their
buttons can authenticate users. The live project currently has both providers
disabled.

## Client integration status

- Auth client is pinned to `supabase-swift` 2.55.3.
- Sessions are stored in Keychain and Supabase refreshes an expired stored
  session before emitting the initial auth state.
- The service supports email-code sign-in/account creation, password sign-in and
  recovery, Apple token exchange, Google OAuth, session refresh, callback
  handling, and sign-out.
- Local HTTP-stub regression coverage is present for email/session and password
  recovery behavior; XCTest was not run for this change.
- On 2026-10-08, a simulator build completed and was installed on `Supabase Auth
  QA`. Manual navigation confirmed the unified email/Next screen, visible Apple
  and Google buttons, the next Sign In step, and the password alternative. No
  code, password, or provider sign-in was submitted during this UI update.
- The redesigned sign-in screen was installed and inspected on the same simulator
  after a normal launch without language arguments. The email/Next controls,
  official Google logo and native Apple button displayed in Simplified Chinese.
  This confirms the first-screen UI and default language only.
- Real email-code, password, Google, Apple, callback, and cloud-write flows still
  require end-to-end verification against configured providers.

## Live provider check

Checked 2026-10-08 against project `cookapp` (`semsjyrqjnumpvanibip`): the
project reports `ACTIVE_HEALTHY`. Public Auth settings report email
authentication enabled, email auto-confirm disabled, and both Apple and Google
disabled. The Auth CLI configuration confirms the `recipe_app://auth/callback`
and legacy `cook://auth/callback` allowlist entries and the temporary Google Site
URL. Email delivery was rate-limited during the flow, and the hosted Magic Link
template still needs the OTP token variable. No Apple or Google provider secret
is stored in the iOS client; provider sign-in is not yet usable against this
project.

The test account's email is confirmed and its profile row exists. No successful
app session or cloud snapshot has been verified yet. The target contains the Sign
in with Apple entitlement, while Apple Developer capability and provisioning
profile configuration have not been checked. These are configuration facts, not
end-to-end acceptance evidence.
