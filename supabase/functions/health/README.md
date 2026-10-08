# Public health dependency baseline — #155

This is a source-only, partial follow-up to #155. It does not resolve the six
production-only functions' private source provenance or deploy anything.

## Version selection

On 2026-10-08 UTC, an unmodified `main@55ac164` health type check resolved both
`jsr:@supabase/supabase-js@2` and the unversioned
`jsr:@supabase/functions-js/edge-runtime.d.ts` to **2.117.3**. This change pins
those observed versions; it does not downgrade the shared Auth client to the
separate import Worker's npm 2.57.4 dependency or upgrade that Worker.

The before/after JSR and npm dependency graphs are identical. The committed
health lockfile records transitive versions and integrity hashes. Its dedicated
`deno.json` enables frozen resolution, following the
[Supabase function-local dependency guidance](https://supabase.com/docs/guides/functions/dependencies)
and [Deno lockfile configuration](https://docs.deno.com/runtime/reference/deno_json/#lockfile).
There is no new global import map or CI workflow.

The shared Auth source is also consumed by admin-auth, delete-account,
recipe-import-artifacts and cleanup. Their shared SDK import is now exact;
this PR does not claim their **entire** dependency graphs are locked. In
particular admin-auth/delete-account retain their existing runtime typing
imports. Their separate lock/deployment work remains open.

## Actual local verification

Linux x86_64; Deno 2.9.6 / TypeScript 6.0.3; code commit `08b6c8f`.

- **PASS:** 32 deterministic tests across health Auth, shared helpers,
  admin-auth and artifact cleanup; see [complete output](validation.log).
- **PASS:** frozen type checks for health, its new test, artifact API and cleanup.
- **PASS:** additional type checks for admin-auth and delete-account with a
  temporary external lockfile; these are API-compatibility checks, not a claim
  that their deployment dependency graphs are now frozen.
- **PASS:** baseline and pinned JSR/npm graph equality, and `git diff --check`.
- **NOT RUN:** Supabase CLI bundling, actual Edge Runtime, staging/production
  authentication, database/RLS, Storage or deployed health HTTP checks. These
  remain required under #135/#141 before any release.

The two new Auth tests use only synthetic values and a fetch stub, with no
network permission. They verify a missing bearer is rejected, a user bearer and
anon API key are preserved during `getUser`, the service client uses its own
key, and invalid credentials are mapped to 401. Environment and fetch stubs
are restored after the test. These are not real JWT/signature validation tests.

## Reproduce

From the repository root, after installing Deno and caching registry dependencies:

```sh
deno check --config=supabase/functions/health/deno.json --frozen \
  supabase/functions/health/index.ts \
  supabase/functions/health/auth_test.ts \
  supabase/functions/recipe-import-artifacts/index.ts \
  supabase/functions/purge-expired-recipe-import-artifacts/index.ts

deno test --config=supabase/functions/health/deno.json --frozen \
  --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY \
  supabase/functions/health/auth_test.ts \
  supabase/functions/_shared/*_test.ts \
  supabase/functions/admin-auth/*_test.ts \
  supabase/functions/purge-expired-recipe-import-artifacts/*_test.ts
```

The test log's service-error strings are synthetic regression fixtures. No
production secret or user record is required. Local success does not authorize
or imply a deployment; #155 must remain open for its other acceptance criteria.
