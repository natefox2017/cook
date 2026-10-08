# RecipePouch import V1 contract fixtures

This directory accompanies [OpenAPI](../schemas/import-v1.openapi.json) and [JSON Schema](../schemas/import-v1.schema.json). **These documents describe an interface to implement; none of these paths are made live by this folder.**

## Validate fixtures

Run after checking out the repository:

```bash
python3 -m pip install 'jsonschema>=4.21'
python3 docs/import-fixtures/validate_contract.py
```

Run the cross-field evidence regression with Deno:

```bash
deno test --allow-read=docs/import-fixtures docs/import-fixtures/contract-evidence_test.ts
```

The Deno regression checks that an original submitted URL stays separate from
the canonical URL, field evidence references resolve, vague/low-confidence
amounts and missing steps remain reviewable, and a confirmed user edit keeps
both the extracted value and the user-origin evidence. It supplements the
JSON Schema fixture checks; it does not add fields or endpoints to the V1
contract.

The validator uses JSON Schema Draft 2020-12, checks external OpenAPI references, and checks all positive/negative fixtures. The contract and validator require an HTTPS hostname, reject credentials or nonstandard ports, and reject empty or whitespace-only text. The extra URL pattern is needed because generic JSON Schema `uri` format alone accepts hostless HTTPS URIs. These local checks are not a production URL fetcher or SSRF defense. A schema check is not an iOS build, deployed API check or real source import.

## Evidence acquisition

`contract-examples.json` contains synthetic requests, receipts, progress states, errors and evidence-backed partial recipes; `example.org` is an inert example hostname, not a verified source. `observations.json` records public help/documentation observations with explicit null HTTP status; it does **not** claim extraction, a downloaded TikTok clip or a working backend.

To create a bounded research observation for a public HTML page, explicitly approve the hostname and run:

```bash
python3 docs/import-fixtures/probe.py \
  --url 'https://www.example.org/recipe' \
  --allow-host www.example.org > page-observation.json
```

The command refuses nonpublic DNS addresses, HTTP, redirects, nonstandard ports and unapproved hostnames, imposes a 15-second/512 KB limit and writes a JSON observation. **Do not use this probe as the production fetcher or an SSRF protection substitute.** Because TLS/DNS can change between validation and connection, actual import backends need validated connection routing, per-hop checks, MIME/size/time limits and network egress restrictions.

## Native/source acceptance still required

1. Use a real public recipe webpage and a real public recipe video, record fetch status, visible body/caption/audio/source evidence, parsed fields, and quality/review verdict. Do not pretend the sample input is an actual source.
2. On iPhone, open third-party app → Share → RecipePouch → return to source app; verify extension terminates promptly and **receipt survives force-quit, reboot and intermittent connectivity**.
3. Verify duplicate shares, account switch, unauthenticated receipt backlog, offline→online retry, missing/private video fallback and competing queue workers.
4. Verify Supabase RLS and JWT owner checks, artifact admission, CAS/deduplication and no false `queued` confirmation, with production-like test accounts.
5. Verify every ungrounded amount/time stays unknown, review markers persist, user-confirmed edits survive subsequent worker attempts, and full import errors are actionable.

Mature-product behavior used to choose these tests: [ReciMe’s TikTok import help](https://recime.app/help/en/articles/11625015-import-from-tiktok), [Apple Share Extension lifecycle](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html), and [Supabase durable queue worker guide](https://supabase.com/docs/guides/queues/consuming-messages-with-edge-functions).
