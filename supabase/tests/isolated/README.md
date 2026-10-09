# Isolated PostgreSQL regression checks

This manual harness runs **real PostgreSQL 18.3**, pgTAP 1.3.5 and PGMQ 1.11.1
inside PGlite 0.5.8. It creates a disposable in-memory database, takes no URL or
credentials, and closes it afterward. It cannot target production. There is no
new CI gate and none of these packages is an app/backend runtime dependency.

## Run

Node 22+ and npm are required. All three development dependencies and their
integrities are pinned in `package-lock.json`, from the official npm registry.

```sh
cd supabase/tests/isolated
npm ci --ignore-scripts
NODE_OPTIONS=--max-old-space-size=256 npm test
```

Installation needs registry access; test execution is offline. Do not pass a
Supabase database URL, service-role key, JWT, or any user data. Synthetic UUIDs,
JWT-claim settings and document metadata are contained in the fixture files.

The runner applies an explicit list of **unchanged repository migrations** and
executes the original ACL suite, the current queue suite, and the new snapshot /
artifact boundary suite. It fails on SQL errors, failed TAP assertions, missing
plans, and mismatched assertion counts. RLS tests switch to the real
`authenticated` role and two different synthetic subjects; the new test verifies
that this role is neither superuser nor BYPASSRLS. Privileged setup/inspection is
separate from those assertions. The `service_role` fixture intentionally bypasses
RLS, matching the worker privilege boundary.

## What this does and does not prove

- Actual database engine execution of ACL changes, RLS, owner checks, snapshot
  revision compare-and-swap, import idempotency, PGMQ admission/read/archive,
  worker attempt claims, owner retry, and private artifact expiry/admission.
- `bootstrap.sql` supplies a **minimal synthetic** `auth.users`, `auth.uid()`,
  `auth.jwt()` and `storage.buckets`. It does not emulate GoTrue, PostgREST,
  Storage HTTP, real JWT verification, object signing/deletion or Edge Functions.
- The five legacy SECURITY DEFINER functions are **nonfunctional signature-only
  stubs** that throw if invoked. Their actual public grant/revoke migration and
  20 original ACL assertions run; private function bodies and admin workflows do
  not. They are never copied from a private repository or deployed.
- `20261008062415_harden_recipe_import_queue_worker_rpcs.sql` and
  `20261009014500_security_performance_hardening.sql`, plus the corresponding
  legacy performance suite, need legacy objects absent from this repository.
  They are explicitly **not in this harness**. No migration is stripped or
  altered to pretend it ran. Staging schema drift validation is still required.
- Single-connection PGlite cannot establish concurrent database-session race
  behavior or production performance. This is not hosted Supabase, its pinned
  production Postgres/extension versions, or deployment/production acceptance.

#134 was CLOSED after local-suite evidence. #135/#141 are CLOSED not_planned (historical); #140 is CLOSED. #155 remains OPEN for admin/webhook acceptance, while new AI/public-share staging uses #250 and selected-release QA #251. Prior suites did not prove
their distinct controlled integration and/or deployment evidence.
