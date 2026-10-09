# Issue #155 production update plan

**Status: review draft. No production writes, function deployments, secret reads, or application-data queries were performed.**

## Observed production baseline

Read-only `supabase functions list --project-ref semsjyrqjnumpvanibip --output json` on 2026-10-09 returned these active deployment bundles. Hashes are the production `ezbr_sha256` values; they are baseline identifiers, not hashes of candidate repository source.

| Function | Live version | `verify_jwt` | Live bundle SHA-256 |
| --- | ---: | --- | --- |
| `revenuecat-webhook` | 3 | `false` | `84c47669ef0797808e4fdc3cc61c93cde5b5c04b4b2c69f2aeff9cfe25c591be` |
| `admin-subscriptions` | 4 | `false` | `4f355129a512842e7e96dff6e2f6274fa2565acbf3c6826655a6f0873c7351e8` |
| `admin-users` | 6 | `false` | `99c86c74a719eea40cb3318fae787c78a9a096702dd699c53a3a37c8fe8a9805` |
| `admin-dashboard` | 3 | `false` | `ba97df336b9ca7f894d7fc08f10d9e6d49c76482f5606ae37bfc33ca4119bd51` |
| `admin-ai` | 4 | `false` | `b90348513a08e7a1fd006fe6561b587c032387e33ceba88ee9ab3ac141f0c1ea` |
| `health` | 8 | `true` | `7e5ee17f8b16ced8c802a0f42b5851e0c514328c81f205e0e6385ae745b0aeca` |
| `openapi` | 23 | `false` | `a7c7f0d301fe53baff101d5f53bedf44a6d82ad55f48422e47a02d04c4217f51` |

Proposed code sources are `main` at `2ad6cc6d40de7265476a0dccd0571fdb306bdad7` for the repository-current functions, PR #211 (`admin-ai`) at `cbd5617a1f2b8508afd13d5ac91031bb16eac2ee`, and PR #222 (`openapi`) at `cd277aa9981966ff9a31bde13540956a89e76f03`. The latter two remain unmerged; this is not a deployment authorization.

## Gates before a production window

1. Merge and review the candidate PRs, then stage the seven functions from their exact merged revisions and compare the deployed `verify_jwt` settings with the table above.
2. Recover/approve the canonical full OpenAPI v23 source before deploying `openapi`. PR #222 is a repository contract and explicitly does not reconstruct the unavailable live v23 document.
3. Check the external worker's secret resolver against v2 before enabling saved provider keys. PR #211 adds `COOKAPP_AI_SECRET_KEY_V2` (canonical unpadded base64url for a 32-byte AES-256 key); provide it through the secret manager, never in files or command output. The former v1 key format is unknown and v1 saved-key probes are unsupported. Do not rotate/replace existing keys until the worker compatibility and recovery process are proven.
4. Reconcile migration history before any database action. The CLI 2.120.0 `migration list` direct PostgreSQL connection timed out twice, but the supported read-only `db query --linked` Management API path succeeded with only `version,name`: production has 46 history rows; this branch has 17 migration files; only four versions match exactly. Thirteen local versions are absent from production history: `20260916000000`, `20261007`, `20261008050000`, `20261008103818`, `20261008155000`, `20261008195255`, `20261008200000`, `20261009014500`, `20261009120000`, `20261009121000`, `20261009121100`, `20261009133000`, and `20261009150000`. These are history differences, not a confirmed apply set; production has historical versions absent locally and some may represent equivalent schema changes. PR #211 adds candidate `20261009160000_admin_ai_provider_transactions.sql`, also absent from production. Do not run migrations until each local file is reconciled with production and a dry run shows only reviewed work. Do not use `db push --include-all`: CLI help says it includes every local migration absent from the remote history table. Do not repair migration history as part of this rollout.
5. Preserve the known limits in release evidence: the external worker resolver has not been adapted/tested for v2, the original v1 crypto protocol is unknown, and CLI lint still reports two legacy queue definitions (`recipe_import_queue_read` integer/bigint return mismatch; `recipe_import_enqueue` references absent `recipe_import_jobs.error_code`).

## Execution and rollback proposal

After approval and the gates above, deploy first to an isolated staging project. Apply only the reviewed migration(s), configure the named secret through the staging secret manager, then deploy the seven functions with their checked-in JWT settings. Validate health with anonymous and authenticated requests, each admin route with no session/owner/admin/denied role, provider create/update/delete and secret-preservation cases using synthetic keys, usage bounds, RevenueCat signature rejection/acceptance fixtures, and OpenAPI schema retrieval plus all documented paths. Do not use production credentials or real provider keys for probes. Record function versions, bundle hashes, migration versions, and test outputs before requesting a separate production window.

For production, require a separate explicit deployment approval. Capture the seven current version/hash values above immediately before rollout; deploy only the approved revisions, then run the same smoke checks without changing user data. On failure, redeploy the recorded prior function bundles and restore the verified pre-rollout function settings. Migration rollback is not assumed safe or automatic: use only a reviewed forward-fix or a separately approved database recovery plan. No OpenAPI rollback target is currently verified because the deployed v23 source is unavailable.
