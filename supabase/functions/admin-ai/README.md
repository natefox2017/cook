# Admin AI Edge Function

This replacement follows the current admin UI provider fields and the verified
schema recorded in `supabase/ISSUE_155_EDGE_FUNCTION_SOURCE_MANIFEST.md`. It is
not recovered source or deployed bundle parity. No production deployment,
production secret inspection, or production data change is part of this work.

## HTTP contract

All six operations require a valid custom admin session with `owner` or `admin`
role. End-user JWTs do not substitute for admin sessions.

| Method | Path                        | Request / response                                                                                 |
| ------ | --------------------------- | -------------------------------------------------------------------------------------------------- |
| GET    | `/providers`                | `{data: Provider[]}`                                                                               |
| POST   | `/providers`                | Provider input, including a nonempty `apiKey`; returns Provider                                    |
| PUT    | `/providers/{id}`           | Provider input; blank `apiKey` preserves the existing reference; returns Provider                  |
| DELETE | `/providers/{id}`           | Returns `{ok:true}` only when unreferenced                                                         |
| POST   | `/providers/test`           | One-time Provider input with a key, or `{providerId}`; returns `{ok:true}` or `{ok:false,message}` |
| GET    | `/usage?range=7d\|30d\|90d` | Existing bounded usage totals, series and model aggregation                                        |

Provider input remains `name/baseUrl/model/apiKey/active`. Provider output
remains `id/name/baseUrl/model/active/apiKeyConfigured/updatedAt`, without
secret fields. A saved probe always reads its URL and selected model from the
database and ignores caller URL, model and key overrides. The probe checks the
provider's `/models` endpoint; it does not verify generation by the selected
model.

A provider's one existing model may be renamed only when unreferenced,
preserving its model ID. Multiple models, route primary/fallback references,
usage provider, model/final-model/attempted-model references, or matching audit
history prohibit model changes. Metadata and active edits remain possible using
the currently selected model. Model selection is enabled first, then creation
time, then ID.

The two service-role-only, security-invoker RPCs in
`20261009160000_admin_ai_provider_transactions.sql` save and delete atomically.
They explicitly set an empty search path. Related table writes are serialized
with short transaction locks so array/JSON reference insertions cannot race the
check. Secret insertion, provider creation/update and initial model creation
roll back together on failure. Delete removes only an unreferenced provider and
its models/health; it retains every secret and never rewrites route or history
rows. Array/JSON/audit UUID matching is conservative and case-insensitive.

Errors use the existing AppError envelope: 400 invalid inputs, 401 invalid
sessions, 403 denied roles, 404 missing providers, 409 model/history conflicts
or unsupported secret versions, and sanitized 503 configuration/database/secret
failures. No upstream response body or internal database error is returned or
logged. Usage sums reported `cache_read_input_tokens` into nullable
`cachedInputTokens`; unreported values remain unknown and a reported zero stays
zero. Cache reads are a subset of input tokens and do not inflate other totals.
Apply `20261009133000_ai_usage_cache_read_tokens.sql` before deploying this
handler; missing columns and other database errors fail closed with sanitized
503 responses.

## Approved v2 secret protocol

Only explicit nonblank new keys write the new protocol. Existing `ai_secrets`
columns and RLS stay unchanged; no parallel secret table is created.

- `COOKAPP_AI_SECRET_KEY_V2`: canonical unpadded base64url 32-byte AES-256 key.
- Fresh opaque UUID `secret_ref` for every create/rotation.
- WebCrypto AES-256-GCM, random 12-byte nonce, 128-bit tag.
- AAD: `ai-secrets:v2:${secret_ref}`.
- Unpadded base64url ciphertext including the WebCrypto tag and base64url nonce;
  `key_version = 2`.
- Blank edits preserve the old reference and ciphertext byte-for-byte. Explicit
  replacements insert fresh rows and retain the old rows, including v1.
- Saved v1/unknown-version probes return an explicit 409 unsupported-version
  error. The unavailable `COOKAPP_AI_MASTER_KEY` format is never inferred or
  converted. The external legacy worker resolver has not been adapted or tested
  for v2; rollout must account for that dependency separately.

Both probe modes require public HTTPS DNS names on default port 443, reject
credentials/query/fragment/private addresses, pin public DNS answers to the TLS
connection, follow no redirects, discard response bodies and have an
eight-second network timeout. Probes do not persist the caller's key or update
health state.

## Local verification

```sh
deno test --allow-env --allow-net --frozen --config supabase/functions/admin-ai/deno.json supabase/functions/admin-ai/
deno check --frozen --config supabase/functions/admin-ai/deno.json supabase/functions/admin-ai/index.ts
python3 supabase/functions/admin-ai/tests/run_local.py
```

The Python harness creates a disposable Supabase CLI project under root `.tmp/`,
uses ports 57820–57829, replays the full 17-migration baseline plus this
migration, runs 44 pgTAP assertions, and serves the actual Edge handler with
synthetic admin sessions and keys. It tests real role/RPC denials,
create/update/rotation/delete, v1 preservation, saved URL overrides, and
concurrent fallback/attempted-history insertions. Logs and a source-hashed
report remain in `.tmp/`; only its own stack is stopped and deleted. Ports must
be available. `--existing` is for iteration against an already isolated fixture
project, not a production or shared stack.

For the focused cache-token projection check, run the same harness with
`--usage-only`. It creates a fresh isolated stack and exercises a real GET with
reported, zero and unknown synthetic values, without provider calls. The full 44
pgTAP / 151 HTTP matrix was run at `cbd5617`; the cache projection follow-up has
separate source-hashed evidence and does not claim a full matrix rerun.

The public example.com probes are negative checks with synthetic credentials; no
successful commercial provider authentication, generation, external worker
compatibility, or production acceptance is claimed. CLI database lint also flags
two preexisting legacy queue functions: `recipe_import_queue_read` returns an
integer where its declared second result is bigint; `recipe_import_enqueue`
references the absent modern `recipe_import_jobs.error_code` column. Neither
legacy definition is changed here. The modern `recipe_import_v1` queue's runtime
results are separate evidence from these legacy lint findings.
