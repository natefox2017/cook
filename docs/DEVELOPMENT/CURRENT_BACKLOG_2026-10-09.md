# Recipe Pals — Current Open-Issue Snapshot (2026-10-09)

> **A dated inventory, not a live API.** Baseline source `main@1b7fc8b43f50edb3b20ad8067437e8ed8bfa1629`, taken after PR #249 and before documentation reconciliation. At inventory time: **24 open ordinary Issues** (22 existing + #250/#251), 52 closed Issues, 175 closed PRs and no open PRs. Always check [live Issues](https://github.com/natefox2017/cook/issues?q=is%3Aissue+is%3Aopen) and latest main before taking work.

## What is and is not delivered

`OPEN` = proposed DEV work or unfinished verification. `CLOSED` does not mean release PASS. An iOS screen, source file, test fixture, auto-merged PR or vendor configuration record cannot prove signed-device/hosted production acceptance. Old #139 and #126–#129/#134 are **closed archival records**, despite pending checkboxes/historical "remain OPEN" text. Closed `not_planned` import #116–#120/#130/#135/#138/#141/#164 stay closed; the newer user-authorized AI scope gets a **fresh staging gate #250**.

## Current live-owner groupings (all OPEN at the snapshot)

| Area | Open Issues | Required next action, not assumed done |
| --- | --- | --- |
| i18n P0 | [#230](https://github.com/natefox2017/cook/issues/230) | Full locales **plus manual language and country choice**. Test-stage English remains current; don't call existing 4 catalogs worldwide coverage. |
| Cooking & detail micro-UX | [#231 timer audio](https://github.com/natefox2017/cook/issues/231), [#232 opt-in voice](https://github.com/natefox2017/cook/issues/232), [#233 parameter popovers](https://github.com/natefox2017/cook/issues/233) | Use existing timers/step models. Voice foreground-only; timer notifications respect iOS; no fabricated conversions. |
| AI import / edit | [#238 evidence & dialogue](https://github.com/natefox2017/cook/issues/238), [#239 lawful AV](https://github.com/natefox2017/cook/issues/239), [#240 multiple dishes](https://github.com/natefox2017/cook/issues/240), [#241 substitution diff](https://github.com/natefox2017/cook/issues/241) | #238 evidence/proposal contract before media/multidish integration. #241 safe preview, not overwrite. No authorized provider means NOT LIVE. |
| Opt-in recipe sharing | [#242 consented snapshots](https://github.com/natefox2017/cook/issues/242), [#243 public Web](https://github.com/natefox2017/cook/issues/243), [#244 poster & QR](https://github.com/natefox2017/cook/issues/244) | **#242 → #243 → #244** for a real revocable HTTPS URL. Link is primary on same device; no public feed or unlicensed media. |
| Growth | [#245 explicit inviter attribution](https://github.com/natefox2017/cook/issues/245), [#246 rewards](https://github.com/natefox2017/cook/issues/246) | Events can aggregate visits/clicks, but cannot identify App Store downloaders. #246 P2 waits for consent, fraud and budget approval. |
| Rich recipe fields & page | [#247 metadata compatibility](https://github.com/natefox2017/cook/issues/247), [#248 detail hierarchy](https://github.com/natefox2017/cook/issues/248) | **#247 → #248**; reuse #233. New nullable data must round-trip old snapshots; don't expose private notes. |
| Auth / payments / sync QA | [#131 Auth](https://github.com/natefox2017/cook/issues/131), [#132 StoreKit](https://github.com/natefox2017/cook/issues/132), [#133 Sync](https://github.com/natefox2017/cook/issues/133) | Real controlled identity, signed current build and Apple Sandbox; previous mocked/Xcode StoreKit fixtures do not replace service E2E. |
| Cooking / performance / runner QA | [#136 Cooking](https://github.com/natefox2017/cook/issues/136), [#137 Instruments](https://github.com/natefox2017/cook/issues/137), [#189 UI Runner](https://github.com/natefox2017/cook/issues/189) | Preserve earlier per-commit actual PASS; collect only missing changed-build tests. Runner Code 74 isn't a Cooking application test failure. |
| Admin/backend source | [#155](https://github.com/natefox2017/cook/issues/155) | Staging/prod provenance, hosted RBAC/webhook authorization and rollout records; different from public recipe import/share new scope. |
| New infra and release | [#250 controlled staging](https://github.com/natefox2017/cook/issues/250), [#251 release gate](https://github.com/natefox2017/cook/issues/251) | #250 closes only with authorized staging evidence. #251 selects launch scope, verifies signed build and release criteria; no production mutation without owner approval. |

## Dependency execution map

`#238 contract` → `#239/#240`; `#238` and current RecipeCore → `#241`. `#247 optional model` → `#248 page`, which wires #233/#241/#242 when actually implemented. `#242 public permissioned snapshot` → `#243 accessible read-only Web` → `#244 QR/long poster` → `#245 opt-in growth metrics` → `#246 rewards only after another decision`. Core real-device QA #131/#132/#133 and protected staging #250 remain separate from tests of backend code. Each feature added to launch scope is also accepted under #251.

## Prevent duplicate or ungrounded work

1. Re-read the selected open Issue, its latest comments, existing PRs/claiming threads and current `main` before editing; avoid clobbering another branch. If the implementation exists, test it rather than rewrite it.
2. Use the repository's [design approvals](../UI_DESIGN_APPROVALS.md) and feature plan; approved `Create with AI` onboarding is not proof the generator exists.
3. Preserve technical persistence IDs, original source evidence, private default, old recipes, local settings, user-confirmed edits and RevenueCat/StoreKit identity boundaries. Never claim external/private videos can be universally decoded.
4. Deliver each small Issue by PR. Record `CODE MERGED / STATIC CHECK / CORE TEST / SIGNED DEVICE / STAGING / PROD` separately; the single lightweight PR auto-merge guard is **not** Xcode/StoreKit/DB testing.
