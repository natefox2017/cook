# Issue 137 Instruments fixture

The DEBUG fixture runs only when both `--uitesting` and `--uitesting-performance-fixtures` are present. In the Recipe scheme's Run > Arguments Passed On Launch, add:

```text
--uitesting
--uitesting-performance-fixtures
--uitesting-performance-seed=137
--uitesting-performance-count=100
```

The Issue 137 matrix uses counts `100`, `1000`, and `5000`, each paired with collection counts `10` and `100`, and cover modes `with` and `without` (12 profiles). Count `500` remains accepted for compatibility with existing local runs. Prepare each measured launch with `--uitesting-performance-reset`, wait for the fixture-backed library to load, then force-quit and run the measured launch without the reset argument. This keeps writes and favorites from a previous run from changing the next run's input fixture. Each profile lives under `Application Support/RecipeUITestPerformance/seed-<seed>/count-<count>/collections-<count>/covers-<mode>/library.json`. The normal `Recipe/library.json` is not opened or migrated in this mode.

Fixtures contain synthetic titles and text, six ingredients and four steps per recipe, 10 or 100 collections with memberships, 300 grocery items, 90 meal-plan entries, and optionally one generated JPEG cover shared across recipe records. Search, recipe writes, favorite writes, grocery writes, and active library scrolling appear as app signposts in Instruments. SwiftUI Instruments can be used alongside Time Profiler and Allocations for scrolling and hitch analysis.

For each device and profile, collect at least five launches with the same OS/build and record p50/p95 search and write durations, peak memory, main-thread stalls, and scroll hitches. Save traces outside Git under `.tmp/issue-137/<main-sha>/<device-os>/<profile>/`. This fixture and its build do not provide performance results; attach the device traces before closing the issue.
