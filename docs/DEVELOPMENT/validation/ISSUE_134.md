# Import regression execution — Issue #134

## Latest main rerun

Executed 2026-10-09 on macOS arm64 against `origin/main` / `HEAD` at
`21866ec99bb9081e9f4312cde488ad63276ba7b6`. The checkout was clean before
execution. Python, Deno, and SQL fixtures ran locally; no production database,
provider credential, Apple account, hosted Edge Runtime, or deployment was
used. CI configuration is unchanged.

- **PASS:** Python 3.11.16 / jsonschema 4.26.0 validated 25 import fixtures
  (12 positive, 13 negative); all 5 OpenAPI-reference unit tests passed.
- **PASS:** Deno 2.9.7 / TypeScript 6.0.3 ran all 61 deterministic tests in
  the Issue #134 import/worker suite selection: 0 failed. The opt-in live
  public-network test was **ignored** (1); no runtime network permission was
  granted.
- **PASS:** `deno check` on the actual `recipe-import-worker/index.ts` entry
  point with the worker config and frozen lockfile (exit 0).
- **PASS:** Node 24.21.0 ran all 85 pgTAP assertions against disposable
  PostgreSQL 18.3 in PGlite 0.5.8: 20 ACL, 40 queue, and 25 snapshot/artifact
  assertions. The harness uses synthetic Auth/Storage fixtures and cannot
  connect to production.
- **NOT RUN:** actual Supabase Auth/Storage HTTP, legacy private business
  migration bodies, two-session concurrency, hosted Edge Runtime, live OCR,
  production, and deployment. See the explicit harness limits in
  [the isolated SQL harness](../../../supabase/tests/isolated/README.md).
- `supabase/functions/health/auth_test.ts` is outside #134's documented
  import/worker suite selection and was not run. The opt-in worker live-network
  test remained ignored.
- **#134 is now CLOSED for its recorded isolated local-suite scope.** The listed local suites passed, but this is not hosted
  integration or production acceptance and does not cover the omitted legacy
  migration suites.

Complete outputs: [Python](issue-134-python.log), [Deno](issue-134-deno.log),
and [isolated SQL](issue-134-sql.log). Test-generated redaction and Storage
failure messages are synthetic fixtures, not live secrets or service errors.

## Reproduce from the repository root

The Python dependency was installed into an ignored task-local environment.
Deno used the checked-in worker import map and frozen lockfile. SQL uses only
the pinned dev dependencies in `supabase/tests/isolated/package-lock.json`.
Dependency installation may require registry access; test execution itself
does not require external service access.

```sh
uv venv --python python3.11 .tmp/issue-134-20261009/python-env
uv pip install --python .tmp/issue-134-20261009/python-env/bin/python 'jsonschema>=4.21'
.tmp/issue-134-20261009/python-env/bin/python docs/import-fixtures/validate_contract.py
.tmp/issue-134-20261009/python-env/bin/python -m unittest discover \
  -s docs/import-fixtures -p 'test_*.py' -v

RECIPE_IMPORT_LIVE_TEST=0 deno test \
  --config=supabase/functions/recipe-import-worker/deno.json --frozen \
  --allow-read=docs/import-fixtures,supabase/functions/recipe-import-worker/fixtures \
  --allow-env=RECIPE_IMPORT_LIVE_TEST,CORS_ALLOWED_ORIGINS \
  supabase/functions/recipe-import-worker/*_test.ts \
  supabase/functions/_shared/*_test.ts \
  supabase/functions/recipe-imports/*_test.ts \
  supabase/functions/admin-auth/*_test.ts \
  supabase/functions/purge-expired-recipe-import-artifacts/*_test.ts \
  docs/import-fixtures/contract-evidence_test.ts

deno check --config=supabase/functions/recipe-import-worker/deno.json --frozen \
  supabase/functions/recipe-import-worker/index.ts

cd supabase/tests/isolated
npm ci --ignore-scripts
NODE_OPTIONS=--max-old-space-size=256 npm test
```

## Previously fixed regressions

The initial full worker type check on `main@81541bc` found five errors before
tests could run. Subsequent fixes were merged before this latest-main rerun:

1. `approvedOCRProvider.ts` now copies a supplied byte view into an
   ArrayBuffer-backed fetch body without including bytes outside the view; a
   mocked regression covers a SharedArrayBuffer-backed subview.
2. `artifactText.ts` now returns a boolean for ownership/expiry checks rather
   than incorrectly narrowing rejected rows to `never`; runtime authorization
   checks and negative-case assertions remain intact.
3. The isolated queue test now calls the current five-argument RPC for the
   changed-source idempotency conflict and separately verifies that the
   obsolete endpoint remains inaccessible.

No test was removed or weakened. The Python, Deno, and SQL test sources and
complete output are in the linked log files above.
