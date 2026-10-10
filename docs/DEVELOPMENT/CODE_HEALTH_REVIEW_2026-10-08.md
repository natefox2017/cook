> **Historical optimization audit (2026-10-08), not fresh profiling or an active task list.** Prior RecipePouch branding is superseded by Recipe Pals. For real current library performance evidence, consult [DEV-95](https://linear.app/gengyun/issue/DEV-95); for the live backlog use [Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a), and re-read latest main before modifying code. Historic snapshots are preserved in Git history indexed by DEV-40.

# RecipePouch code-health review — 2026-10-08

## Scope and approach

Reviewed the current SwiftUI app screens, app services, and RecipeCore source with emphasis on repeated collection queries, high-frequency UI recomputation, import streaming, grocery consolidation and duplicate helpers. The branch starts from `main` after PRs #100, #102 and #103. This is a targeted behavior-preserving optimization, **not** a rewrite of the sync, authentication, data schema, or recipe parsing contracts.

The temporary English-only QA language policy from PR #103 remains unchanged.

## Implemented

| Area | Previous behavior | Change and preserved semantics |
| --- | --- | --- |
| Recipes filter | For every displayed recipe in a collection, scan the full membership list | Build `RecipeCollectionIndex` once for the filtered view and perform set membership checks |
| Collections index/list | Recount each collection by scanning all memberships and recipes; rescan membership for every picker row | Reuse a snapshot index for per-collection counts and picker checks |
| List rendering | Sort/filter the recipe result multiple times for count, empty state and grid | Compute one result per SwiftUI body render; the display order is unchanged |
| Favorites | Search recipes twice (exists and list) | Build the same favorites list once |
| Grocery consolidation | Scan the entire grocery list for every selected ingredient | Build a key-to-first-eligible-row index; preserve unchecked-only merge, name folding, case-sensitive units, exact decimal arithmetic and source attribution |
| Webpage import | Append every streamed byte individually to `Data` | Accumulate 16 KiB chunks while keeping the 2 MB hard maximum and cancellation check |
| Cooking timers | Two identical clock format functions | One private shared formatter, with unchanged output |

`RecipeCollectionIndex` is an immutable snapshot, **not a persisted cache**. This prevents stale membership values when RecipeStore publishes updates.

## Regression coverage added

- `RecipeCollectionIndexTests.swift`: multiple collections, duplicate memberships, missing IDs.
- `RecipeGroceryConsolidationTests.swift`: normalized ingredient consolidation, purchased-row protection, unit case sensitivity, consolidation disabled.
- Existing RecipeCore store, cooking, import, and UI tests remain in place.

## Checks and remaining risk

- Source-level changes were reviewed against the repository's existing behavior and coding conventions (English file headers, no unnecessary comments, no new dependencies).
- Xcode simulator build, real-device behavior, full UI screenshots, and actual test execution **must still be run on macOS**. GitHub's lightweight auto-merge workflow is not a compile or performance test.
- RecipeStore still saves an atomically written complete JSON snapshot per mutation. Changing serialization/persistence requires realistic large-library benchmarks and crash/recovery verification; intentionally not altered here.
- The Cloud Sync coordinator and cooking view still contain substantial multi-responsibility code. Extracting them without native test coverage risks regressions to sync conflict resolution, timers, and Share Extension handoff. Do this in smaller independently verifiable changes if profiling supports it.

## macOS validation commands

```sh
swift test --package-path ios/RecipeCore
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO test
```

Before release, profile a large recipe collection and grocery import with Instruments (Time Profiler, Allocations) and verify that the English QA override is intentionally disabled only after multilingual QA approval.
