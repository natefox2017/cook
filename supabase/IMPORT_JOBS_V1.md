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
- Results live in the private job payload. `ios/Recipe/Services/RecipeRemoteImportService.swift` now provides **an authenticated iOS create/query/retry adapter** and a conservative `saveCompletedTextJob` mapper into the existing RecipeStore. The adapter is **not yet invoked by the draft Share inbox/UI** (#72), so foreground polling, automatic receipt→job submission, result handoff, per-owner lifecycle and real signed-device acceptance are still outstanding. The mapper deliberately refuses to overwrite a recipe that already exists locally, preserving user edits; original pasted text stays attached.

## Files

- `supabase/migrations/20261008155000_recipe_import_jobs_v1.sql`: owner-scoped jobs, SELECT RLS, transactional create/retry RPCs, worker claim and permissions.
- `supabase/functions/recipe-imports/index.ts`: user-authenticated HTTP create/query/retry.
- `supabase/functions/recipe-import-worker/index.ts`: secret-authenticated durable queue worker.
- `supabase/functions/recipe-import-worker/textEvidence.ts` and `textEvidence_test.ts`: narrow deterministic text parser and tests.
- `supabase/config.toml`: verifies end-user JWT for API; cron worker must validate its separately configured secret.
- `ios/Recipe/Services/RecipeRemoteImportService.swift`: native authenticated transport, progress lookup and guarded text-to-RecipeStore mapping. This is code prepared for #30's future inbox handoff, **not** an already-working app flow.

## 2026-10-08 source audit and lease-fencing changes

- **SQL idempotency:** original user source bytes remain in `source_value`, while the trimmed copy is used only for basic input validation and an index hint. Repeating the exact same `client_request_id` and original text with leading/trailing whitespace now returns the existing job rather than a false 409. Changing the original text with the same request ID still conflicts.
- **Worker lease fencing:** terminal `failed`/`completed` updates now compare both `queue_message_id` and the attempt number returned by `claim_recipe_import_job`. When a visibility timeout permits a fresh claim, a stale worker cannot overwrite the new attempt's final status or result. The losing worker must leave the message unacknowledged.
- **SQL source audit:** one definition each of submit/retry/claim is present; the accidental earlier concatenation has not recurred. This is a source-level check, **not PostgreSQL syntax/runtime proof**.
- **Read-only production check:** the legacy queue is `pgmq` 1.5.1, with 0 pending and 1 archived message at inspection, and `public.recipe_import_jobs` is still absent. The legacy `recipe_import_enqueue` function still writes `pending/running/imported` and references columns absent from this V1 table. Do not call that function on V1 jobs or deploy before checking consumers and DB migration compatibility.
- **Required database regressions:** (1) exact whitespace-bearing request replay -> same job ID; (2) same request ID with different raw text -> conflict; (3) worker A claims attempt N, times out, worker B claims attempt N+1, then A's fenced write changes **zero rows**; (4) B persists final result before ACK; (5) account A cannot query or retry account B's job. Run on a disposable database with real authenticated roles before deploying.

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
