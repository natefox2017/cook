# Issue #155 Edge Function source manifest

## Scope and production baseline

This manifest records the public source and a read-only production inventory for the Edge Functions tracked by Issue #155. The Supabase project is `cookapp` (`semsjyrqjnumpvanibip`). The inventory below was read on 2026-10-09. Production was not changed.

`ezbr_sha256` is Supabase's deployed bundle hash. It is not the SHA-256 of `index.ts`. Source hashes below are entrypoint file hashes and do not include imported shared modules or the Deno lockfile.

| Function | Production version | `verify_jwt` | Production bundle SHA-256 | Repository source status |
| --- | ---: | ---: | --- | --- |
| `revenuecat-webhook` | 3 | `false` | `84c47669ef0797808e4fdc3cc61c93cde5b5c04b4b2c69f2aeff9cfe25c591be` | Dedicated source branch is under review. Its owner-binding migration must precede staging webhook tests. |
| `admin-subscriptions` | 4 | `false` | `4f355129a512842e7e96dff6e2f6274fa2565acbf3c6826655a6f0873c7351e8` | Added in this change. Production entrypoint baseline SHA-256: `a94b842e152464d180ba866dc2d4446dab2f8384fafaea746f9d82401601e19e`. Local source adds explicit owner/admin authorization and safe database error responses. |
| `admin-users` | 6 | `false` | `99c86c74a719eea40cb3318fae787c78a9a096702dd699c53a3a37c8fe8a9805` | Tracked on `main`; its deployed entrypoint matched the checked-in file in the 2026-10-09 read-only audit. The bundle also includes shared modules. |
| `admin-dashboard` | 3 | `false` | `ba97df336b9ca7f894d7fc08f10d9e6d49c76482f5606ae37bfc33ca4119bd51` | Added in this change. Production entrypoint baseline SHA-256: `508bd852b227a8367fe7cf6c2776f3e74d0d2fdd6a3d77ee8700eaef71169237`. Local source adds owner-only authorization and safe database error responses. |
| `admin-ai` | 4 | `false` | `b90348513a08e7a1fd006fe6561b587c032387e33ceba88ee9ab3ac141f0c1ea` | **Source unavailable.** Production entrypoint is a 399-byte wrapper that imports an implementation from `natefox2017/cookapp` branch `cursor/ai-platform-core-4b9d`. Both the authenticated GitHub API and raw URL returned 404 during this audit. No placeholder or empty implementation is included. |
| `health` | 8 | `true` | `7e5ee17f8b16ced8c802a0f42b5851e0c514328c81f205e0e6385ae745b0aeca` | Tracked on `main`; the source uses local shared modules. The deployed bundle hash still differs from the source-only local change and is not evidence of deployment parity. |
| `openapi` | 23 | `false` | `a7c7f0d301fe53baff101d5f53bedf44a6d82ad55f48422e47a02d04c4217f51` | Source work is in a separate module branch. The production entrypoint currently references a mutable `cookapp` branch for CORS and the OpenAPI spec. |

The function versions and bundle hashes are inventory evidence only. This branch does not claim that the new source was staged or deployed. The live `admin-ai` implementation and the full production origin of the missing functions remain source-provenance gaps until their authorized source is available.

## Source and authorization decisions

- `admin-subscriptions` keeps the production route and response contract. All four roles (`owner`, `admin`, `operator`, `readonly`) may read the plan catalog. Only `owner` and `admin` may create, update, or delete plans, or read subscription records and revenue.
- `admin-dashboard` exposes registration, user, recipe, subscription, payment, and download aggregates, including limited recent-user details. It is owner-only.
- Both handlers authenticate the custom admin session before creating a service-role client. They use the existing `admin-session.ts` and `admin-role.ts` interfaces from the repository; neither shared file nor database schema is changed here.
- Function-level Supabase JWT verification remains disabled because these endpoints authenticate the separate admin bearer session themselves. This is explicitly set in `supabase/config.toml`.
- Deno dependencies are locked per function. These handlers contain no runtime import from a mutable Git branch. Their shared code is imported from the same repository commit.
- The live production sources and downloaded bundles were scanned for common credential forms during the read-only audit. No matches were found in the scanned files. The unavailable `admin-ai` implementation could not be scanned.

## Local verification

The new HTTP tests start loopback Deno servers and send real HTTP requests for the role matrix. They inject deterministic session and database fixtures so prohibited roles can be checked before any service-client access. This verifies route-level authorization and response status locally; it does not authenticate against Supabase Auth/Postgres, exercise real administrator accounts, or prove staging or production behavior.

Commands:

```sh
deno test --frozen --allow-net=127.0.0.1 --config supabase/functions/admin-subscriptions/deno.json \
  supabase/functions/admin-subscriptions/authorization_test.ts \
  supabase/functions/admin-subscriptions/http_test.ts

deno test --frozen --allow-net=127.0.0.1 --config supabase/functions/admin-dashboard/deno.json \
  supabase/functions/admin-dashboard/access_test.ts \
  supabase/functions/admin-dashboard/http_test.ts

deno check --frozen --config supabase/functions/admin-subscriptions/deno.json \
  supabase/functions/admin-subscriptions/index.ts \
  supabase/functions/admin-subscriptions/http_test.ts

deno check --frozen --config supabase/functions/admin-dashboard/deno.json \
  supabase/functions/admin-dashboard/index.ts \
  supabase/functions/admin-dashboard/http_test.ts
```

Latest result for the two local HTTP suites: subscriptions **5 passed**, dashboard **4 passed**. Both type checks passed. These local tests do not close Issue #155.

## Staging rollout and production rollback plan

1. Build a staging project from a dedicated branch deploy directory. Do not link CLI commands to production. Before deployment, inspect `Deno.env.get` and the imported shared modules to enumerate the required secret names; configure values only in the staging secret store. Never copy production secrets into local files or test output.
2. Apply the RevenueCat event-owner binding migration in staging before testing webhook deliveries. Replay duplicate event IDs for the same owner and a conflicting owner; verify idempotency and a conflict response without changing ownership.
3. Deploy one function at a time with the `verify_jwt` value in this manifest. Run unauthenticated, invalid-session, and each administrator-role HTTP case against staging. Verify that `operator` and `readonly` receive 403 for plan writes and financial reads, and that non-owners receive 403 from `admin-dashboard`.
4. Compare each staged function's deployed bundle SHA and version to the reviewed source commit and record the secret names (never values), timestamp, smoke-test results, and prior production version. Do not test `admin-ai` until its complete authorized implementation and provider contract are available.
5. Production remains read-only until a separate, explicit release approval. If a later approved release fails, redeploy the prior reviewed source commit and matching lockfiles for that function, preserving the captured `verify_jwt` setting and server-side secret names. Record the resulting new Supabase version and bundle SHA; do not assume restoring a previous version number restores its content.

No deployment, secret change, database write, migration, or Issue closure is included in this source change.
