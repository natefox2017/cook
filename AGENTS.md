# Recipe — Agent Instructions

Use this file as the repository-wide guide for coding agents. Keep changes scoped to the user's request, preserve unrelated work, and follow the current project documentation.

## Naming Contract

- The technical project, Xcode project, target, Swift module, shared package, folders, files, and code identifiers use **Recipe** naming.
- The user-facing product brand is **Recipe Pals**. Technical names and legacy data identifiers keep their existing compatibility contracts.
- Primary paths are:
  - `ios/Recipe.xcodeproj`
  - `ios/Recipe/`
  - `ios/RecipeCore/`
  - `ios/RecipeUITests/`
  - `ios/ShareExtension/`
- Do not create new `Cook*` technical types, targets, modules, source folders, or filenames.
- Preserve compatibility for existing users. Legacy bundle identifiers, URL schemes, persisted files, and `cook.*` keys may be read or migrated when changing them would lose existing data or break deployed integrations.
- New local preference/session keys use the `recipe.*` namespace. Migration code must continue to understand supported legacy `cook.*` values.

## Project Overview

Recipe is the native iOS codebase for Recipe Pals, a private recipe collection and cooking app. V1 focuses on collecting recipes from third-party sources, organizing them privately, and using them for cooking, shopping, and simple meal planning. The backend uses Supabase for authenticated sync and asynchronous import services.

## Project records and canonical task source

- **Linear is the sole task system:** [Cook — Recipe Pals Development](https://linear.app/gengyun/project/cook-recipe-pals-development-8c015c72cb6a), team `GEN`. Linear Issues contain all features, bugs, Todo checkboxes, optimization, research, tests, dependencies, review and acceptance evidence. Linear Board and assignee are the only claiming/status authority. GitHub private repo `natefox2017/cook` stores branches, code, commits, CI checks, reviews and PRs only. Markdown holds durable product requirements, architecture, APIs, design, coding/QA standards and AI collaboration rules, not a task queue or diary.
- Original GitHub Issues/PRs are archived historic evidence. [GEN-40](https://linear.app/gengyun/issue/GEN-40/cook-migration-make-linear-the-exclusive-issue-and-kanban-source) governs cutover. Do not create new GitHub task Issues, do not claim using labels, GitHub Projects, Todoist or chat memory. Do not mix Cook tasks with other projects in the same Linear team.
- Recipe Pals V1 is private recipe collection and cooking. Later approved scopes can include lawful import evidence, reviewable AI edits, private-by-default sharing with explicit opt-in. This does not authorize public community feeds, automated publication of copyrighted/private recipes, fingerprint tracking or paid referral rewards. Consult the current Linear Issue and durable product specs before implementation.

## Linear Board: required task claim, six-state workflow and delivery

- **Six target states:** `Backlog` unplanned, `Ready` fully specified/unblocked/unassigned, `In Progress` claimed, `In Review` PR submitted or verification pending, `Blocked` documented blocker, `Done` all acceptance passed. Some connected `GEN` team statuses currently lack `Ready` and `Blocked`. Until an authorized team administrator creates and confirms them, leave migrated tasks in `Backlog` and do not silently substitute `Todo`, `Canceled` or `Done`.
- **Before development:** read current default branch, active branches, PRs, CI, this file and durable specs; inspect the live Cook Linear Board, issue owner, checked Todo, dependencies and other work. Search prior Linear issues and merged code for duplicates. Do not re-implement already merged work.
- **One independent deliverable = one Linear Issue, normally one PR.** Split parent/sub-issues on independently verifiable boundaries, link prerequisites, freeze shared API/schema contracts before parallel development, avoid simultaneous edits to the same files, reuse established code and maintained license-compatible open source. Avoid both unrelated bundles and non-deliverable microtasks.
- **Zero-context Issue contract (all ten):** (1) background/problem, (2) observable objective, (3) current implementation and gap, (4) real files/modules/screens/APIs/DB changes or N/A, (5) detailed behavior/input/output/edge/error/retry rules, (6) architecture/style/compatibility/security limits and prohibited changes, (7) dependencies and linked Linear IDs/PRs/docs, (8) individually verifiable Markdown `- [ ]` Todos, (9) exact test commands, fixtures, expected vs real PASS/FAIL/NOT RUN, (10) deliverable commits, PR, evidence, Linear state and handoff. A fresh AI must be able to execute/test/accept using only GitHub and the issue; mark unknown claims TO VERIFY. Incomplete work remains Backlog.
- **Only Ready is claimable:** re-read the Linear issue/board plus latest code, PRs and dependencies; verify Ready, no assignee or competing implementation; assign yourself and set `In Progress`; immediately re-fetch the same Linear issue and confirm assignee/status; record unique agent/session claim ID and UTC time in Linear. Only then create/continue the focused branch. A GitHub label/issue assignee, chat, old Todoist task or branch is never a claim.
- **Concurrent claims are not atomic locks.** Even after readback, two AI agents could race; on conflicts, inconsistent status, another assignee or duplicate PR, STOP and coordinate one owner before modifying code. Do not build unneeded locking infrastructure.
- **Immediate sync:** after each accepted Todo, update its Linear checkbox, commit/PR/test proof; PR title, branch and description must include `GEN-<number>` and issue URL. PR submission moves to `In Review`; automated merge must not move directly to Done without required tests. Closed-unmerged PR needs investigation. Move blocked tasks to `Blocked` (when configured) with exact reason and recovery steps. Re-read status after each change.
- **Done:** after complete Todos, required tests and approvals, merged PR (or verified research-only deliverable) and satisfied dependencies, set Linear `Done` and re-read. Merged PR ≠ signed-device/staging/production acceptance. Parent Issue waits for necessary children.
- **Migration-only exception:** GEN-40 may change management files and archive old trackers while statuses are being configured. It does not permit unclaimed feature/bug implementation; all transferred product issues remain Backlog until Ready is truly configured and checked.

## Documentation versus active issues

- Specs such as `docs/PRODUCT_BASELINE_V1.md`, `docs/USER_FLOWS.md`, `docs/DESIGN_SYSTEM.md`, `docs/ARCHITECTURE.md`, `docs/RECIPE_IMPORT_PIPELINE.md`, `docs/DATA_MODEL.md` and `docs/ROADMAP.md` record lasting product/design/system contracts, not executable task queues. Each changed specification links its canonical Linear Issue.
- Record bug fixes, Todo, QA failures, temporary handoffs, progress and PR test evidence **only in Linear**. Never create additional Markdown progress snapshots, dated QA reports or duplicate checklists; do not modify docs/README for routine fixes. Retain old evidence files until necessary facts are safely transferred.
- Link GitHub PRs with `GEN-n` in branch/title/body. Do not use GitHub `Closes #123` for migrated work; original GitHub Issue numbers are archival only. Use Linear issue references for partial deliverables and mark Done only after acceptance. Verify PR integration events rather than assuming automations fired.

## Code Style and Comments

- **Never compress Swift declarations, view builders, closures, or control flow onto one line.** Source must remain readable in a normal code review.
- Format all touched Swift before committing. Prefer standard Swift formatting: 4-space indentation, one declaration or statement per line, readable trailing closures, and wrapped argument lists when they become long.
- Every Swift source/test file must begin with a short English file header:
  - `// Developer: gengyun`
  - `// Purpose: <one concise sentence describing the file>`
- Comments must be written in English.
- Add comments for non-obvious invariants, compatibility migrations, security boundaries, concurrency, persistence, and intentionally conservative parsing. Do not narrate obvious syntax.
- Public or shared APIs should use descriptive identifiers and concise documentation comments when behavior is not self-evident.
- Do not use mass comments as a substitute for clear names and structure.
- When touching previously minified code, expand and format the entire affected declaration/file rather than adding more compact code around it.

## Product Rules

- The normal collection flow is: share from a third-party app, choose Recipe Pals, receive an acknowledgment, and return to the source app.
- The Share Extension receives and queues input, then finishes promptly. It must not wait for full parsing or AI processing.
- Import complete information automatically. Send only missing, anomalous, or low-confidence fields to a review flow.
- Keep manual recipe entry as a fallback.
- Preserve original source URL, source platform, and available author/title metadata.
- Do not add a community feed, public posts, follows, likes, comments, creator profiles, or a public recipe marketplace to V1.
- Never turn vague amounts such as “to taste,” “a little,” “about,” or “unknown” into invented exact values.

## Architecture and Code Boundaries

- iOS app and Share Extension: SwiftUI and native iOS APIs.
- Backend: Supabase Postgres, Edge Functions, Storage, and Queues/pgmq.
- AI providers are called by the backend through an OpenAI-compatible provider layer. Never put provider secrets or service-role keys in the client.
- Do not introduce a second UI framework, database, or queue unless the task explicitly requires it.
- Keep imports asynchronous and idempotent. Preserve partial results and source evidence when parsing fails.
- Validate fetched URLs and redirects; protect import services from SSRF, private-network access, oversized downloads, and excessive processing time.

## Repository Map

- `ios/Recipe/` — iOS app, screens, design helpers, and services
- `ios/RecipeCore/` — shared domain models and local persistence
- `ios/RecipeUITests/` — native UI regression tests
- `ios/ShareExtension/` — native share extension
- `supabase/` — backend configuration, migrations, and functions
- `docs/` — durable approved product requirements and specifications, not work logs or bug-fix reports

## Change Workflow

- Keep `main` PR-only. Use a focused branch for implementation.
- **Before a PR, rebase/merge the current `origin/main`** and compare against the latest accepted onboarding, branding, navigation and purchase contracts. Do not restore older screen implementations from an old branch merely to resolve conflicts.
- **Create a regular (non-Draft) PR only for a correctly claimed Cook Linear Issue** after its implementation Todo is complete. Include the `GEN-n` identifier, exact issue URL, completed Todo IDs and actual test results. Trusted same-repo auto-merge is allowed, but code merge is not evidence of end-to-end acceptance or Linear Done.
- Draft PRs are only for genuine work in progress. If a completed PR was already opened as Draft, append the exact completion marker `<!-- auto-ready: complete -->` to its PR body, or apply the `auto-ready` label; the workflow promotes it and merges it without a manual UI click. Do not set either marker before work is complete.
- Do not overwrite an approved design with copy/layout taken from stale history. The first onboarding story remains **OnboardingAI / Create with AI** and Premium retains the AI feature row unless the user expressly approves a change. The merge workflow blocks those regressions and obsolete user-facing RecipePouch naming.

- **All tasks and acceptance belong in Linear Issues.** Confirm a unique Cook Linear Issue and Ready → In Progress owner/state readback before coding. Update each Todo, real tests and Linear status; do not create GitHub Issues or write routine progress Markdown. No verified Linear claim means no implementation.
- Freeze shared API/schema decisions before parallel work; avoid simultaneous edits to the same core file.
- Inspect the current implementation before changing it. Do not apply review comments mechanically.
- Make the smallest safe change that satisfies the request. Preserve existing behavior and user data.
- Do not remove failing tests just to make checks pass. Do not commit secrets, access tokens, passwords, or private credentials.
- Keep UI changes consistent with `docs/DESIGN_SYSTEM.md` and the existing app.
- Use short, localized screen titles and menu labels (`About`, `Help & Support`, `Premium`), without appending `Recipe Pals` to navigation titles. Keep the brand where identification matters, such as bundle names, sharing instructions, and About app identity.
- Groceries is a private shopping checklist, **not** a storefront, marketplace, or checkout experience; do not advertise or add commerce functionality.
- User-facing copy follows product language/localization rules. Source identifiers and technical documentation use consistent Recipe naming.

## Language During Development

- Until the user explicitly approves multilingual release, default to English for all user-facing Recipe Pals UI regardless of the iPhone's preferred language.
- Keep the four fully translated UI languages (en, zh-Hans, zh-Hant, ja) available for manual selection. Explicit `--uitesting-locale` wins for deterministic UI smoke tests; ordinary launches and UI tests without a forced locale respect manual selection, defaulting to English when unset.
- When computing displayed strings, use a `LocalizedStringResource` with the app's explicit locale. A bare `String(localized:)` can fall back to the device language even when SwiftUI's locale is overridden.
- Do not globally override system `AppleLanguages` or remove translation resources as a test shortcut.

## CI Policy

- Keep CI intentionally minimal.
- The private GitHub Free repository uses one lightweight trusted merge workflow to squash-merge eligible normal PRs directly; marked-complete Drafts may be promoted automatically. Never use `gh pr merge --auto`, which depends on paid native auto-merge protection.
- Keep unmarked Draft PRs, change requests, unresolved review threads, and unmergeable PRs out of automatic merges. Do not check out or execute PR code with the write-enabled merge token. The merge workflow validates approved UI and naming contracts by treating PR-head files as **untrusted data** and executing only trusted-base validators.
- Do not reintroduce per-PR Xcode builds, simulator runs, Swift tests, or documentation CI unless the user explicitly requests them.
- Required status names may remain as compatibility gates, but they must not pretend to validate work they do not actually validate.
- Run substantive build/tests manually when needed and report exactly what was executed.

## Build and Verification

Core tests:

```sh
swift test --package-path ios/RecipeCore
```

iOS simulator tests:

```sh
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO test
```

For UI changes, inspect the affected flow in a simulator when the environment permits. The minimum deployment target is iOS 18.0. Do not claim simulator, signing, backend, StoreKit, or end-to-end verification based only on static source review.
