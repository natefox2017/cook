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

## Source of Truth

### Live backlog, snapshots, and user-approved extensions

- **Live task and acceptance evidence is in GitHub Issues; live claim/status is in Todoist**, not a dated Markdown status snapshot or `OPEN` text in a closed historical ticket. Read the latest GitHub Issue/PR and Todoist card before any action. The former release umbrella #139 and older device/test Issues #126–#129/#134 are closed and retained as historical evidence; current selected-release acceptance is #251.
- The user's approved **next-phase** extensions are AI-assisted source/evidence drafts and edit (#238–#241), opt-in **single-recipe** Web/long-image sharing (#242–#245), optional later invite rewards (#246), and detail metadata/UI (#247–#248). These are **planned, not shipped**. They do not authorize a public feed/community, automatically publishing imported private/copyrighted material, user fingerprinting or real reward payouts.
- Import deployment tickets #116–#120/#130/#135/#138/#141/#164 were closed as `not_planned`; **do not reopen them or treat them as passing integration tests**. For the newly approved functionality use #250 for controlled staging and #251 for release-scope acceptance. Changes to production infrastructure require separate owner approval.
- Keep historical design/QA/provenance records as read-only evidence; place corrections, missing test evidence, and current execution status in the relevant GitHub Issue, not a new dated Markdown note. Use `docs/ROADMAP.md`, `docs/PRODUCT_BASELINE_V1.md`, and `docs/PRODUCT/*.md` only for durable product requirements; GitHub Issues own the live work state.
- During testing, English is the default unless the user explicitly selects a bundled language under Settings → Language & Country. Manual language and country preferences are partially implemented; additional language packs and automatic system-language release fallback remain **open in #230**.



## GitHub Issues + Todoist Board — mandatory multi-agent task management

- **Four authoritative layers:** GitHub Issues own all requirements, bugs, technical debt, tests, independent Todos, dependencies, acceptance evidence and final results. **Todoist Board alone owns claiming, queueing and task status.** GitHub PRs own branch changes, review and merge. Markdown owns only durable product, architecture, technical/API contracts, development standards and AI collaboration rules — never a parallel task queue or progress diary.
- **One repository → one official Todoist Board; one independently deliverable Issue → one live task/card.** Official Cook board: [Cook — Development Kanban](https://app.todoist.com/app/project/6hj76CCMgwhrRp6m). Do not use the separate Nonstop pilot. A Todoist task contains the repository, GitHub Issue number and link, and a PR link once available; keep its full requirement and Markdown checkboxes only in the Issue. Never duplicate cards for the same Issue.
- **Exactly six ordered Todoist Sections:** `Backlog` (insufficiently specified), `Ready` (well-specified, unblocked and unclaimed), `In Progress` (successfully claimed), `In Review` (PR submitted and review/acceptance pending), `Blocked` (owner keeps claim; reason and recovery in Issue), `Done` (PR merged, all necessary acceptance verified). Do not invent intermediate claim/closed statuses. Moving to **Done does NOT complete a Todoist task**: never invoke Todoist's task completion/checkbox; keep historical cards visible and `checked=false` for de-duplication and audit.
- **Before every task:** read this file and relevant technical rules; inspect current default branch, worktree, branches, active PRs and CI/reviews, both open and historical Issues, all completed Todo checkboxes, and the live Todoist board. Reuse an existing Issue rather than reproducing finished code or creating duplicates. If an Issue is missing its Todoist card, reconcile it before any feature work. The GitHub Issue/PR and Todoist live state override chat history and old status documents.
- **Issue completeness gate:** every independent Issue must describe (1) background/problem, (2) objective/output, (3) current implementation/unfinished behavior, (4) concrete files/modules/screens/APIs/database scope (or N/A), (5) precise flow/interaction/inputs/outputs/edge cases/errors, (6) architecture/code/compatibility/prohibitions and reuse constraints, (7) dependencies and links to upstream Issues/PRs/specs, (8) individually verifiable `- [ ]` acceptance checkboxes, (9) exact test commands/fixtures/scenarios/expected results and `NOT RUN` boundaries, (10) PR/commit/test evidence and Issue/Todoist handoff requirements. Assume a completely context-free AI must execute, test and objectively verify it from current GitHub alone. Mark unknowns `TO VERIFY`; do not say 'as previously discussed'. Incomplete/blocked work remains `Backlog`/`Blocked`, never `Ready`.
- **Parallel split:** one independent deliverable should have one Issue/card and normally one PR. Large initiatives use parent + child Issues and a parent Issue checkbox for each required child; close the parent only after required children pass. Freeze shared API, schema, migration or file-format contracts before parallel development. Parallel agents should not edit the same core file. Prefer existing repository code and mature, license-compatible open-source solutions. Do not over-split non-independent details or bundle unrelated capabilities.
- **Claim exactly from Ready (no Todoist assignee required):** (1) read current Board and candidate Ready card; (2) read the linked Issue, latest default branch/code, active PRs/branches and dependencies; (3) verify nobody is already developing it and all prerequisites pass; (4) re-read the card still in `Ready`; (5) move the card to `In Progress`; (6) immediately re-fetch it and confirm Section/identity; (7) check for any competing claim/PR and record unique agent/claim ID, UTC time and branch in the Issue; (8) only then create/continue its isolated development branch. Other five Sections are not claimable. Issue labels, GitHub assignees, branch names and chat messages are **never substitute claims**.
- **Concurrency caveat:** Todoist move-and-readback is **not atomic mutual exclusion**. Two agents can see Ready simultaneously. On contention, inconsistent reads, another PR or unexpected ownership, stop and reconcile with the Issue and actual code; never silently overwrite a peer. Do not build a distributed lock unless a real coordination requirement and authorization justify it.
- **Synchronize after each Todo:** immediately check the corresponding GitHub Issue box, link actual commit/PR/test results with environment and `NOT RUN` for anything untested, keep Todoist Section current and re-read both. Submitting a PR moves the card to `In Review` and records the PR link in its card and Issue. If blocked, move to `Blocked`, document exact reason, existing branch/state and unblock condition; keep the card, branch and Issue. GitHub/Todoist mismatch is a blocker, not an excuse to report completion.
- **Done gate:** only after all necessary checkboxes and tests pass, changes are reviewed and PR merged, no blocking dependency remains, and both systems agree: update GitHub evidence, move Todoist card to `Done`, re-read to verify it remains **uncompleted and visible**, then close the accepted Issue. Partial work, an auto-merged PR, or source-only tests do not prove real-device/staging/production acceptance. Pure research tasks may have no PR if verifiable evidence is recorded in the Issue. Cancel/duplicate Issues with a documented reason; do not mark unaccepted work Done.
- **One-time migration exception:** Issue [#299](https://github.com/natefox2017/cook/issues/299) governs replacing the formerly inaccessible board workflow. This exception applies only to bootstrapping task-management rules; it never authorizes ordinary feature work without Todoist Ready → In Progress claim verification. After migration use the normal claim procedure for every independent task.

## Documentation vs. Issues (mandatory)

- **Durable product specifications belong in documentation; actionable requirements belong in Issues.** `docs/` is for approved product rules, user flows, design systems, and stable behavioral/API/data contracts. Every newly approved requirement also needs an Issue with a Todo checklist and an associated Todoist card, which are the execution source of truth. Do not use documents as a development diary, bug tracker, changelog, progress report, test log, or PR summary.
- **All task details and execution evidence belong in GitHub Issues.** Track requirements, bugs, regressions, UX fixes, performance, security, refactors, tests, QA, integrations, deployment, and operational work using explicit Todo checkboxes. Search for an existing matching Issue first; update it instead of creating duplicates. Create a focused Issue only if no suitable one exists, then add its unique Todoist card to `Backlog`, and promote to `Ready` only when all Issue details and prerequisites are verified.
- **Write execution evidence to the Issue, not a new Markdown file.** Record the cause, affected code, fix/PR/commit references, exact tests run and their results (or `NOT RUN`), outstanding risks, and verification/deployment status in the Issue body or comments. Only mark work complete when its stated acceptance criteria are actually met.
- **Documentation updates are exceptional, not routine.** Change a requirements document only when the user approves a new or changed requirement, design rule, or long-lived contract, or explicitly requests that document edit. Link the corresponding Issue. A routine code or UI fix, PR review, test run, or bug resolution does **not** require any `docs/` or README update.
- **Keep PRs and Issues aligned.** Every non-requirement code change references its Issue. Use `Refs #...` for partial implementation and `Closes #...` only when the Issue's full accepted scope is satisfied. A merged PR alone is not proof of signed-device, staging, or production acceptance.
- **Leave legacy reports alone.** Do not create more dated `*_QA_*.md`, `*_validation.md`, `*_fix.md`, status snapshots, or handoff notes merely to record a change. If an old document is misleading, clarify it in its linked Issue unless an approved requirement truly changes.

Read the relevant documents before substantial product or architecture changes:

- `docs/PRODUCT_BASELINE_V1.md` — product scope and priorities
- `docs/USER_FLOWS.md` — user journeys
- `docs/DESIGN_SYSTEM.md` — visual direction and UI conventions
- `docs/ARCHITECTURE.md` — system boundaries
- `docs/RECIPE_IMPORT_PIPELINE.md` — import lifecycle
- `docs/DATA_MODEL.md` — data model
- `docs/DEVELOPMENT_STANDARD.md` — collaboration and delivery conventions

`docs/UI_DESIGN_APPROVALS.md` records UI directions and decisions. It is not a separate development gate when the user has directly requested implementation. Follow the user's current explicit instructions when they supersede older documentation.

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
- **Create a regular (non-Draft) PR only for a Todoist-claimed Issue after its implementation Todo is complete.** Include Issue number, Todoist task/Board URLs, claim information, completed Todo IDs and exact evidence. Our trusted GitHub Actions workflow merges ordinary clean same-repo PRs automatically; merging is not end-to-end acceptance and cannot replace Kanban updates.
- Draft PRs are only for genuine work in progress. If a completed PR was already opened as Draft, append the exact completion marker `<!-- auto-ready: complete -->` to its PR body, or apply the `auto-ready` label; the workflow promotes it and merges it without a manual UI click. Do not set either marker before work is complete.
- Do not overwrite an approved design with copy/layout taken from stale history. The first onboarding story remains **OnboardingAI / Create with AI** and Premium retains the AI feature row unless the user expressly approves a change. The merge workflow blocks those regressions and obsolete user-facing RecipePouch naming.

- GitHub Issues are the task, Todo checklist and delivery record for **all requirements and changes**. Before coding, locate or create the Issue, verify its unique Todoist card and successfully claim it from `Ready`. Update each Todo checkbox/test evidence and the Todoist Section after every step. No verified Todoist claim means no implementation. Do not generate a documentation-update task for every PR.
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
