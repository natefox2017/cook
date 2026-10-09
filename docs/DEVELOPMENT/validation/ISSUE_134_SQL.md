# Actual isolated SQL execution — #134

Executed 2026-10-09 UTC, Linux x86_64, Node 24.19.0, PostgreSQL 18.3 in
PGlite 0.5.8, pgTAP 1.3.5, PGMQ 1.11.1. Base: `main@55ac164`.

## First real run and fix

Unchanged ACL suite: **20/20 PASS**. Unchanged queue suite: **38/39 PASS**.
Assertion 19 expected `23505 CLIENT_REQUEST_ID_CONFLICT` for a changed source,
but called the obsolete defaulted internal RPC and received `42501` instead.
The source-preservation migration correctly revoked that internal entry point.

The test now calls the current five-argument RPC, holding platform and original
URL constant and changing only source content. The original conflict assertion
is preserved. A separate real invocation asserts the obsolete endpoint still
returns `42501`; grants and production migrations are unchanged.

## Final clean-install results

- **PASS:** `npm ci --ignore-scripts` from the committed exact-version lock.
- **PASS:** `NODE_OPTIONS=--max-old-space-size=256 npm test`: **84/84 pgTAP assertions** across 3 suites.
  - 20 legacy function privilege assertions (signature-only fixture bodies).
  - 40 real queue/owner/idempotency/worker attempt/retry assertions.
  - 24 snapshot CAS and private artifact/owner/expiry/anonymous-role assertions.
- **PASS:** `git diff --check`.
- An unrestricted-heap clean-install rerun was killed by the host before TAP
  output. Retrying with the Node heap bounded to 256 MiB completed all 84
  assertions; the earlier complete run also passed. This is not a production
  memory benchmark.
- **NOT RUN:** actual Supabase Auth/Storage HTTP, external endpoints, legacy
  backend business logic, two-session contention, production or deployment.

[Full stdout](issue-134-sql.log). Commands and exact synthetic-platform / omitted
legacy-migration boundaries are documented in
[the isolated harness](../../../supabase/tests/isolated/README.md).

This removes the earlier blanket “no local SQL runtime” blocker for the listed
suites. It does **not** close #134 or the controlled Supabase/security/deployment
acceptance tasks, and does not claim any production permission changed.
