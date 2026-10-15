# Recipe Pals Commercial Contract V1

Canonical specification: [DEV-425](https://linear.app/gengyun/issue/DEV-425). Parent: [DEV-424](https://linear.app/gengyun/issue/DEV-424). This is a **contract-only, not implemented or deployed** deliverable: it freezes capability, entitlement, quota and release-stage wire semantics so independent downstream tasks (billing, quota server, save integration) can start from one machine-readable source.

Machine-readable sources of truth:

- [OpenAPI](schemas/commercial-v1.openapi.json) — six authenticated routes.
- [JSON Schema](schemas/commercial-v1.schema.json) — DTO shapes and the versioned `x-commercial-policy`.
- [Contract examples](commercial-fixtures/contract-examples.json) — free / premium / expired / multi-candidate / replay / error examples decoded identically by Swift and TypeScript.

Cross-language DTO validators (the actual enforcement of the arithmetic invariants):

- `ios/RecipeCore/Sources/RecipeCore/RecipeAccessContract.swift`
- `supabase/functions/_shared/recipeAccessContract.mjs`

Wire conventions: all UUIDs and hashes are canonical lowercase; uppercase is rejected. Integer counters are bounded to `2^53 - 1` so Swift and TypeScript decode identically. Request DTOs are `Codable` with validated public initializers so the app can construct and encode them for future HTTP; response DTOs are decode-only.

## Scope and authority

Owner identity always comes from the verified Supabase JWT (`auth.uid()`), never from a request field. The client may cache `/recipe-access` for UI only; every settlement action is re-adjudicated server-side against live entitlement and quota state. The server owns `policy_version`, stage, entitlement, `limit`, `used`, `reserved` and `remaining`; a client never authors any remaining/limit value.

Release stage (`stage`) is `freeTest` or `commercial`. `freeTest` is the default and has no StoreKit networking, no purchase entry point, and no new payment gate. `commercial` is an explicit build configuration with a separate server-side switch. The server never trusts a client-claimed stage to grant entitlement. If the client and server stage disagree, the commerce service returns `CONFIGURATION_UNAVAILABLE` (503); basic local read/manual/timer/math/JSON-HTML features remain available regardless.

## Capability vocabulary and quota policy

The capability vocabulary is fixed. Unknown wire identifiers are rejected (fail-closed).

| Capability | Unit | Free quota | Premium quota | Metered this version |
| --- | --- | --- | --- | --- |
| `smart_import` | `successful_imports` | 5 / ISO UTC week | 100 / UTC calendar month | yes |
| `ai_edit` | `successful_edits` | 3 / lifetime (first 3 only) | 30 / UTC calendar month | yes |
| `recipe_question` | `successful_answers` | not entitled | 100 / UTC calendar month | yes (phase II) |
| `recipe_translation` | `successful_translations` | not entitled | 20 / UTC calendar month | yes (phase II) |
| `media_import` | `media_tasks` | not entitled | 20 / UTC calendar month, still consumes `smart_import` quota | yes (phase II) |
| `hands_free_cooking` | — | not entitled | entitlement-only, unmetered | no |
| `weekly_templates` | — | not entitled | entitlement-only, unmetered | no |
| `weekly_groceries` | — | not entitled | entitlement-only, unmetered | no |
| `auto_plan` | — | not entitled | entitlement-only, unmetered | no |
| `pdf_export` | — | not entitled | entitlement-only, unmetered | no |

Period definitions:

- **ISO UTC week**: `period_start` is Monday 00:00:00 UTC, `reset_at` the following Monday 00:00:00 UTC.
- **UTC calendar month**: `period_start` is the 1st 00:00:00 UTC, `reset_at` the 1st of the next month 00:00:00 UTC.
- **lifetime**: `period_start` and `reset_at` are both `null`; only the free `ai_edit` first-3 bucket uses it.

Every metered quota enforces `remaining == max(0, limit - used - reserved)`, with all four counters non-negative and bounded to `2^53 - 1` so Swift and TypeScript agree. A downgraded owner may carry `used > limit` (week/month observation counters) with `remaining` clamped to zero. `units` is fixed vocabulary so Swift and TypeScript agree on what a settled unit counts. Unmetered premium capabilities report `quota: null` and grant no numeric promise ("no infinite" promise is therefore preserved by absence, not by an infinite value).

Answers/translations/media settle only on a successfully returned valid result; a failed or replayed call does not decrement. Provider token cost is a separate budget and is never charged against success counters.

## GET /recipe-access

Returns `AccessResponse` (`owner_id`, `server_time`, `policy_version`, `stage`, `entitlement`, `capabilities`). `entitlement.status` is `free`, `premium` or `expired`; `valid_until` is `null` for `free`. The client owner comes from its own session and a client must reject a response whose `owner_id` differs from its session owner.

## Usage reservation lifecycle

Reserve before provider work; settle from the real persisted operation result; never from a client success boolean.

1. `POST /recipe-usage/reservations` — `{operation_id, capability, input_hash, estimated_units, source}`. `source` carries the persisted origin: for `smart_import`, an owned `job_id` plus the selected `candidate_ids` (their count equals `estimated_units`); for `ai_edit`, the approved `session_id` and `turn_request_id`. Returns a durable `Reservation` with `status: reserved`, a 10-minute `reserved_until` TTL, and `tier_at_reserve`/`policy_version`/`period_start` frozen at reserve time. The lock key is `(owner, capability)`; the counters (week/month/lifetime) are read inside that lock.
2. `POST /recipe-usage/{operation_id}/commit` — settle a dispatched reservation. The server loads the persisted operation/proposal referenced by `source` (never a client success flag) to decide committed units.
3. `POST /recipe-usage/{operation_id}/release` — release a reservation confirmed not dispatched or not committed. Units return to the original bucket.
4. `POST /recipe-usage/{operation_id}/finalize` — the import/edit alias: atomically persists the authorized result, the stable `recipe_id`, the approved `payload_hash` and the usage commit. One candidate is settled per finalize (`source.candidate_ids` has exactly one entry), so the single `recipe_id`/`payload_hash` is unambiguous; multi-candidate saves issue one finalize per candidate. The `recipe_id` and `payload_hash` are server-produced; the client never supplies a success flag, an `actual_units` value or a recipe ID.
5. `POST /recipe-usage/{operation_id}/ack` — confirms the device durably persisted the finalized save. Recovery after a crash reuses the same `operation_id` and never re-invokes the model.

The reservation is frozen with `owner`, `capability`, `period_start`, `policy_version` and `tier_at_reserve`. A commit that crosses a week/month boundary still settles against the original reservation period; the event `occurred_at` is `reserved_at`. A new period never double-charges. An un-dispatched reservation is safe to release after its 10-minute TTL; a reservation marked `dispatched_unknown` is never auto-released or re-dispatched. A generated-but-unapproved proposal is held 24 hours, after which only reservations confirmed uncommitted are released; approval re-reserves against the current period for the same saved proposal without re-running the provider. A still-valid reservation may complete its authorized action after the tier expires; subsequent new actions use the current tier.

### Idempotency and replay

Identical replay returns the same durable outcome with `200`. The same idempotency key with different input returns `409 IDEMPOTENCY_CONFLICT`. The server never recalculates an old outcome against new evidence. Multi-candidate imports settle per successfully saved candidate ID: the same candidate under a new request must not be charged twice.

## Error mapping

Errors always carry `{code, message, recoverable, request_id}`; `Retry-After` (HTTP header) is deterministic — derived from the quota `reset_at` or the reservation TTL — never random jitter.

| Code | HTTP | Meaning |
| --- | --- | --- |
| `AUTH_REQUIRED` | 401 | Invalid/expired/anonymous credentials |
| `OWNER_MISMATCH` | 403 | JWT owner differs from the operation owner |
| `NOT_FOUND` | 404 | Unknown operation, masking foreign ownership |
| `IDEMPOTENCY_CONFLICT` | 409 | Same key, different input |
| `RESERVATION_EXPIRED` | 409 | Reservation past its TTL |
| `INVALID_INPUT` | 422 | Malformed request |
| `QUOTA_EXCEEDED` | 402 | Quota exhausted |
| `UPGRADE_REQUIRED` | 402 | Capability requires premium |
| `CONFIGURATION_UNAVAILABLE` | 503 | Client/server stage disagreement |
| `SERVICE_UNAVAILABLE` | 503 | Commerce backend unavailable |
| `INTERNAL_ERROR` | 500 | Generic; never exposes SQL/provider text |

## RevenueCat SDK pin (for DEV-426)

Fixed official `purchases-ios` release for the native StoreKit 2 "myApp + StoreKit 2" observation/sync bridge:

- **Version:** `5.95.0` (stable, published 2026-10-12).
- **Package.resolved pin** (`version: 3`, `kind: remoteSourceControl`, `location: https://github.com/RevenueCat/purchases-ios.git`, `revision: 95ad250230efa7fc3e811c158ed264832aed2e79`).
- **Deployment target:** iOS 13.0 minimum (satisfies the app's iOS 18 floor). StoreKit 2 is the default in v5; the removed `.with(usesStoreKit2IfAvailable:)` must not be reintroduced.
- **Configuration:** `Purchases.configure(with: .builder(withAPIKey: apiKey).with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2).build())`. "Observer Mode" was renamed `PurchasesAreCompletedBy` in v5.
- **Identity/sync/restore:** `Purchases.shared.logIn(_ appUserID: String) async throws -> (customerInfo: CustomerInfo, created: Bool)`, `Purchases.shared.logOut() async throws -> CustomerInfo`, `Purchases.shared.syncPurchases() async throws -> CustomerInfo`, `Purchases.shared.restorePurchases() async throws -> CustomerInfo`, `Purchases.shared.getCustomerInfo() async throws -> CustomerInfo`, and `Purchases.shared.recordPurchase(_:)` for purchases completed by the app. `appUserID` is the verified Supabase UUID; no anonymous configure before login.

Login/logout hardening: do not configure an anonymous SDK before login; on logout, invalidate the old owner's callbacks and block cloud entitlement; if the SDK cannot be deconfigured, keep an internal instance but block and mask the old owner's authorization and calls until the next verified owner binding completes. The original transaction owner is never silently transferred to a new account; a restore conflict prompts the original account. Dashboard restore behavior must be `Keep with original App User ID` (returns `receipt_already_in_use` on mismatch); the actual Dashboard configuration is read in DEV-101/93, not in this round.

References: [4.x → 5.x migration](https://www.revenuecat.com/docs/sdk-guides/ios-native-4x-to-5x-migration), [restore behavior](https://www.revenuecat.com/docs/projects/restore-behavior).

## Additive operation mapping

The five owner-draft wire paths (`POST /recipe-draft-sessions`, `GET /recipe-draft-sessions/{session_id}`, `POST …/turns`, `GET …/turns/{request_id}`, `POST …/turns/{request_id}/approval`) keep their existing meaning. Commerce binds on top with the independent usage routes above, and never adds undefined fields to those five paths:

- `ai_edit` finalizes when a user accepts an edit overlay and saves it; the `source` references the owned `session_id` + `turn_request_id` of the approved turn, and `input_hash` is the canonical hash of the approved save payload.
- `smart_import` finalizes per selected candidate; the `source` references the owned completed import `job_id` + exactly one `candidate_id` per finalize, and reservation happens only when the user confirms the save and the selected independent candidate count is known (never a guessed count before candidates exist).

Approved-payload recovery: the client persists the approved payload as a local save intent before finalize. `finalize` returns the stable `recipe_id` and `payload_hash` but not the full payload; after the server commit the client writes the payload to the private library by the returned stable ID and ACKs. A crash after finalize but before the local write recovers by reloading the local save intent and re-reading/re-ACKing the same `operation_id`; `finalize` is idempotent by `(owner, capability, source)` and re-ACK is a no-op, so recovery never re-runs the model or double-charges.

## Shared file ownership

- `ios/Recipe/Services/SubscriptionStore.swift` → billing task (DEV-426).
- Server usage/quota persistence → quota task.
- `ios/RecipeCore/Sources/RecipeCore/RecipeStore.swift` writes → the iOS save-integration task, serialized with finalize/ACK.

## Schema version and commit record

- `x-commercial-policy.schema_version` = `1`, frozen by this contract. Any quota/config change must bump the versioned policy and sync user-facing copy; agents must not self-author commercial rules.

*Schema version/commit recorded after PR merge: to be filled by the coordinator.*
