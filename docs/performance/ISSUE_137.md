# Issue #137 — Isolated iPhone performance fixture and remaining capture plan

## Status / non-repetition boundary

**2026-10-09, source audit `main@18541b1`.** Fixture generation and launch gates landed via [PR #214](https://github.com/natefox2017/cook/pull/214). Existing [Issue #137](https://github.com/natefox2017/cook/issues/137) already records a successful **single 31.188-second Instruments session** with a 5,000-recipe / 100-collection / covers / seed 137 fixture, plus earlier macOS CLI p50/p95 and four signed hosted fixture PASS cases. Do **not** re-run those as if they were untested, or equate initial frame rendering with total cold-start latency. This plan prepares only missing measurements; **no new iPhone trace has been captured by this documentation update**.

## Environment and fixture contract

- Device: user's current **iPhone 16 Pro Max**, iOS 27.0.1 at the recorded baseline, **normal Dynamic Type**. Reconfirm OS/device at execution; no second device or simulator is authorized.
- Freeze exact `git rev-parse HEAD`, Xcode version, signed App bundle ID, `CFBundleVersion` and installed binary's source SHA before comparing traces. If source/build identity is unavailable, label the run PARTIAL; never substitute the audit SHA.
- Use only **DEBUG isolated fixtures**, no real user library, account or private media. Launch arguments (Recipe scheme → Run → Arguments):
  ```text
  --uitesting
  --uitesting-performance-fixtures
  --uitesting-performance-seed=137
  --uitesting-performance-count=100
  --uitesting-performance-collections=10
  --uitesting-performance-covers=without
  ```
- Supported count grid: **100, 1,000, 5,000** recipes × **10, 100** collections × **with, without** covers = **12 profiles**. Scale order from small to large if performance or available storage limits the device; record every skipped cell with its reason. The implementation also accepts count 500 for existing compatibility; it is **not** a thirteenth required matrix cell.
- Each recipe fixture has synthetic title/text, 6 ingredients, 4 steps; standard fixture distribution includes 300 grocery items, 90 meal-plan entries and multi-collection membership. Record seed, 12 profile parameters, ingredient/step membership counts and fixture file SHA-256 for each run. Validate expected recipe/collection/grocery/plan counts on launch, or mark that sample invalid.
- Profile path is scoped under `Application Support/RecipeUITestPerformance/seed-<seed>/count-<count>/collections-<count>/covers-<mode>/library.json`. The normal persisted `Recipe/library.json` must not be opened or migrated in this mode.
- Prepare each profile **once** with `--uitesting-performance-reset` to generate the isolated fixture. Remove that reset flag for every measured start. After actions mutate favorite/recipe/grocery state, restore only the same QA fixture **before the next independent measurement set**, never clear real user preferences or data. Record whether the run is cold, warm, offline or resumed.

## Missing capture actions and measurement windows

For each required profile feasible on the phone, collect **at least five independent runs per interaction** with stable environment and unchanged synthetic initial state. Capture raw durations in milliseconds, p50 and p95 derived from the recorded raw observations (with five samples the p95 estimate has high uncertainty). Report median/p95 **per interaction type**; don't aggregate unrelated actions.

| Action | Exact measurement | Instruments / evidence |
| --- | --- | --- |
| Search | Focus search, type a fixed 6–12 character matching query character-by-character, wait for stable results; isolate each `Library Search` signpost and end-to-end visible update | Time Profiler main-thread stack, per-character duration, frame/hitch time and screenshot/result count |
| Recipe save | Edit a synthetic recipe field, Save, wait for persisted UI state; follow app/RecipeCore commit spans where visible | Action → saved UI duration, file-write timeline, main-thread blocking and persistence confirmation |
| Favorite | Toggle a fixed synthetic recipe heart and confirm new favorite state | `Favorite Write` signpost, p50/p95, allocation/peak RSS delta |
| Grocery | Check/uncheck a fixed synthetic grocery item and verify state | `Grocery Write` signpost, p50/p95, save cost and RSS delta |
| Collections | Enter/exit and switch collections with multi-membership at 10 and 100 collection sizes | Navigation-to-visible-list latency, diffing hot paths and any loading indicator |
| Scrolling | Scroll the recipe grid/list **100 consecutive swipes** at steady velocity, preserving order and recording run length; repeat the entire run at least five times where feasible | `Library Scroll` signpost, SwiftUI/Animation Hitches, dropped frames / hitch ratio, Time Profiler hot call stacks |
| Start/offline | New install/fixture prepared → cold launch, first interactive frame, offline kill/relaunch and online reentry; log each phase separately | Full launch wall clock (not just Initial Frame Rendering), os_signpost timelines, app launch state and offline cache result |
| Memory | At baseline, after load, after each action group, and after scrolling collect actual **peak resident memory** (RSS / physical footprint where available), Memory Graph live retained objects and allocation timeline | Instruments Allocations/VM Tracker/Memory Graph with units, screenshot/trace and per-action before/after comparison |

If automation cannot connect because [#189](https://github.com/natefox2017/cook/issues/189) remains Code 74 before UI test execution, obtain **manually performed isolated QA actions with Instruments recording** when feasible. Record whether the manual path is used; do not relabel a hosted fixture PASS as UI Runner PASS. Do not change signing, security settings or actual personal data to force automation.

## Data capture and acceptance

For each sample record an anonymized run ID; exact build+device+OS; wall-clock start/end; recipe count; collections; covers; fixture checksum; network state; action; raw latency(s); main-thread stall/hitch; peak physical footprint; output trace path; result `PASS/FAIL/PARTIAL/BLOCKED`; and anomaly notes. Save traces under ignored `.tmp/issue-137/<actual-build-sha>/<device-os>/<profile>/<run-id>/` and link **accessible** sanitized reports in #137 (a local path alone is not retrievable by a remote reviewer).

Keep [the existing Instruments launch observation](https://github.com/natefox2017/cook/issues/137#issuecomment-6080183636) as a separate, scoped datum: reported Initial Frame Rendering **799 ms** was not total cold start; ending Heap+Anonymous VM **361.79 MiB** was not peak RSS; allocation total **2.84 GiB** was not simultaneous footprint. The existing CLI largest-cover search p50/p95 **46.40/47.21 ms** is macOS-only, not a device UX timing.

### Release / change decision

A prospective performance fix needs: one reproducible expensive stack or measured UI hitch, a minimal implementation proposal preserving atomic writes/crash recovery and migration behavior, and before/after metrics from **the same signed device, fixture and build lineage**. If no bottleneck is reproduced, record the trace-limited conclusion and keep speculative persistence refactoring out of scope. Missing/blocked traces cannot be marked PASS.
