# Issue 137 Instruments fixture

The DEBUG fixture runs only when both `--uitesting` and `--uitesting-performance-fixtures` are present. In the Recipe scheme's Run > Arguments Passed On Launch, add:

```text
--uitesting
--uitesting-performance-fixtures
--uitesting-performance-seed=137
--uitesting-performance-count=500
```

Change the count to `1000` or `5000` for the other profiles. Use `--uitesting-performance-collections=10` or `100` and `--uitesting-performance-covers=with` or `without` to select the remaining fixture dimensions. Add `--uitesting-performance-reset` once to regenerate that seed/count/collections/cover profile; remove it for repeat runs so cold-start measurements load the already-written fixture. Each profile lives under `Application Support/RecipeUITestPerformance/seed-<seed>/count-<count>/collections-<count>/covers-<mode>/library.json`. The normal `Recipe/library.json` is not opened or migrated in this mode.

Fixtures contain synthetic titles and text, six ingredients and four steps per recipe, 10 or 100 collections with memberships, 300 grocery items, 90 meal-plan entries, and optionally one generated JPEG cover shared across recipe records. Search, recipe writes, favorite writes, grocery writes, and active library scrolling appear as app signposts in Instruments. SwiftUI Instruments can be used alongside Time Profiler and Allocations for scrolling and hitch analysis.

For each device and profile, collect at least five launches with the same OS/build and record p50/p95 search and write durations, peak memory, main-thread stalls, and scroll hitches. Save traces outside Git under `.tmp/issue-137/<main-sha>/<device-os>/<profile>/`. This fixture and its build do not provide performance results; attach the device traces before closing the issue.
