# RecipePouch Supabase release and verification

> Deployments of production database migrations and functions are gated by
> [#140](https://github.com/natefox2017/cook/issues/140),
> [#141](https://github.com/natefox2017/cook/issues/141) and
> [#135](https://github.com/natefox2017/cook/issues/135).
> A merged PR is **not** evidence that the backend has been deployed.

## Environments and boundaries

- Project: `cookapp` (`semsjyrqjnumpvanibip`), production.
- App: `ios/Recipe`, signed-in Supabase Auth user JWT, publishable key only.
- Service: `supabase/functions`; service-role secret never reaches the App.
- Data: owner-scoped `user_snapshots`, import jobs, private storage artifacts.
- Existing admin-only RLS tables intentionally have **no public policies**.
  Do not add permissive policies merely to silence an informational advisor.

Before staging, capture the remote migration history, DB schema, Edge function
versions, bucket metadata, advisors and a recovery point. Compare with
`supabase/migrations/`. Production currently has duplicate-named snapshot
migrations (`20261008061916` and `20261008062013`); **do not** rewrite
migration history or rerun prior versions blindly.

## Staging migration order

Apply missing migration versions only, in dependency order, in an isolated
Supabase branch/test project after checking snapshot history drift:

1. `20261008103818_restrict_untrusted_security_definer_rpcs.sql` — removes
   public/admin SECURITY DEFINER entry points; admin Edge function uses service role.
2. `20261008155000_recipe_import_jobs_v1.sql` — owner-scoped import jobs and
   dedicated logged PGMQ queue.
3. `20261008195255_preserve_recipe_import_source_url.sql` — source metadata.
4. `20261008200000_recipe_import_artifacts_v1.sql` — private artifact table,
   storage bucket and artifact-import RPC.
5. `20261009014500_security_performance_hardening.sql` — 30 equivalent owner
   RLS policy expressions, 5 foreign-key indexes and 5 fixed search paths.

Confirm the existing `user_snapshots` revision-checked write RPC remains the
only authenticated mutation route; direct authenticated UPDATE and DELETE
must stay revoked. Check API roles individually: `anon`, `authenticated`,
`service_role`. `service_role` is allowed to bypass RLS only on the server.

Run the included database pgTAP suites using `supabase test db` against a
disposable environment with all prerequisite schema migrations applied. Do
not run fixture-inserting tests on production.

## Function configuration

Deploy code from the **same commit** as the tested migrations:

| Edge function | Gateway JWT verification | Additional authentication |
| --- | --- | --- |
| `recipe-imports` | enabled | user + owner-scoped RPC / RLS |
| `recipe-import-artifacts` | enabled | user + owner-scoped artifact lookup |
| `recipe-import-worker` | disabled | `x-recipe-worker-secret` |
| `purge-expired-recipe-import-artifacts` | disabled | server-only bearer token |
| `delete-account` | enabled | user JWT, server-side storage cleanup |
| `admin-auth` | disabled | distinct admin token / bootstrap gate |

Set `RECIPE_IMPORT_WORKER_SECRET` and
`RECIPE_IMPORT_ARTIFACT_CLEANUP_SECRET` to independent, high-entropy values
in Supabase secrets. Neither is an iOS config value or a checked-in token.
Grant the scheduler access to these secrets server-side. Dispatch the worker
periodically and the cleanup endpoint **daily**; log executions and alert on
queue backlog, repeated 503s and stuck expired artifacts. Do not put live
credentials, signed URLs, JWTs or user source text in logs or GitHub Issues.

## Minimum release acceptance

- A/B accounts: direct RLS and REST lookup of another owner's job/artifact/
  snapshot denied, including repeated requests.
- Sync: first-login consent, manual upload, offline edits, CAS race, conflict
  resolution, sign-out and account switching; no upload on failed first read.
- Import: submit with request UUID, replay idempotency, validation failures,
  queue claim, worker, terminal response, recoverable retry and archived ACK.
- Storage: upload intent, private signed upload, content verification, repeated
  completion, bounded download URL, idempotent deletion and expired cleanup.
- Verify worker rejects all calls without its secret and always fences claims.
- Check Supabase security/performance advisors and explain residual warnings.
  Run `deno test` for the isolated `*_test.ts` files, including
  `functions/_shared/errors_test.ts`; do not run network-dependent live tests
  against production.

Record staging command output and masked traces with the exact commit SHA,
migration versions, Edge versions, HTTP status and final DB mutation.
Confirm a rollback strategy before the separate production release window.
For a migration failure, restore from the planned recovery point or deploy a
forward migration; never delete user data or casually drop the job queue.

## References

- [Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase database tests](https://supabase.com/docs/guides/local-development/testing/overview)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase Queues](https://supabase.com/docs/guides/queues)
