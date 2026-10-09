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
- **NOT RUN:** production/staging authentication, database/RLS, Storage or
  deployed health HTTP checks. The isolated local Edge Runtime and GoTrue check
  completed later and is recorded below.

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

## Local HTTP boundary check

On 2026-10-09, Deno 2.9.7 / TypeScript 6.0.3 ran the handler over an actual
`127.0.0.1` HTTP listener with `--cached-only` and network permission limited
to loopback. The normal 401 and 200 paths use the real shared `requireUser`
client pointed at a synthetic local Auth server. A separate injected-auth
case verifies that `errorResponse` maps a forbidden `AppError` to HTTP 403;
the production `requireUser` contract itself currently maps invalid Auth
responses to 401 and has no role-based 403 branch.

```sh
deno test --config=supabase/functions/health/deno.json --frozen --cached-only \
  --allow-net=127.0.0.1 \
  --allow-env=CORS_ALLOWED_ORIGINS,SUPABASE_URL,SUPABASE_ANON_KEY \
  supabase/functions/health/http_test.ts
```

This check used no production Auth token, database, internet connection, or
deployment. The 403 fixture is an error-boundary check, not evidence of a live
health authorization rule.

## Actual isolated Edge Runtime and GoTrue verification

On 2026-10-09 UTC, code snapshot
`2a586421d5ff2c982db06aca2666211c89af2f45` (PR #205 head immediately before
this documentation follow-up) was copied into a disposable local Supabase
project and served through Kong and Supabase Edge Runtime. Supabase CLI 2.120.0
ran only Postgres, GoTrue, Kong, and Edge Runtime. The project used
`issue155-edge-20261009-60181` on API/database ports 60181/60182; it did not use
staging or production.

- **Health:** anonymous, forged, and expired signed user JWT requests returned
  401. A temporary confirmed user created in local GoTrue signed in through the
  password grant; that GoTrue-issued token returned 200 from health.
- **OpenAPI:** GET returned 200 and the exact bundled document (53,455 bytes);
  every `$ref` resolved within the document. GET and OPTIONS returned wildcard
  CORS; OPTIONS returned 200. POST returned 405 with CORS headers. The served
  handler imports the bundled JSON and contains no `fetch()` call.
- The temporary user and isolated project were deleted after the check.

### Reproduce locally

From the repository root, create a fresh temporary CLI project, copy only the
shared helper and these two functions, and configure a unique project ID and
unused API/database ports. Set `[functions.health] verify_jwt = true` and
`[functions.openapi] verify_jwt = false` in its `supabase/config.toml`.

```sh
fixture=.tmp/issue-155-edge-runtime
mkdir -p "$fixture/supabase/functions"
supabase init --workdir "$fixture" --yes
cp -R supabase/functions/_shared supabase/functions/health \
  supabase/functions/openapi "$fixture/supabase/functions/"
```

In the generated config, set a unique `project_id`, use free API/database
ports (this run used 60181/60182 and shadow port 60183), and append:

```toml
[functions.health]
verify_jwt = true

[functions.openapi]
verify_jwt = false
```

Start only the services used by this check, then serve both functions through
the local Kong route. The CLI prints synthetic local keys at startup; use them
only for the temporary GoTrue user-creation and password-grant requests, and
do not copy them into logs or commit them.

```sh
supabase start --workdir "$fixture" \
  -x realtime,storage-api,imgproxy,mailpit,postgrest,postgres-meta,studio,logflare,vector,supavisor
supabase functions serve --workdir "$fixture"
```

Against `http://127.0.0.1:<api-port>`, create a confirmed synthetic user via
`/auth/v1/admin/users`, obtain its token via
`/auth/v1/token?grant_type=password`, and request
`/functions/v1/health` without a token, with a forged token, with an expired
HS256 token for that user, and with the GoTrue-issued token. For OpenAPI, GET
`/functions/v1/openapi`, resolve every `$ref` locally, send an OPTIONS request
with an Origin and requested GET method, and send POST. Expected statuses are
401/401/401/200 for health and 200/200/405 for OpenAPI GET/OPTIONS/POST.

Afterwards stop only this fixture with
`supabase stop --workdir "$fixture" --project-id <fixture-project-id> --no-backup`.
The run record is retained locally at
`.tmp/issue-155-provenance/edge-runtime-2026-10-09.md`; it is intentionally not
committed. This local check does not establish production bundle parity or
production/staging behavior.
