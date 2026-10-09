# Recipe Pals Admin

Standalone operations console built with React, Vite, and shadcn-style components.

## Run locally

1. Copy `.env.example` to `.env.local` and set the Supabase project Functions URL and publishable key.
2. Run `./run-admin.sh` from the repository root, or run `npm install && npm run dev` in this directory.

The browser uses only a Supabase publishable key and the custom admin bearer session. Service-role keys and model API keys never belong in this app's environment variables. Admin sessions are held in `sessionStorage` and revalidated with `admin-auth` when the page reloads.

## Connected functions

- `admin-auth`: login, session, logout, password change
- `admin-dashboard`: registration and subscription overview (owner only)
- `admin-users`: account list and payment details
- `admin-subscriptions`: revenue reports, subscription records, plan catalog
- `admin-ai`: OpenAI-compatible provider configuration and model usage (the existing production function's route contract must match this UI)

The admin dashboard uses the custom admin session rather than end-user Supabase Auth. Keep function gateway JWT verification disabled only for these routes; each function must validate the custom admin bearer session and role. The admin dashboard receives registration and payment data only for the management flows that need it.

Provider API keys are write-only from the UI: editing an endpoint never fetches or displays the saved key. Only send them to a trusted backend function over HTTPS.

The current repository has no trusted registration-country value. The user list shows country as unavailable until the registration pipeline stores a country code; it never geolocates or displays registration IPs in the browser.

`admin-auth` uses custom bearer sessions, separate from end-user Supabase Auth. It supports password login and changes, Google Authenticator-compatible TOTP, WebAuthn passkeys, factor management, and per-admin login history. When a factor is enabled, password verification starts a short-lived factor challenge instead of issuing a session; TOTP is required when enabled, otherwise a registered passkey can complete sign-in. TOTP secrets are encrypted at rest, accepted TOTP counters cannot be replayed, and successfully verified WebAuthn challenges are consumed. Passkey verification requires user verification plus the configured origin and relying-party ID. Configure `ADMIN_AUTH_FACTOR_ENCRYPTION_KEY`, `ADMIN_WEBAUTHN_ORIGIN`, and `ADMIN_WEBAUTHN_RP_ID` on the Edge Function before enabling these factors.

Failed password and factor attempts share an account-level counter. The fifth failure locks that administrator out for 24 hours, and a correct password alone does not clear failures while a second factor is still required. Successful completion clears the counter. Login history records the method, outcome, timestamp, optional IP address and user agent, and a bounded failure reason; it does not store submitted passwords, TOTP codes, passkey responses, or bootstrap tokens. The seeded `admin` / `admin` credential is permitted only by local/development backend configuration; production explicitly blocks it and requires a bootstrapped owner password.

The production `admin-ai` function source is not checked into this repository. Confirm its provider and usage request/response contract before using the AI Models write actions; provider API keys must remain server-side.

The AI Models UI expects provider tests at `POST /admin-ai/providers/test`. That route must be implemented by the trusted function: accept the test configuration and optional replacement key, use the saved key when editing without a replacement, avoid logging or echoing secrets, and return `{ "ok": true }` only after the upstream test succeeds. The browser sends secrets only to the configured HTTPS function origin, refuses redirects, and blocks tests for HTTP provider URLs; HTTP provider URLs may still be saved for local deployments. The production function source is unavailable in this repository, so the test route and upstream behavior remain a backend acceptance dependency.

Usage responses may omit optional telemetry. Missing cached input token and average response time values render as “Not reported”; the nullable `ai_usage_events.cache_read_input_tokens` column follows the OpenTelemetry cache-read input token meaning and remains a subset of input tokens.
