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

The Deno HTTP tests start loopback servers and exercise the role gates with deterministic injected dependencies. A second integration run below used the actual local Supabase Edge Runtime, GoTrue health service, PostgreSQL schema, service-role client and persisted admin sessions.

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

### Local Supabase HTTP integration

On 2026-10-09, a separate disposable project `issue155-http-57481` ran on API port `57481` and database port `57482`, isolated from the other local Supabase stack. Runtime versions were Supabase CLI 2.120.0, PostgreSQL 17.11, Edge Runtime 1.77.4 and Deno 2.1.4. The GoTrue health endpoint returned HTTP 200.

The database used the schema-only #140 production catalog export for admin tables and `profiles`, plus a local schema-only subset for tables used by these two handlers. The extra table definitions came from read-only production catalog queries for columns, defaults and constraints. The catalog indexes were inspected; the local harness did not reproduce non-unique performance indexes. No production rows or credentials were copied. A synthetic owner was created through the local `admin-auth/bootstrap` route and production-derived `admin_bootstrap_owner` RPC. Synthetic `admin`, `operator` and `readonly` rows were added only to this disposable database; all four roles then logged in through the actual local `admin-auth/login` function and received persisted `admin_sessions` rows. Each `/admin-auth/session` request returned HTTP 200 with its expected role.

| Local HTTP request | owner | admin | operator | readonly |
| --- | ---: | ---: | ---: | ---: |
| `GET /admin-subscriptions/plans` | 200 | 200 | 200 | 200 |
| `GET /admin-subscriptions/records` | 200 | 200 | 403 | 403 |
| `GET /admin-subscriptions/revenue` | 200 | 200 | 403 | 403 |
| `POST /admin-subscriptions/plans` | 201 | 201 | 403 | 403 |
| `PUT /admin-subscriptions/plans/{id}` | 200 | 200 | 403 | 403 |
| `DELETE /admin-subscriptions/plans/{id}` | 200 | 200 | 403 | 403 |
| `GET /admin-dashboard` | 200 | 403 | 403 | 403 |

Missing and invalid sessions returned 401 on both functions. The local plan row was created, updated and deleted through the real HTTP handlers and local PostgREST database. This confirms the two handlers' route and SQL behavior against the checked-in source with a production-derived schema subset. It is still local evidence, not hosted staging or production acceptance.

## Admin AI recovery plan and source gap

### Source search and read-only database evidence

- `git log --all --full-history -- supabase/functions/admin-ai` and `git rev-list --all --objects` contain no tracked `admin-ai` source path or blob. The scoped search of the known #155 worktrees found only the downloaded production wrapper under `.tmp/issue-155-live`; that 399-byte file imports implementation from the inaccessible `natefox2017/cookapp` feature branch. The wrapper's raw GitHub URL and authenticated repository lookup both returned 404.
- A read-only production catalog query on 2026-10-09 found six AI tables: `ai_providers`, `ai_models`, `ai_routes`, `ai_secrets`, `ai_provider_health`, and `ai_usage_events`. RLS is enabled (not forced) on each. No policies were listed. `anon` and `authenticated` have no SELECT privilege; `service_role` has SELECT/INSERT/UPDATE/DELETE on all six. No public routines named `ai_*` or `llm_*` were found.
- Catalog columns are: `ai_providers` — `id`, `name`, `protocol`, `base_url`, `secret_ref`, `enabled`, `request_timeout_ms`, `max_retries`, `status`, `last_health_check_at`, `environment`, `metadata`, timestamps; `ai_models` — `id`, `provider_id`, `display_name`, `upstream_model_id`, `enabled`, `capabilities`, `context_window`, `max_output_tokens`, input/output cost fields, `metadata`, timestamps; `ai_routes` — `id`, `route_key`, `primary_model_id`, `fallback_model_ids`, timeout/retry/temperature/output limits, `structured_schema_key`, `enabled`, `reserved`, timestamps; `ai_secrets` — `id`, `secret_ref`, `ciphertext`, `nonce`, `key_version`, timestamps; `ai_provider_health` — `provider_id`, `status`, success/error timestamps, `last_error`, `consecutive_failures`, `circuit_open_until`, `updated_at`; `ai_usage_events` — request/route/provider/model IDs, status, latency, input/output tokens, estimated cost, retry/error/attempt metadata, user/admin IDs, source job ID, timestamp.
- The live `ai_usage_events` schema records request/route/provider/model IDs, final model, status, latency, input/output tokens, estimated cost, retries, error code, attempted models, user/admin IDs, source job ID and timestamp. It has no cached-input-token column. The UI treats cached input and average latency as optional; average latency can be aggregated from `latency_ms`, while cached-input usage must remain absent/null unless the source owner confirms another telemetry source.
- `ai_models.provider_id` and `ai_provider_health.provider_id` cascade from providers; `ai_routes.primary_model_id` and usage-event model/provider references use `ON DELETE SET NULL`. Provider `secret_ref` references `ai_secrets.secret_ref` with `ON DELETE SET NULL`. The provider/model/route schema contains enabled flags, retry/timeout bounds, model capabilities, cost fields and fallback model IDs. The UI exposes only a single provider/model projection, so the exact CRUD mapping must preserve the broader routing data.

### Recoverable admin UI contract

The current `admin/src/api.ts`, `admin/src/types.ts`, `admin/src/App.tsx` and `admin/src/pages/LLMPage.tsx` define these routes. The admin portal routes the LLM page only to `owner/admin`; the page also gates provider write actions to those roles:

| Route | UI request/response contract |
| --- | --- |
| `GET /providers` | `{ data: LLMProvider[] }`; each item has `id`, `name`, `baseUrl`, `model`, `active`, `apiKeyConfigured`, `updatedAt`. |
| `POST /providers` | `{ name, baseUrl, model, apiKey, active }`; returns one `LLMProvider`. |
| `PUT /providers/{id}` | Same body; an empty `apiKey` means preserve the saved key. Returns one `LLMProvider`. |
| `DELETE /providers/{id}` | Returns `{ ok: true }`. |
| `POST /providers/test` | `{ providerId?, name, baseUrl, model, apiKey? }`; returns `{ ok, message? }`. An omitted key for an existing provider means test with its saved key. |
| `GET /usage?range=7d|30d|90d` | Totals, date series and by-model request/token aggregates; cached input and average latency are optional. |

The UI makes provider-management actions available to `owner` and `admin` and shows keys as write-only. It sends provider keys only to an HTTPS function origin and rejects redirects for save/test requests. The backend must enforce the same role boundary, never return or log keys, preserve a blank key on edit, validate provider URLs and redirects against SSRF/private-network access, and bound connection-test time and response size.

### What can be rebuilt from the current contract

The provider CRUD projection, test route, usage range query, safe key-configured flag, owner/admin checks, and token/latency aggregation can be implemented from the UI and live table structure. The implementation should keep `ai_routes` fallback/model relationships intact and use the existing `ai_providers`/`ai_models`/`ai_secrets` data model instead of introducing parallel tables.

The complete former `admin-ai` source is still needed to resolve the provider-to-model projection, encrypted-secret write/read protocol, encryption-key custody and environment name, whether connection tests persist `ai_provider_health`, usage bucket timezone/retention semantics, route deletion policy and any provider-specific compatibility behavior. The wrapper comment mentions `COOKAPP_AI_MASTER_KEY`, but that name and the encryption format are not independently confirmed. Do not implement or deploy these unresolved storage/security behaviors by guessing. Recover the authorized function source or obtain the source owner's explicit data-mapping and key-custody contract first.

## Staging rollout and production rollback plan

1. Build a staging project from a dedicated branch deploy directory. Do not link CLI commands to production. Before deployment, inspect `Deno.env.get` and the imported shared modules to enumerate the required secret names; configure values only in the staging secret store. Never copy production secrets into local files or test output.
2. Apply the RevenueCat event-owner binding migration in staging before testing webhook deliveries. Replay duplicate event IDs for the same owner and a conflicting owner; verify idempotency and a conflict response without changing ownership.
3. Deploy one function at a time with the `verify_jwt` value in this manifest. Run unauthenticated, invalid-session, and each administrator-role HTTP case against staging. Verify that `operator` and `readonly` receive 403 for plan writes and financial reads, and that non-owners receive 403 from `admin-dashboard`.
4. Compare each staged function's deployed bundle SHA and version to the reviewed source commit and record the secret names (never values), timestamp, smoke-test results, and prior production version. Do not test `admin-ai` until its complete authorized implementation and provider contract are available.
5. Production remains read-only until a separate, explicit release approval. If a later approved release fails, redeploy the prior reviewed source commit and matching lockfiles for that function, preserving the captured `verify_jwt` setting and server-side secret names. Record the resulting new Supabase version and bundle SHA; do not assume restoring a previous version number restores its content.

No deployment, secret change, database write, migration, or Issue closure is included in this source change.
