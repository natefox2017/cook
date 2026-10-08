# RecipePouch Full-Repository Code Audit — 2026-10-09

## Baseline and method

- Baseline: `main` at `975f70b0eed9684530275f2b8c187a371f747524` (after PR #107).
- Inventoried the full tracked file tree (250 entries) and statically scanned **72 non-test Swift, TypeScript, and SQL source files** (43 Swift, 19 TypeScript, 10 SQL) for dangerous forced casts, fatal errors, TODO/FIXME markers, assertion usage, and detached tasks.
- Reviewed critical execution paths in the SwiftUI app, RecipeCore model/store, Share Extension, durable import workflow, StoreKit/Auth, Supabase import API/worker/artifact endpoints, storage cleanup and owner-scoped SQL grants/RLS.
- Compared prior optimization PRs #103–#107 to the current source; inspected existing unit/integration test cases rather than treating minimal auto-merge CI as verification.
- This is a **static source audit and focused fix**, not proof of complete runtime acceptance or measured performance.

## Confirmed defects fixed in this branch

1. **Portable JSON includes image media despite UI claiming it does not.** `RecipePortableExport.json` encoded unmodified `Recipe` objects, which include `coverData` and `coverAsset`. Exporting many recipe photos unnecessarily inflated the portable text-data archive. The recipe-only export now clears those two fields on temporary recipe copies. It preserves recipe IDs, ingredients, steps, original source text, notes, and membership relationships. `RecipeStore.exportData` (the full local-library JSON) is deliberately unchanged.
2. **Zero-byte shared attachments were recorded as successful receipts.** `RecipeShareInbox.receiveFile` previously accepted empty Data, while `fileData(for:)` refused it during upload. The receive boundary now rejects empty image/document data before creating any receipt, preventing misleading "Saved" acknowledgements and permanently unprocessable pending items.

Added `RecipePortableExportTests` and `RecipeShareInboxTests` regressions. The focused Foundation-only Swift sanity probe passed for media stripping and empty-data rejection; **these are not tests of the full RecipeCore package**.

## Subsequent fixes merged into main

- [PR #109](https://github.com/natefox2017/cook/pull/109) unifies the historically stable SHA-256-based receipt ID transformation, which was duplicated for URL/text and image/file sources. Two fixed ID fixtures guard compatibility, file retry deduplication and source persistence.
- [PR #110](https://github.com/natefox2017/cook/pull/110) treats task cancellation during share-job submission/polling as an expected lifecycle event, not an import error. Its regression case verifies the pending receipt remains for retry.
- The two earlier contract fixes above were merged as [PR #108](https://github.com/natefox2017/cook/pull/108). An isolated Swift/Foundation sanity probe confirmed the data-handling rules, but **full Xcode and RecipeCore test execution remain unverified**.

## Static findings retained for targeted follow-up

| Priority | Area | Finding | Required verification |
| --- | --- | --- | --- |
| P1 | `RecipeStore.commit` / cloud sync | Every mutation validates and serializes a complete JSON library on the main actor before atomic disk write. Large collections, especially with embedded image data, can cause interaction latency. No profiling evidence exists yet to justify changing its crash-safe persistence boundary. | Benchmark large libraries on an iPhone with Instruments Time Profiler and Allocations; preserve atomic writes, migration compatibility and crash recovery. |
| P1 | `CloudSyncCoordinator` / Share handoff | Stateful sync and import coordination includes account transitions, network retries and conflict resolution across many await points. Mechanical extraction could introduce stale-account updates or deletion races. | Simulate two accounts/two devices, offline edits, concurrent refresh, token expiry and interrupted erase before further decomposition. |
| P1 | Release QA | Current environment cannot run Xcode, device sign-in, StoreKit purchases or extension host-app acceptance. Existing minimal PR workflow does not build/test the product. | Run `swift test --package-path ios/RecipeCore`, native `xcodebuild test`, app-language regression and production Supabase ownership tests on a Mac/test deployment. |
| P2 | `RecipeShareInbox.receive(.text)` | Incoming shared text is trimmed before receipt persistence. This may drop leading/trailing whitespace from original recipe evidence. Changing the fingerprint requires care to preserve idempotency for historical receipts. | Add round-trip whitespace regression and migration-aware identity design before changing existing hashes. |

## What was deliberately not changed

- No authentication/session/StoreKit/sync contract rewrite, RLS migration, production environment config or external endpoint change.
- No removal of four-language catalogs: the **temporary English-default QA policy remains active** in both app and extension.
- No reintroduction of expensive CI workflows.
- No claim that source-level checks prove app performance, backend deployment health, iOS UI correctness, security of every possible input, or production release readiness.

## Release checks

```sh
swift test --package-path ios/RecipeCore
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO test
```

Also exercise the Share Extension with empty and nonempty attachments, verify the two export formats (recipe-only vs full-library JSON), inspect export size with photo-heavy libraries, and test end-to-end owner isolation against the actual Supabase project.
