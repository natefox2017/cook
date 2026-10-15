# API Contract V1

> Import V1 machine-readable source of truth: [OpenAPI](schemas/import-v1.openapi.json) and [JSON Schema](schemas/import-v1.schema.json). The existing prose for recipe/grocery routes describes **planned** functionality, not deployed HTTP APIs.

### Import contract freeze — 2026-10-08

- `POST /recipe-imports`, `GET /recipe-imports/{job_id}` and `POST /recipe-imports/{job_id}/retry` are defined in OpenAPI but **not deployed by this PR**. Their request/response/error shapes are verified against versioned fixtures in [import-fixtures](import-fixtures/README.md).
- The Share Extension **first** stores an atomic local receipt with `receipt_id`, a stable `client_request_id`, immutable source reference and `received_at`, then immediately completes the Share host request. That is *local acknowledgment*, not cloud acceptance. The app later owns upload/retry/polling.
- The backend obtains `owner_id` from the verified Supabase JWT, never from an import request field. `(owner_id, client_request_id)` is the idempotency boundary. User-visible duplicates are also matched by canonical URL/platform content ID/fingerprint without cross-user deduplication.
- The backend returns HTTP 202 with `received` only after **durably recording** the job; it must never claim `queued` until a durable queue message has been confirmed. Worker retries must not create duplicate recipes. An unavailable queue leaves a truthful `received` record or returns a recoverable error.
- The job state machine is `received → queued → extracting → parsing → validating → completed`, with `failed` as a terminal/retryable error. `needs_review` is **recipe.status**, not a job state; a completed job can produce a partial recipe with `recipe_status=needs_review`.
- `image`/`file` requests may only reference an owner-controlled and already available artifact ID; no client-chosen Storage path or public URL-to-private-media proxy. `recipe-import-artifacts` creates a private upload intent, confirms the stored object, issues owner-checked short-lived download URLs, and expires artifacts after seven days.
- Evidence links to each extracted/inferred field; `user_confirmed=true` wins over re-parsing. `to taste`, `适量`, ungrounded time/amount, and uncertain visual inference stay raw/nullable; never substitute fabricated exact measurements.
- Error envelopes always carry `code`, `message`, `recoverable`, and `request_id`; 401/403/404/409/422/429/503 have distinct meanings. Client must show a recoverable fallback and preserve the local receipt.
- Server-side URL fetch must revalidate every redirect and resolved IP, reject private/link-local/metadata targets, enforce MIME/body-size/time limits and prevent DNS rebinding; authenticated client access must be owner-scoped through RLS.

`docs/schemas/import-v1.openapi.json` also defines the additive authenticated artifact handshake: create/resume upload intent, complete upload, issue a one-minute download URL, and delete. Its new endpoint schemas do not alter the frozen `/recipe-imports` request, response, or job state contract. Upload and download tokens are short-lived capabilities and must not be logged or stored as durable client state.


正式实现时以 OpenAPI 文件为机器可读真相源；本文件先冻结语义。

## POST /recipe-imports

创建异步导入任务。

Request：
- input_type: url | text | image | file
- url/text/artifact reference
- client_request_id
- optional platform hint

Response：
- job_id
- status: received | queued
- existing_recipe_id?（命中幂等/重复时）

必须快速返回，不等待 AI 完成。

## GET /recipe-imports/{job_id}

Response：
- job_id
- stage
- status
- progress_hint?
- recipe_id?
- review_count?
- error_code?
- recoverable
- suggested_action?

## GET /recipes

支持：
- pagination
- search
- status
- favorite
- sort

搜索至少覆盖：
- title
- ingredient normalized name
- step text

## GET /recipes/{id}

返回：
- recipe
- ingredients
- steps
- source
- review markers
- cover
- user edits

## PATCH /recipes/{id}

允许修改用户拥有的食谱字段。
用户修改必须记录 user_confirmed / precedence，不被下一次后台重解析静默覆盖。

## POST /recipes/{id}/groceries

按 servings 生成购物项。
仅在单位可安全换算时合并。

## Error shape

统一：
- code
- message
- recoverable
- suggested_action?
- request_id

示例：
- INVALID_INPUT
- UNSUPPORTED_SOURCE
- PRIVATE_OR_LOGIN_REQUIRED
- FETCH_BLOCKED
- FETCH_TIMEOUT
- MEDIA_TOO_LARGE
- PARSE_INCOMPLETE
- PROVIDER_TIMEOUT
- RATE_LIMITED
- INTERNAL_ERROR

客户端不能只按 HTTP 状态码决定 UI。


## Extractive owner draft contract (specification only)

[DEV-291](https://linear.app/gengyun/issue/DEV-291) freezes the additive [owner draft/session/turn specification](AI/RECIPE_DRAFT_API_V1.md), [OpenAPI](schemas/recipe-draft-v1.openapi.json) and [JSON Schema](schemas/recipe-draft-v1.schema.json). It reuses DEV-283/285 and an owned completed import job. The API is default-disabled and not implemented or deployed; persistent revision/replay, confirmed overlay, approval CAS and token reservations are future implementation requirements. It does not change the frozen import API or implicitly save a private Recipe, and excludes inspiration or new source inference.

## Commercial access and usage contract (specification only)

[DEV-425](https://linear.app/gengyun/issue/DEV-425) freezes the additive [commercial access/usage specification](RECIPE_PALS_COMMERCIAL_CONTRACT.md), [OpenAPI](schemas/commercial-v1.openapi.json) and [JSON Schema](schemas/commercial-v1.schema.json). It defines `GET /recipe-access` and the `/recipe-usage` reservation/commit/release/finalize/ack routes with server-owned owner identity, entitlement stage and quota. It is not implemented or deployed; billing, quota persistence and save integration are separate downstream tasks.

## Bounded AI recipe edit proposal contract (edit-v1)

[DEV-431](https://linear.app/gengyun/issue/DEV-431) adds an owner-authenticated AI edit proposal service whose machine-readable source of truth is [JSON Schema](schemas/recipe-edit-v1.schema.json). It reuses the three change paths already whitelisted by `RecipeEditProposal` and never authorizes fields outside them.

- `POST /recipe-edit-proposals` creates a reviewable proposal for `intent = substitute | simplify | dietary`, or replays the same proposal for an already-seen `operation_id` (idempotent). A request carries a minimal private recipe snapshot (`ingredients`, `steps`, `updated_at`, client `snapshot_hash`) that is context only — the server never claims the local snapshot is a cloud-verified original.
- Every proposal is marked `generated: true` and keeps its `source` provenance (`recipe_id`, `source_revision`, `snapshot_hash`). The server computes `input_hash = SHA-256(canonicalJSON({capability:"ai_edit", source:{recipe_id, snapshot_hash, source_revision, intent}}))` for the commercial reservation.
- The only change kinds are value replacements keyed by a stable lowercase UUID id: `ingredient:<id>:name`, `ingredient:<id>:amount`, `step:<id>:instruction`. Each carries `original`, `proposed`, `reason` and `warnings`. There is no `title`/`summary`/`servings`/`timer`/`temperature` patch, no ingredient/step addition, deletion, or reordering. An edit that cannot be expressed in these kinds returns `needs_manual_edit: true` with an empty change set instead of a fabricated patch.
- `GET /recipe-edit-proposals/{id}` returns the persisted proposal, owner-scoped. `POST /recipe-edit-proposals/{id}/approve` accepts a possibly human-revised change set plus `expected_snapshot_hash`; the server verifies only the three whitelisted kinds and returns `409` when the snapshot changed or the revision is stale. A confirmed proposal commits exactly once.
- Replay is keyed by `(owner_id, operation_id)`; a different body under the same key returns `409`. On timeout or security rejection the original recipe is preserved and any determinable uncommitted reservation is released. Dietary suggestions are advisory only and never promise allergy or medical safety.

## Bounded recipe Q&A contract (recipe-question)

[DEV-438](https://linear.app/gengyun/issue/DEV-438) adds an owner-authenticated recipe Q&A service whose machine-readable source of truth is [JSON Schema](schemas/recipe-question-v1.schema.json). It reuses the frozen phase-II metering capability `recipe_question`.

- `POST /recipe-questions` answers a bounded question about one owned recipe, returning a validated `answer` plus `statements` (`recipe` or `ai`). The request carries `recipe_id`, `revision`, a client `snapshot`, the `question`, up to five local `history` turns, and a per-turn `operation_id`.
- The client `snapshot` is context only and is never trusted for authorization: the server loads the canonical owned snapshot from `user_snapshots` and uses that for the provider. A recipe id absent from the owner's snapshot returns `404`, so an arbitrary client snapshot cannot fake ownership.
- Settlement is one `recipe_question` unit per operation through the service-role-only phase-II ledger (`recipe_usage_reserve_internal` -> `recipe_usage_mark_dispatched` -> `recipe_usage_finalize_internal`). The source is `{origin:"recipe_question", recipe_id, turn_request_id}` and `input_hash = SHA-256(canonicalJSON({capability:"recipe_question", source}))`.
- A validated answer is persisted per operation and a replay returns the stored answer without re-dispatching the provider. A retry of a dispatched-but-unknown operation never re-dispatches; it replays the stored answer or surfaces the in-flight state. The premium quota is `successful_answers` 100/UTC-month.

