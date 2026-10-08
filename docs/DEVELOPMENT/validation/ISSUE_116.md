# Selectable PDF actual validation — #116 / #158

Executed 2026-10-08 UTC on Linux x86_64, Deno 2.9.6 / TypeScript 6.0.3.
Code tested: `950507c96e7eaba48fb2475ee85df6cde5d73594`, based on refreshed
`main@55ac164` and PDF PR #158, with the existing #165 type fixes merged
without rewriting or duplicating them. No production service or user document
was used. This is a manual check, not a new CI gate.

## Reproduced and fixed

- Frozen install rejected the old lockfile because `unpdf@1.8.1` was absent.
  Regenerated with Deno and the official npm registry; existing pinned versions
  and integrity checks remain, obsolete mirror URL overrides were removed.
- Actual Deno type checking rejected `isEvalSupported` and `pdf.destroy()`.
  The pinned bundled PDF.js no longer has eval or that option; its supported
  lifecycle is `pdf.loadingTask.destroy()`, also used by unpdf itself.
  See [Mozilla removal](https://github.com/mozilla/pdf.js/commit/f6bac014ea397bcabee7d42d07fbd9f67c2322c6).
- Strengthened real synthetic PDF assertions to require ready status and preserve
  vague amounts. Added an actual blank PDF and ten consecutive document parses
  with stable recipe/artifact identity and original source preservation.

## Actual results

- **PASS:** 66 deterministic Deno tests, 0 failed; 1 opt-in live test ignored.
  Seven tests are PDF-specific, including real PDF.js byte parsing.
- **PASS:** Worker entry-point `deno check`, type checking enabled and frozen lock.
- **PASS:** 25 Python contract fixtures and 5 OpenAPI-reference unit tests.
- **PASS:** `git diff --check`.
- Peak child RSS for the complete test/check/Python script: **340548 KiB**
  (Python `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss`). This includes Deno's
  TypeScript compiler; it is **not** a claim about deployed Edge peak memory.
- **NOT RUN:** Supabase Edge isolate memory/timeout, real Storage/queue,
  approved OCR provider, iOS/Share Extension, production or live user PDFs.
  The existing eight-second check is best effort between pages, not a hard
  preemption limit on a single parser call. Staging resource acceptance remains
  required before deployment (#135/#141).

## Reproduce

Use the complete command set in [Issue #134 validation](ISSUE_134.md) from this
branch. Its worker `*_test.ts` glob includes the new PDF tests. Grant no runtime
network permission. Use the committed frozen worker lockfile after a normal
registry cache fill. Do not use `--no-check` or modify TLS verification.

Full output: [Deno](issue-116-deno.log), [Python](issue-116-python.log).
#116 and #134 remain open for their distinct integration acceptance.
