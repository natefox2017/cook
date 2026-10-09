# OpenAPI repository replacement — #155

This public function serves a locally bundled OpenAPI document. It is the
repository's current-handler contract, version `2026-10-09.1`; it is not a
parity reconstruction of the unavailable production OpenAPI v23.

The document records its source revision in `info.x_source_revisions`:

- `main`: `bef764c4a95186d27d69dbcd76d8ae51c2b47977`, including the merged
  admin-subscriptions, admin-dashboard, and RevenueCat webhook handlers.

`admin-ai` is omitted because the repository has no implementation handler. The
internal worker and cleanup operations are described as internal endpoints with
their separate secret-based authentication; they are not app-client APIs. The
handler imports `openapi.json` locally and has no runtime fetch or remote module
dependency. `verify_jwt = false` is required because the contract is a public
document; its contents include no credential values.

## Local verification

```sh
deno check --cached-only \
  supabase/functions/openapi/index.ts \
  supabase/functions/openapi/handler.ts \
  supabase/functions/openapi/http_test.ts

deno test --cached-only --allow-net=127.0.0.1 \
  supabase/functions/openapi/http_test.ts
```

The HTTP tests serve the handler on loopback only and verify GET parsing,
all-local `$ref` resolution, the reviewed route/method inventory, CORS
preflight, and 405 behavior. The test process has no network permission beyond
`127.0.0.1`; no production Auth token, database, remote fetch, or deployment is
used.

## Release boundary

This change does not deploy the function or alter production state. Any release
requires a separate approved deployment window. Reverting this repository change
is a normal Git revert; the prior live v23 source URL is not a verified rollback
target because its source was unavailable during this investigation. Verify any
rollback target before a later production release.
