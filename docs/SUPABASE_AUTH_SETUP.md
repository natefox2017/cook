# Supabase Auth Setup

This app connects to the existing `cookapp` Supabase project. The iOS target uses
only the project's publishable key; service-role and provider secrets must stay
in Supabase or another server-side secret store.

## Redirect URL

The app handles the `cook://auth/callback` URL for email confirmation and password
recovery. Keep this URI in the Supabase Auth redirect allowlist and in
`ios/Recipe/Info.plist`; the live project's allowlist has not been verified.

## Email and password

Configure the project's email provider and confirmation policy in Supabase Auth.
When email confirmation is enabled, registration returns a verification-needed
state until the user follows the email link. Password reset returns to the same
app callback and the recovered password is submitted through Supabase Auth. The
reset acknowledgment stays generic because Supabase does not reveal whether the
email belongs to an account ([password-based Auth docs](https://supabase.com/docs/guides/auth/passwords)).
The Swift client uses PKCE, whose recovery callback is a generic code exchange
rather than a recovery-specific auth event. After a reset request succeeds, the
app keeps a local pending-recovery marker across app restarts and consumes it
after a valid callback, so the account screen opens to the recovery form without
changing the callback URL. Failed callback exchanges also open the account screen
so the error is visible. The PKCE verifier remains in Supabase's local auth
storage; recovery links must be opened on the device that requested them. See the
[Supabase PKCE flow docs](https://supabase.com/docs/guides/auth/sessions/pkce-flow).

## Sign in with Apple

The client exchanges Apple's identity token with Supabase Auth and sends the raw
nonce used for the Apple request. Before enabling the Apple action, enable the
**Sign in with Apple** capability for the App ID (`com.shopkivoo.recipe`) and
its Xcode target, ensure the provisioning profile carries that capability, and
configure the corresponding Apple provider in Supabase Auth. Keep any Apple
private key and provider secrets in provider configuration; never add them to
the app.
For this native-only ID-token flow, Supabase Apple Client IDs must include
`com.shopkivoo.recipe`. A Services ID, `.p8` and client secret are required only
for a separate web OAuth flow, not the current native action. See the
[native Swift configuration](https://supabase.com/docs/guides/auth/social-login/auth-apple#configuration-swift-native).
The native account screen is wired to the Auth service. A visible Apple button
does not mean the provider is enabled; the live project state below currently
blocks Apple sign-in.

## Sign in with Google

The account sheet now offers Google beside Apple's native sign-in. The Google
button calls `client.auth.signInWithOAuth(provider: .google,
redirectTo: RecipeSupabase.redirectURL)` through the existing Supabase Swift
client and the system's `ASWebAuthenticationSession`. Supabase exchanges the
OAuth callback and stores the resulting app session in the same Keychain-backed
client as email/Apple login. Canceling the Google browser sheet is not an error.
No new Google SDK, on-device Google secret, or extra account store is required.

**Required deployment configuration (not verified in production):**
1. In Google Cloud, register a Web OAuth client and allow
   `https://semsjyrqjnumpvanibip.supabase.co/auth/v1/callback` as its
   authorized redirect URI. Configure the consent screen brand/audience and
   minimum `openid`, email, profile scopes.
2. Under Supabase `cookapp` → Authentication → Providers → Google, enable the
   provider and configure that Web Client ID and Client Secret.
3. Supabase Auth redirect URLs must allow `cook://auth/callback` in addition
   to Google Cloud's *HTTPS* callback. These are two different redirect steps.
4. Verify successful login, user cancellation, restart/session restoration and
   returning from the OAuth browser on a signed iPhone. Do not call the provider
   available until these actions succeed.

Apple retains its official `SignInWithAppleButton`; the Google logo is a
multicolor vector asset using the standard G geometry/colors. Both controls use
50pt height and 14pt corner radius. Google uses its standard outlined/dark
colors, while Apple uses the supported white-outlined (light) or white (dark)
variant. Provider-specific branding takes precedence over an identical fill.
This follows:
- https://developers.google.com/identity/branding-guidelines
- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/
- https://supabase.com/docs/reference/swift/auth-signinwithoauth

## Client integration status

- Auth client is pinned to `supabase-swift` 2.55.3.
- Sessions are stored in Keychain and Supabase refreshes an expired stored
  session before emitting the initial auth state.
- The service supports email sign-up/sign-in, password reset/update, Apple token
  exchange, Google OAuth via system authentication session, session refresh,
  callback handling, and sign-out.
- Local HTTP-stub regression coverage is present for email/session and password
  recovery behavior; simulator XCTest is pending the shared-device queue.
- Production sign-up, email delivery, Apple sign-in, and password-recovery flows
  still require end-to-end verification against the configured providers.

## Live provider check

Checked 2026-10-09 against project `cookapp` (`semsjyrqjnumpvanibip`): the
project reports `ACTIVE_HEALTHY`. Its public Auth settings report email
authentication enabled, email auto-confirm disabled, and both Apple and Google
providers disabled. New email accounts therefore require confirmation, but successful
message delivery has not been tested. The settings endpoint does not expose the
redirect allowlist, so the exact `cook://auth/callback` allowlist entry is not
verified. No Apple provider secret or email credential is stored in the iOS
client; the target contains the Sign in with Apple entitlement, while the
local signed provisioning profile was verified to contain team `WT475Q2P69`,
the current App ID, Apple capability, App Group and the supplied iPhone.

This is configuration evidence only. No test account was created and no email,
Apple credential, recovery link, or password was submitted. Real provider flows,
Keychain restore, and cold/warm callback handling remain unverified.

The separate local GoTrue/PostgREST email and snapshot harness and the exact
remaining external setup actions are documented in
[Auth, StoreKit and sync readiness](AUTH_STOREKIT_SYNC_READINESS.md).
