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

The checked-in `admin-auth` currently supports password login and password changes only. Google Authenticator TOTP and passkey login are not implemented in its server-side contract, so do not expose this console publicly until those flows are added and verified. The seeded `admin` / `admin` credential is permitted only by local/development backend configuration; production explicitly blocks it and requires a bootstrapped owner password.

The production `admin-ai` function source is not checked into this repository. Confirm its provider and usage request/response contract before using the AI Models write actions; provider API keys must remain server-side.
