# Actual isolated SQL execution — #134

Re-executed 2026-10-09 on macOS arm64 with Node 24.21.0 against
`origin/main` / `HEAD` at `21866ec99bb9081e9f4312cde488ad63276ba7b6`.
The disposable database is PostgreSQL 18.3 in PGlite 0.5.8, with pgTAP 1.3.5
and PGMQ 1.11.1. No database URL or credential is accepted by the harness.

## Historical first run and fix

Unchanged ACL suite: **20/20 PASS**. Unchanged queue suite: **38/39 PASS**.
Assertion 19 expected `23505 CLIENT_REQUEST_ID_CONFLICT` for a changed source,
but called the obsolete defaulted internal RPC and received `42501` instead.
The source-preservation migration correctly revoked that internal entry point.

The test now calls the current five-argument RPC, holding platform and original
URL constant and changing only source content. The original conflict assertion
is preserved. A separate real invocation asserts the obsolete endpoint still
returns `42501`; grants and production migrations are unchanged.

## Latest clean-install results

- **PASS:** `npm ci --ignore-scripts` from the committed exact-version lock.
- **PASS:** `NODE_OPTIONS=--max-old-space-size=256 npm test`: **85/85 pgTAP assertions** across 3 suites.
  - 20 legacy function privilege assertions (signature-only fixture bodies).
  - 40 real queue/owner/idempotency/worker attempt/retry assertions.
  - 25 snapshot CAS and private artifact/owner/expiry/anonymous-role assertions.
- **PASS:** `git diff --check`.
- The latest clean-install run completed in one process with exit 0. This is
  isolated database evidence, not a production memory benchmark.
- **NOT RUN:** actual Supabase Auth/Storage HTTP, external endpoints, legacy
  backend business logic, two-session contention, production or deployment.

[Full stdout](issue-134-sql.log), including `npm ci --ignore-scripts`.
Commands and exact synthetic-platform / omitted legacy-migration boundaries are documented in
[the isolated harness](../../../supabase/tests/isolated/README.md).

This removes the earlier blanket “no local SQL runtime” blocker for the listed
suites. It does **not** close #134 or the controlled Supabase/security/deployment
acceptance tasks, and does not claim any production permission changed.
