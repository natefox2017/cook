# Recipe Pals — Optional Public Recipe Page (not deployed)

A dependency-free, server-rendered guest recipe reader for `/r/:opaqueSlug`, intended to consume the **permission-filtered public snapshot** from Issue #242. The `GET` loader is injected for tests; without `RECIPE_PALS_PUBLIC_RECIPE_API` the server returns 503 rather than displaying sample/private content. API implementation, staging, real HTTPS hosting, AASA/Universal Links and public revocation are **not present**.

- `npm test` (Node 20+) runs security/availability/HTML tests.
- `npm start` starts a local-only reader (no example data).
- `RECIPE_PALS_PUBLIC_RECIPE_API`: an **approved** HTTPS endpoint base responding to `GET /<slug>` with `PublicRecipeSnapshot` JSON; must perform RLS/auth-field allowlisting, rights checks and revocation.
- `RECIPE_PALS_APP_STORE_URL`: **verified** `https://apps.apple.com/.../idNNNN` destination. No CTA is shown until this is set; never invent a listing.
- HTML uses escaped text, no untrusted script/HTML, no user-private data, no tracking cookies, `Cache-Control: no-store`, CSP and `noindex` for unlisted shares.

This is a **development component**, not the public product release. Only publish once #242/#250 and the real domain/Apple settings are verified, then complete signed-device/visitor/OG/cache/withdrawal acceptance in #243/#251. Keep the former `admin/` site separate.
