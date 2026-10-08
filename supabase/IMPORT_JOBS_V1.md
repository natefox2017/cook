# Import Jobs V1 — implementation and deployment boundary

This directory adds the **first server job/queue slice** for [Issue #31](https://github.com/natefox2017/cook/issues/31). It uses existing `cookapp` Supabase and the existing durable `pgmq.q_recipe_import` queue. It does not add a competing queue, app database or AI provider.

## Data flow

- The signed-in user calls `POST /functions/v1/recipe-imports` with a validated `client_request_id` and a text or HTTPS URL source. This is the implementation of planned OpenAPI `POST /recipe-imports`. **Image/file artifact references are rejected as unavailable**, not silently marked received.
- `recipe-imports` authenticates the bearer token against Supabase Auth. Owner is derived from the verified token again in `submit_own_recipe_import` via `auth.uid()`, never accepted in JSON. Anonymous-auth users are not eligible.
- The SQL RPC locks per owner, checks a 30-new-jobs/hour limit and `(owner_id,client_request_id)` uniqueness, creates a private job row and sends PGMQ message **in the same database transaction**. Only then does the response advertise `queued`. If insertion, queue send or commit fails, no false queued job is acknowledged.
- `GET /functions/v1/recipe-imports/{job_id}` fetches only the signed-in owner's job (RLS + explicit owner predicate). `POST /.../{job_id}/retry` reuses the existing job when its failed error is recoverable and attempts remain, with transactional queue re-admission.
- `recipe-import-worker` is service-only and triggered by an authenticated secret. It uses existing restricted `recipe_import_queue_read` and `recipe_import_queue_archive` RPCs plus the new server-only atomic claim. Unacknowledged messages become visible again; stale claims can be retried up to three attempts. **Queue archive occurs only after the job result is persisted.**
- For **pasted text**, the small evidence-first extractor reads explicit Ingredients/Steps headings in English/Chinese/Japanese, preserves vague amounts as null normalization and marks incomplete results `needs_review`.
- For **remote URLs/videos**, this slice intentionally returns a truthful `UNSUPPORTED_SOURCE` with the original source retained. Do **not** fetch arbitrary client URLs from an Edge Function without DNS-pinned, redirect-by-redirect SSRF validation and limits. This remains further work in #31.
- Results live in the private job payload; the main iOS app does **not yet** poll and upsert them into RecipeCore. Client handoff, media storage, production URL/video evidence, provider routing, owner separation and device acceptance are outstanding, so #31 must stay open.

## Files

- `supabase/migrations/20261008155000_recipe_import_jobs_v1.sql`: owner-scoped jobs, SELECT RLS, transactional create/retry RPCs, worker claim and permissions.
- `supabase/functions/recipe-imports/index.ts`: user-authenticated HTTP create/query/retry.
- `supabase/functions/recipe-import-worker/index.ts`: secret-authenticated durable queue worker.
- `supabase/functions/recipe-import-worker/textEvidence.ts` and `textEvidence_test.ts`: narrow deterministic text parser and tests.
- `supabase/config.toml`: verifies end-user JWT for API; cron worker must validate its separately configured secret.

## Required verification before production migration/deploy

Do not infer success from source code, lightweight PR auto-merge or an existing PGMQ table. On a disposable branch/database, validate:

1. Apply migration with Supabase CLI and check `pg_policies`, table grants, function grants, `security definer` owner checks and security advisors. The repo timestamp was authored without a working CLI in this environment; generate/reconcile migration history with the project CLI before merging.
2. Run `deno test supabase/functions/recipe-import-worker/textEvidence_test.ts` and `deno check` on both functions. Execute negative tests for 401, anonymous session, request ID reuse with changed source (409), invalid/private URL, unsupported artifacts (422), quota (429), cross-account GET (404) and direct INSERT/UPDATE/DELETE denial.
3. With a real signed-in test account, POST text and verify one PGMQ message + `queued` and a visible stored job. Duplicate concurrent POST must produce one job. Worker must mark it completed with `ready` or `needs_review`, preserve original evidence and archive only after persisted result.
4. Force worker interruption after claim and after DB result write; verify visibility retry, stale claim recovery, idempotent completion, no false queued/ack and attempt cap. Confirm retries never create duplicate recipes.
5. Verify the old service-only `recipe_import_enqueue` helper, which expects legacy `pending/running/imported` statuses, is not used with the new V1 lifecycle. It predates the V1 job table and must be explicitly retired/adapted after checking existing Admin Dashboard consumers.
6. Configure `RECIPE_IMPORT_WORKER_SECRET` server-side and schedule a trusted Cron invocation; configure no provider secret in the iOS app. Do not deploy a public worker without this secret. Confirm `recipe-import-worker` rejects missing/wrong secrets.
7. Complete real source URL/video extraction, per-hop SSRF defence, artifact upload/retention, client polling and result upsert before calling #31 or #34 production-ready.

**Environment observed 2026-10-08:** Supabase `cookapp` reported ACTIVE_HEALTHY, queue `pgmq.q_recipe_import` exists and is logged, and `public.recipe_import_jobs` did not exist. There is no deployed recipe import worker/function yet. This PR does **not** apply a production migration or deploy any Edge Function.

Reference: [Supabase Queues](https://supabase.com/docs/guides/queues), [Consuming messages with Edge Functions](https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions), [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth).
