# OpenAPI repository contract — #155

This public function serves a locally bundled OpenAPI document. Version `2026-10-09.2` preserves the 39 existing HTTP operations across 37 paths from main `2ad6cc6d40de7265476a0dccd0571fdb306bdad7` and adds four `/admin-ai` paths with six operations.

The six admin-ai operations freeze the current `admin/src/api.ts` and `admin/src/types.ts` contract together with the current PR #211 implementation contract. PR #211 is still unmerged. These OpenAPI entries describe the frozen request/response types and explicit current error outcomes; they do not claim the routes are deployed or runtime-tested. The published PR #211 source revision and catalog pointer are recorded in `info.x_source_revisions` and `info.x_source_catalog`.

The production catalog reference is [Issue #155 Edge Function source manifest](../../ISSUE_155_EDGE_FUNCTION_SOURCE_MANIFEST.md#admin-ai-recovery-plan-and-source-gap). Its AI table and column inventory informs nullable usage fields; the OpenAPI work does not add or change database schema.

## Admin AI contract

Every operation uses the custom `AdminSessionBearer` token and the `x-required-admin-roles` extension declares `owner` and `admin`. Missing, invalid, or expired sessions return `401`; valid `operator` or `readonly` sessions return `403`. This is a documentation contract; the six routes are not exercised by the OpenAPI tests.

| Path | Operation | Request / response | Frozen limitations and errors |
| --- | --- | --- | --- |
| `/admin-ai/providers` | `GET` | `200 { data: LLMProvider[] }` | Provider output includes `apiKeyConfigured`; it never includes key material. |
| `/admin-ai/providers` | `POST` | `LLMProviderInput` request; `200 LLMProvider` | Provider and model mapping are saved atomically. Invalid/missing key returns `400`; transaction conflict returns `409`; unavailable v2 key configuration returns `503`. |
| `/admin-ai/providers/{id}` | `PUT` | `LLMProviderInput` request; `200 LLMProvider` | An empty key preserves the saved reference. A model change returns `409` only when history/route references or a multi-model mapping block the atomic change. Unavailable v2 key configuration returns `503`. |
| `/admin-ai/providers/{id}` | `DELETE` | `200 { ok: true }` | Unreferenced provider deletion succeeds atomically. History, route, usage, or model references return `409`; unknown provider returns `404`. |
| `/admin-ai/providers/test` | `POST` | `{ providerId?, name, baseUrl, model, apiKey? }`; `200 { ok, message? }` | With `providerId`, stored endpoint/model/key override caller fields. A saved v1 key or provider missing key/model returns `409`; unknown provider returns `404`. An unsuccessful probe returns `200` with `ok: false`. |
| `/admin-ai/usage` | `GET` | `range=7d\|30d\|90d`; `200 LLMUsage` | `range` defaults to `7d`; invalid values return `400 validation_error`. Cached input tokens remain optional/null because the catalog has no cached-input column. |

`LLMProviderInput.apiKey` and the one-time test `apiKey` are write-only. The response type exposes only `apiKeyConfigured`. The shared error envelope is used for explicit `400`, `401`, `403`, `404`, `405`, `409`, `500`, and `503` responses; each operation documents only the statuses it can currently return.

## Local verification

```sh
deno check --cached-only \
  supabase/functions/openapi/index.ts \
  supabase/functions/openapi/handler.ts \
  supabase/functions/openapi/http_test.ts

deno test --cached-only --allow-net=127.0.0.1 \
  supabase/functions/openapi/http_test.ts
```

The HTTP tests serve only the OpenAPI document handler on loopback. Contract tests verify the unchanged 39-operation inventory plus the six frozen admin-ai operations, local `$ref` resolution, role metadata, types, and error outcomes. They do not invoke or claim runtime verification of PR #211's unmerged admin-ai handler. The test process has no network permission beyond `127.0.0.1`; no production Auth token, database, remote fetch, or deployment is used.

## Release boundary

This change does not deploy the function or alter production state. Any release requires a separate approved deployment window. Reverting this repository change is a normal Git revert; the prior live v23 source URL is not a verified rollback target because its source was unavailable during this investigation. Verify any rollback target before a later production release.
