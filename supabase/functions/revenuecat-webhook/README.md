# RevenueCat webhook — #155

The user authorized publication of this project's backend source on 2026-10-09.
This module reuses the existing `codex/revenuecat-webhook-issue-155` implementation
and reconciles it with the current Supabase deployment. No production change was
made. [Issue #155](https://github.com/natefox2017/cook/issues/155) remains open.

## Provenance and dependencies

Read-only connector inventory on 2026-10-09 returned `revenuecat-webhook` v3,
ACTIVE, `verify_jwt=false`, bundle SHA-256
`84c47669ef0797808e4fdc3cc61c93cde5b5c04b4b2c69f2aeff9cfe25c591be`.
The exact retrieved entry-point bytes are preserved in
`provenance/deployed-v3.ts.txt`; source SHA-256 is
`05387a7f853ee783ef44b207adbb8f074e2f605d4bb47c5f8c50c542ef33e385`.
The source and bundle hashes describe different artifacts. Deployment metadata,
source size and each observed RPC definition hash are in
`provenance/deployed-v3.json`. No deployment Git SHA is supplied by the connector;
one must not be inferred from the version or entry-point's temporary path.
`release.json` records the new entry-point/helper/config/lock hashes, credential
names, gateway verification setting and prerequisite migration hash for the
coordinator's combined release manifest.

The deployed v3 imports unversioned runtime typings and SDK major `@2` and
contains neither a lock nor its resolved graph. The checked-in implementation
pins JSR SDK/runtime typings 2.117.3 and has its function-local frozen
`deno.json`/`deno.lock`, including transitive integrity hashes. This is the
existing branch's selected dependency version, not a claim that v3 resolved
the same SDK. There are no mutable Git branch imports or runtime downloads of
project source. Lockfile tarball URLs retain the existing mirror; package
versions and integrity hashes are frozen.

The preserved source contains environment lookups for credentials, not literal
provider or service credentials. Its `cookapp-rc-webhook` string is a public
domain separator for the fixed-length header comparison, not a secret. Local
fixtures contain only synthetic users, IDs, products and amounts.

## Authentication and behavior

Every request still requires the exact configured
`Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`. No Supabase user bearer,
anonymous key or service key substitutes for the provider credential. Missing
server configuration fails closed. `verify_jwt=false` is intentional because
RevenueCat sends its configured credential rather than a Supabase JWT.

When `REVENUECAT_WEBHOOK_SIGNING_SECRET` is configured, the handler additionally
requires `X-RevenueCat-Webhook-Signature`, authenticates the timestamp and exact
raw bytes, and rejects signatures outside five minutes. Bearer and signing
secrets are independent. Omitting the signing secret preserves existing
Bearer-only integrations; it does not claim that the sender enabled HMAC.
Enable/rotate the provider signing configuration only in an approved window.
See [RevenueCat's authorization and signature contract](https://www.revenuecat.com/docs/integrations/webhooks).

Input is bounded at 64 KiB before JSON parsing. Malformed JSON/event shape and
missing usable event IDs are rejected. Date overflow becomes unavailable date
metadata instead of crashing. Unknown event types and TEST/ALIAS/TRANSFER keep
their existing ignored responses; this module does not implement transfers.
Current UUID `app_user_id` is authoritative; only an unresolved current ID may
fall back to the original UUID. No alias array is treated as an account claim.
Known different-owner replays return 409. Database diagnostics log a code only.

## Required database owner binding

`supabase/migrations/20261009150000_revenuecat_event_owner_binding.sql` is a new,
coordinator-authorized migration; no existing migration or shared file changed.
It preserves both existing RPC signatures and return types:

- `upsert_subscription_from_revenuecat`: a duplicate `rc_event_id` checks the
  existing purchase event owner first. Same owner returns without any payment
  side effect; different owner raises `42501` before writes. Database unique
  constraints serialize concurrent claims, not a process-local lock.
- `upsert_payment_transaction`: an assigned owner cannot change to a different
  owner or NULL. A previously unassigned payment may acquire its first owner,
  consistent with the existing `coalesce` semantics. An atomic conflict-update
  predicate also protects the race where neither requester saw a prior row.
- Duplicate purchase-event ownership, including NULL after account deletion,
  cannot be rebound. Financial owner violations propagate rather than being
  swallowed by the subscription RPC's diagnostic handler. Service-only
  execution grants are preserved explicitly.

The migration requires the existing commerce tables, unique keys and helper
RPCs recorded in `provenance/` and the fixture. It is not a replacement for the
repository's incomplete historical production schema/migration chain.

## Actual isolated verification

```sh
deno test --cached-only --config supabase/functions/revenuecat-webhook/deno.json \
  supabase/functions/revenuecat-webhook/index_test.ts
deno check --cached-only --config supabase/functions/revenuecat-webhook/deno.json \
  supabase/functions/revenuecat-webhook/index.ts
python3 supabase/functions/revenuecat-webhook/tests/run_local.py
```

Executed 2026-10-09: **4 Deno tests passed**; frozen/cached entry-point type check
passed. The HTTP harness completed **80 assertions**, including two baseline
probes that deliberately reproduce the old production RPC bug: same event ID
first A then B leaves `purchase_events` owned by A and changes its payment to B.
This is reproduced unsafe behavior, not a passing security property. All
remaining assertions exercise the patched migration/handler.

The harness uses real Supabase CLI 2.120.0 containers, PostgreSQL 17.11.0.004,
PostgREST v16.4 and Edge Runtime v1.77.4 (Deno compatibility v2.1.4). It calls
the real gateway, SDK and RPCs over HTTP, with anonymous fixture data only:
missing/wrong Bearer, absent/wrong/stale/modified HMAC, missing server secret,
400/413 payload errors, repeated and concurrent events, original/current owner
mapping, 5 rounds each of payment RPC, subscription RPC and webhook owner races,
8 simultaneous same-owner deliveries, changed duplicate payloads, NULL binding,
anonymous direct-RPC rejection, late-event ordering and independent A/B state.

`tests/fixtures/observed-rpcs.sql` preserves the read-only retrieved business
function bodies; statement terminators and dependency order allow batch replay.
`schema.sql` reproduces observed columns and required unique/FK keys with
synthetic Auth identities. This is a deliberately partial platform fixture,
not a clone of production policies, constraints, triggers or user data.
`grants.sql` matches the observed service-only RPC execution boundary.

The runner accepts no remote endpoint/credentials. HTTP uses fixed literal
loopback URLs and disables proxies/redirect following. Randomly named project
containers and data volumes are removed in `finally`; other stacks remain.
Ignored, private `.tmp/recipe-rc-*/report.json` records source/migration hashes
and assertion names. Startup/Edge logs may contain disposable local CLI keys;
keep them out of Git. Earlier harness attempts failed on fixture load order,
missing batch terminators and disabled-Auth key inventory; those setup failures
were corrected before the successful run.

Not verified: RevenueCat dashboard delivery/signing configuration, production
secrets, staging/production schema drift, real payment events, store purchases,
account transfers, billing reconciliation or a production deployment. No real
paying account, subscription or payment row was written.

## Approved release and rollback procedure

1. Before the approved production window, read/hash the current deployed source
   and commerce RPCs again and compare with the observed baseline. Review schema
   keys/signatures/ACL and halt on unexplained drift. Capture a controlled schema
   and release backup, including the current function artifact/configuration.
2. Apply **only the owner-binding migration first** through the coordinator's
   reviewed migration process. Verify service-only grants and anonymous/user
   denial. The existing v3 webhook remains compatible with these signatures.
3. Deploy this complete module with the recorded frozen dependencies and
   `verify_jwt=false`. The coordinator's release manifest must include the
   migration prerequisite and module hashes. Provider credentials remain in
   Supabase Secrets; never add their values to a release manifest.
4. First validate an isolated staging endpoint with disposable identities and
   approved sandbox events. In production, use an explicitly approved test-event
   scope; monitor response codes and duplicate/owner conflicts. HMAC requires
   a separate provider/server signing-secret coordination step.
5. On handler regression, restore the previous reviewed function artifact and
   its configuration while **retaining the owner-binding migration**. The
   archived source helps recover the v3 implementation but is not a recoverable
   original binary bundle or a byte-identical rebuild guarantee. Capture that
   deployable artifact before release. Do not automatically restore the unsafe
   RPCs or transfer/erase financial owners as a rollback shortcut.

No production deployment or rollback was performed here. Acceptance and closing
#155 belong to the coordination chat after all modules and release evidence exist.
