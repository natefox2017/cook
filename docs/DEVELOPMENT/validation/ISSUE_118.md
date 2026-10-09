# Public social identity reconciliation — #118 / #152

Executed 2026-10-09 UTC on Linux, Deno 2.9.6 / TypeScript 6.0.3.
Tested source: `b74ec7f`, updated from original PR #152 `c6676c1` by merging
current `main@55ac164` and the existing #165 type fixes. No remote history rewrite.

## Integration preserved

- Resolved `schemaRecipe.ts` conflicts while retaining #151 public social
  metadata/caption extraction and #152 URL-derived external content IDs.
- Recipe JSON-LD author wins over page/social fallback, Twitter-only title and
  author remain available, fetched canonical URL determines the social ID,
  original shared URL remains unchanged, and missing recipe fields stay reviewable.
- Tightened the ID-only YouTube watch route to exactly `/watch`; a malformed
  `/watch/other?v=...` path cannot mint a valid external content ID.
- Added cross-feature fixtures for caption provenance plus identity, canonical
  redirect handling and spoofed domains, and structured author/raw-quantity
  precedence. Existing metadata, OCR, artifact and ownership assertions remain.

## Actual results

- **PASS:** 65 deterministic Deno tests, 0 failed; 1 opt-in live test ignored.
  Includes 6 source-identity tests and both pre-existing public-metadata tests.
- **PASS:** Worker entry-point type check with frozen existing lockfile.
- **PASS:** 25 Python contract fixtures and 5 OpenAPI-reference tests.
- **PASS:** `git diff --check`.
- No runtime network permissions for tests. No ASR/keyframe provider, media
  downloading, platform login, real platform success rate, Supabase Edge/Storage,
  iOS or production deployment was tested. #118/#138/#141 remain open.
- PDF work in separate #158 and health dependency work in #166 are not in this
  branch; this count must not be represented as their aggregate acceptance.

Commands: the complete [#134 manual regression commands](ISSUE_134.md) cover
all worker `*_test.ts`, including these tests. Full stdout:
[Deno](issue-118-full.log), [Python](issue-118-python.log).
