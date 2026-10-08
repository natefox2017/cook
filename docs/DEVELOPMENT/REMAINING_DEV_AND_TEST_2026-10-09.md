# RecipePouch — Remaining Development and Test Backlog

Updated: 2026-10-09. Initial audit baseline: `main@51aa4da`. Latest verified code merges include #114, #115 and #125; always refresh `main` before starting any Issue.

## Why these tasks and this order

Use the patterns repeated in **established shipped products**, rather than treating older internal issue sequences as development truth:

- [Paprika iOS](https://www.paprikaapp.com/help/iphone/), [ReciMe](https://recime.app/help/en/articles/11594896-qu-est-ce-que-recime), and open-source [Mealie](https://github.com/mealie-recipes/mealie) consistently place private recipe saving/import, reliable manual editing, cooking, grocery lists, meal planning, and account sync in the normal workflow. RecipePouch already implements most local surfaces: do **not** restart them.
- Open-source [recipe-scrapers](https://github.com/recipe-scrapers/recipe-scrapers) separates safely acquiring HTML from parsing supplied HTML, uses Schema.org/host-specific extraction, and includes representative per-source fixtures. Reuse the existing safe URL fetcher + field evidence/fixture testing; do not build a new scraper platform just for its own sake.
- Consequently: **fix correctness/build/ownership first → complete bounded file and source extraction + honest needs_review → run cheap deterministic tests → deploy safely to staging → use iPhone/developer-account acceptance LAST**.
- Do not expand into a public feed, creator social network, nutrition/paywall feature creep, or unauthorized scraping/login-wall bypass.

## Development Issues — code/operations only

| Priority | Issue | Exact scope | State / dependency |
| --- | --- | --- | --- |
| P0 | [#112](https://github.com/natefox2017/cook/issues/112) | Add existing artifact service to Xcode main target | **CODE MERGED** in [#114](https://github.com/natefox2017/cook/pull/114); **build untested**, #126 |
| P1 | [#113](https://github.com/natefox2017/cook/issues/113) | Validate all local/external OpenAPI refs | **CODE MERGED** in [#115](https://github.com/natefox2017/cook/pull/115); Python execution #134 |
| P1 | [#116](https://github.com/natefox2017/cook/issues/116) | Private plain-text and selectable-text PDF attachment parsing | OPEN; fixtures first, depends on deployed API #141 for integration |
| P1 | [#117](https://github.com/natefox2017/cook/issues/117) | Image/scanned-PDF OCR evidence, provider abstraction | OPEN; controlled artifacts, no secrets in client |
| P1 | [#118](https://github.com/natefox2017/cook/issues/118) | Public social caption → permitted ASR/visual fallback | OPEN; build only safe public/legal paths and truthful needs_review |
| P1 | [#119](https://github.com/natefox2017/cook/issues/119) | Evidence priority and prevent late worker results overwriting user edits | OPEN; preserve old library and idempotent job outcomes |
| P1 | [#120](https://github.com/natefox2017/cook/issues/120) | Artifact delete/retry/expiration behavior | OPEN; production cleanup scheduling part of #141 |
| P2 | [#121](https://github.com/natefox2017/cook/issues/121) | Preserve original shared text whitespace and historical IDs | **CODE MERGED** [#125](https://github.com/natefox2017/cook/pull/125); native checks #126/#130 |
| P1 | [#122](https://github.com/natefox2017/cook/issues/122) | Root floating Tab safe-area obscuring content | OPEN; requires #128 actual screenshot/layout validation |
| P2 | [#123](https://github.com/natefox2017/cook/issues/123) | Persistence/large-library refactor only if profiling proves slowdown | BLOCKED by #137, no speculative rewrite |
| P1 | [#124](https://github.com/natefox2017/cook/issues/124) | Files picker success/cancel/error callback bug, **only after reproduction** | BLOCKED by focused #127 |
| P0 security | [#140](https://github.com/natefox2017/cook/issues/140) | Remove unjustified anonymous/security-definer RPC execute access | OPEN; staging validation and safe production release required |
| P0 operations | [#141](https://github.com/natefox2017/cook/issues/141) | Deploy queue/artifact schema, Edge functions and scheduler in controlled stages | OPEN; latest project does **not** have these deployed |

One Issue = one independently reviewable PR; add regression fixtures to development PRs without changing the release CI policy. Existing product UI and the temporary English-only QA policy remain unchanged.

## Test Issues — no production feature edits

### Can run without Apple developer account (run first when runtime is available)

| Issue | Environment | Coverage |
| --- | --- | --- |
| [#134](https://github.com/natefox2017/cook/issues/134) | Python + Deno + local PostgreSQL | OpenAPI/worker safety/fixtures/RLS (deterministic tests). Python/Deno full commands not executed by current chat runtime. |
| [#135](https://github.com/natefox2017/cook/issues/135) | Controlled Supabase staging + server credentials | Deployment/RLS/Queue/Storage/Edge/owner isolation; **not yet run end to end**. |
| [#138](https://github.com/natefox2017/cook/issues/138) | Safe public sources + controlled backend | Real platform caption/VTT/fallback/needs_review; blocked where Dev #116–#119 incomplete. |

### Leave Mac / iOS native execution until code-only work is ready

| Issue | Scope |
| --- | --- |
| [#126](https://github.com/natefox2017/cook/issues/126) | Full RecipeCore SwiftPM tests, Xcode build and current-main simulator tests |
| [#127](https://github.com/natefox2017/cook/issues/127) | JSON/HTML Files picker feedback and both local-delete entrances |
| [#128](https://github.com/natefox2017/cook/issues/128) | Four tabs + all secondary screens, Liquid Glass safe area, accessibility/VoiceOver |
| [#129](https://github.com/natefox2017/cook/issues/129) | Forced English under Chinese/Japanese system, plus explicit locale smoke |
| [#136](https://github.com/natefox2017/cook/issues/136) | Cooking background timers, notifications, interrupted session recovery |
| [#137](https://github.com/natefox2017/cook/issues/137) | Instruments baseline and realistic large-library datasets |

### Leave real Apple/provider/multi-device verification LAST

| Issue | Access needed |
| --- | --- |
| [#130](https://github.com/natefox2017/cook/issues/130) | Signed iPhone / Share Extension / App Group / Safari, Photos, Files host integration |
| [#131](https://github.com/natefox2017/cook/issues/131) | Apple Developer Sign in with Apple + Google/Supabase OAuth + email callback test accounts |
| [#132](https://github.com/natefox2017/cook/issues/132) | App Store Connect subscription product IDs and Sandbox/TestFlight |
| [#133](https://github.com/natefox2017/cook/issues/133) | Two accounts/two devices + signed-in staging backend, offline/revision/conflict/erase |
| [#139](https://github.com/natefox2017/cook/issues/139) | V1 release gate; aggregates all above tests and remains open until actual PASS |

## Live backend read-only findings (2026-10-09)

Supabase `cookapp` project `semsjyrqjnumpvanibip` currently reported `ACTIVE_HEALTHY` with 9 active Edge Functions, **none** named `recipe-imports`, `recipe-import-worker`, `recipe-import-artifacts` or `purge-expired-recipe-import-artifacts`. `public.recipe_import_jobs` and `public.recipe_import_artifacts` are absent. Production history ends at migration `20261008062415` (with earlier duplicate-name snapshot hardening versions), whereas current repo contains later import migrations.

A read-only privilege query reported `anon_execute=true` on 5 public `SECURITY DEFINER` functions (`admin_bootstrap_owner`, `admin_change_password`, `admin_verify_credentials`, `capture_registration_meta`, `get_runtime_config_number`). This is an **authorization finding, not proof of exploitation**. Track in #140 and verify all callers and intended grants before deployment. Relevant Supabase [security advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable).

The current Supabase connection shows no development branches; creating a paid staging project/branch requires the owner's explicit approval. Do not apply untested SQL, grant changes or queue migrations to production to make the backlog appear finished.

## Historical QA and superseded branches

- [#92](https://github.com/natefox2017/cook/issues/92) retains the detailed historical failure context. Its former instruction “do not start QA work” is superseded by the user's 2026-10-09 request; every actionable failure is carried into the dedicated TEST tickets above. Close #92 as *superseded/migrated* after links are posted.
- [Draft PR #98](https://github.com/natefox2017/cook/pull/98) was closed without merging because its large outdated changes would switch the app back to Simplified Chinese and overwrite newer Auth UI. Three useful independent fixes have instead merged via #114/#115/#125. This is not a failed release test.
- [PRs #100–#111](https://github.com/natefox2017/cook/pulls?q=is%3Apr+is%3Amerged) implemented localization, English QA policy, login improvements, optimization and source-contract fixes. Their source changes are not proof of native Xcode or production backend execution.

## Rules for evidence and closure

Write `PASS / FAIL / BLOCKED` for each acceptance case; include tested commit SHA, platform, dependency versions, anonymized fixtures, commands, actual result, and screenshot/log paths. A green `Validate iOS project` status is a compatibility auto-merge gate, **not** an iOS build or unit test. Keep unresolved TEST Issues open even when their corresponding DEV code merges. When the owner finishes the final Mac/Apple-account test batch, explicitly review every blocker and only then close #139 or schedule release.

No new public-user data, account credentials, provider secrets, unapproved UI rewrites or production environment changes are authorized by this roadmap alone.
