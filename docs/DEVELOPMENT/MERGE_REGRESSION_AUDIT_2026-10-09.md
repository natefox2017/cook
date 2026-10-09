# Recipe Pals — Merge Regression and Auto-Merge Root Cause Audit

**Date:** 2026-10-09. **Snapshot:** `main@2b180289d22a9b0beb20e27027f37acfcec18aa0` before the proposed fix. GitHub inventory: 456 tracked tree nodes, 371 files. This is a repository-source/static audit, **not a claim of Xcode/phone/runtime acceptance**.

## Why previously approved code was changed

- [PR #223](https://github.com/natefox2017/cook/pull/223), merged as `5c50aa7`, changed onboarding's approved first page from `Create with AI` to `Save recipes your way`, and changed the Premium AI feature to a generic collecting feature. This was an actual source modification, **not simply stale iOS Settings cache**.
- [PR #226](https://github.com/natefox2017/cook/pull/226), merged as `4e26fe7`, restored the AI-first story and Premium row and added `testOnboardingPreservesApprovedAIStoryAndPaywall` plus Chinese-screen UI assertions. Those new cases are currently **source only** until UI Runner #189 is functional.
- [PR #225](https://github.com/natefox2017/cook/pull/225) aligned App and Share Extension bundle names; [PR #229](https://github.com/natefox2017/cook/pull/229) removed additional obsolete iOS public copy. Notification settings' **actual device-level title** still requires acceptance under [#136](https://github.com/natefox2017/cook/issues/136).
- A textual, conflict-free Git merge does **not** detect design/behavior regressions: the old workflow had no first-launch/paywall source guard and did not execute device tests. Some instructions/approval documents also still described the obsolete RecipePouch product name, making stale edits more likely.

## Why a manual click seemed necessary

GitHub event history provides the exact distinction:

| PR | Manually changed by owner | Merged by Actions bot |
| --- | --- | --- |
| [#223](https://github.com/natefox2017/cook/pull/223) | `ready_for_review` 2026-10-09 13:23:38 UTC | 13:23:49 UTC |
| [#224](https://github.com/natefox2017/cook/pull/224) | `ready_for_review` 2026-10-09 12:32:08 UTC | 12:32:21 UTC |
| [#229](https://github.com/natefox2017/cook/pull/229) | Normal PR created 14:35:41 UTC | 14:35:54 UTC |

The original merge job had `github.event.pull_request.draft == false` at job level. The two delayed PRs were **drafts**, and only the owner's Ready-for-review action allowed the already-working merge bot to run. Successful bot runs do not mean that a Draft ever auto-promoted. Conversely, waiting for native GitHub `Enable auto-merge` is not the same as this repository's immediate merge bot on private Free.

## Source audit findings

The snapshot was inspected through live repository file reads:

- **67 iOS Swift files** across app, Core, tests and Share Extension: no `Save recipes your way` or older user-facing RecipePouch UI messages were found. First launch shows `OnboardingAI` / `Create with AI`; Premium has `Create with AI`. Four string catalogs are valid JSON; App has **808** keys with zh-Hans/zh-Hant/ja values; Share Extension has **14**.
- **121 source files** under `admin/` and `supabase/` (`.ts`, `.tsx`, `.mjs`, `.py`, `.sql`) and **47 ancillary text/config** entries were scanned for old branding, stale wording, hardcoded legacy identifiers and TODO/FIXME. There was one **public error text** `Sign in with your RecipePouch account.` in the undelivered recipe-imports Edge function, and an OpenAPI `info.title` still branded RecipePouch. This PR changes **repository source only**, not deployed Edge bundles.
- Older `RecipePouch` tokens in `RecipeLocalEraseMarker`, `recipepouch.recipes` export format, Auth Keychain service `com.modelhub.cook.supabase-auth`, local StoreKit fixture ID and Share Extension error domain are **technical persistence/compatibility contracts**. They must not be mass-renamed without a migration. Admin npm package and icon filenames, Edge source comments and old import User-Agent are also not proof of an older executable replacing the current screen code.
- The stale `docs/UI_DESIGN_APPROVALS.md`, `docs/DESIGN_SYSTEM.md`, `docs/IOS/UI_IMPLEMENTATION.md`, `docs/LOCALIZATION.md`, and old `docs/DEVELOPMENT/github-ruleset.md` conflated current code with historical names/counts and old paid ruleset checks. The fix updates their current-contract wording while retaining archived evidence.

## Fix and safety boundary

1. Complete work as a **normal PR** by default; no Ready-for-review click. A true WIP Draft remains Draft; a finished Draft opts into promotion explicitly via `AGENTS.md`'s completed-work marker or `auto-ready` label, so the bot can promote it without the owner clicking.
2. Extend merge triggers for PR editing/labels and review-submitted events, and retry GitHub's transient `mergeable=UNKNOWN`. Keep head SHA matching, same-repository restriction, conflict checks, review decisions and unresolved review-thread protection.
3. Before automatic merge, read the PR's current first-launch and Premium source, both bundle InfoPlists/localized catalogs and changed-file diffs **as inert data**, run the branding validator fetched from the trusted base commit, and reject old AI copy or newly added RecipePouch display strings. Do **not** check out or execute PR-head code with the write-enabled `pull_request_target` token.
4. Do not claim this small gate equals Xcode build, UITests, true notification name update, subscription verification or Supabase deployment. Those remain under [#136](https://github.com/natefox2017/cook/issues/136), [#189](https://github.com/natefox2017/cook/issues/189), [#132](https://github.com/natefox2017/cook/issues/132), and [#155](https://github.com/natefox2017/cook/issues/155).

This is a targeted prevention of **known source regressions**, not a proof that every possible functional bug has been eliminated. No production config, credential, payment or user data was changed by this audit.
