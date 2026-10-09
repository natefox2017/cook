# Import regression execution — Issue #134

Executed 2026-10-08 UTC on Linux x86_64, against code commit `51020c9`
(`main@55ac164` plus the focused fixes for #164 in this PR). No production data, provider credentials, database,
or Apple runtime was used. CI configuration is unchanged.

## Results

- **PASS:** Python 3.12.14 / jsonschema 4.26.0: 25 contract fixtures
  (12 positive, 13 negative) and all 5 OpenAPI reference unit tests.
- **PASS:** Deno 2.9.6 / TypeScript 6.0.3: all 59 deterministic tests;
  the opt-in public-network test was **not run** (1 ignored).
- **PASS:** `deno check` on the actual import worker entry point.
- **BLOCKED:** SQL ACL/RLS/queue integration: no isolated PostgreSQL/Supabase
  runtime is configured here. Never substitute production for this check.
- **NOT RUN:** Swift, Xcode, simulator/device, live OCR, actual Edge Runtime,
  remote Storage and public-source integration. See #126, #135 and #138.
- #134 remains open for SQL acceptance and any new merged test coverage.
  Open PRs #152 and #158 were not included in this main-based checkout.

Complete successful fixture output: [Python](issue-134-python.log) and
[Deno](issue-134-deno.log). The synthetic failure messages printed by the
redaction and Storage tests are expected fixtures, not live credentials/errors.

## Failures found and fixed

The first full type check on `main@81541bc` reported five errors before
running tests. The final run also includes subsequently merged #162/#163:

1. `approvedOCRProvider.ts`: a general `Uint8Array<ArrayBufferLike>` is not a
   valid fetch `BodyInit`. Copying the supplied view into a new `Uint8Array`
   creates an ArrayBuffer-backed body without including bytes outside the view.
   A mocked request regression covers a SharedArrayBuffer-backed subview.
2. `artifactText.ts`: a failed ownership/expiry check does not imply the row
   lacks the `PrivateArtifactRow` shape. Its type predicate incorrectly narrowed
   rejected rows to `never`, breaking four existing negative-case assertions.
   Return a boolean; preserve every runtime authorization check and assertion.

The first runtime pass also identified four missing fixture-read permissions in
this invocation. The successful command below grants only the two fixture
folders, rather than unrestricted filesystem access. No test was removed or
weakened and no type check was skipped.

## Reproduce from the repository root

Use Python with `jsonschema>=4.21` and Deno 2.9.6. Dependencies use the existing
worker import map and frozen lockfile. The initial dependency cache fill may
need registry access; the tests have no runtime network permission.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 docs/import-fixtures/validate_contract.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
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
```

In the test environment Deno's inherited SOCKS proxy initially refused
connections. Pointing `ALL_PROXY`/`all_proxy` at the already configured HTTPS
proxy and setting `DENO_CERT` to the existing `SSL_CERT_FILE` allowed the official
registry fetches. TLS verification remained enabled; neither setting is a
repository or production configuration requirement.
