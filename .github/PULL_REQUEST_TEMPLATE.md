## Linear Issue (single authoritative task)

- Linear issue: [GEN-___](https://linear.app/gengyun/issue/GEN-___)
- Cook Board: https://linear.app/gengyun/project/cook-recipe-pals-development-8c015c72cb6a
- Issue assignee / claim session and UTC timestamp:
- Claim check: verified **Ready → In Progress**, assignee + status re-read; if bootstrap migration, name its explicit issue:
- Linked prior changes or dependencies (Linear issue identifiers):
- Completed acceptance Todo IDs / evidence in Linear:
- Remaining Todo IDs / NOT RUN (write None if fully accepted):

> New tasks, bugs, testing, acceptance and Todo checkboxes belong only in **Linear Issues**, not GitHub Issues, Todoist or Markdown. Prefix a focused branch such as `gen-40-...`, include `GEN-40` in PR title/description to link GitHub ↔ Linear. Do not use `Closes #123` on historical GitHub issues. A merged PR alone is not Linear Done.

## Change scope

- Current implementation / problem:
- What changed; expected behavior and edge/error paths:
- Concrete touched file paths / API / schema:
- Preserved product design, compatibility and prohibited changes:
- Reused code/open-source solution and license (N/A for simple fix):

## Tests and acceptance evidence

- Exact commands, environment and PASS/FAIL:
- Expected output and observed result:
- Device/StoreKit/staging/production evidence, or **NOT RUN** with reason:
- UI change screenshots/recording/design state, or N/A:
- Known blockers, regression coverage and follow-up:

## Security / PR review

- [ ] No secrets, user data, unauthorized destructive migration/production writes or unsupported billing/security change
- [ ] No unrelated rewrite, stale-branch regression or discarded failing tests
- [ ] Relevant Linear acceptance Todos and actual test results updated
- [ ] Linear status set to **In Review** after opening PR and re-read, OR an explicit conflict/blocker recorded

## Completion contract

After PR merge, leave Linear **In Review** while necessary tests, approvals, acceptance checkboxes, dependencies or production gates are outstanding. Only accepted work becomes **Done** in Linear, after re-reading owner/status and recording the linked merge commit. A canceled or closed-unmerged PR is reviewed manually. Linear Ready/Blocked statuses must be configured before normal task claiming; do not silently replace with `Todo`.

## Existing Cook release and CI contract

- Main receives branch PRs only. Existing trusted lightweight same-repo auto-merge remains unchanged; normal clean PRs may merge without adding heavy per-PR Xcode CI. The merge bot is not a test certificate.
- For actual in-progress work use Draft; mark completed Draft PRs with the exact repository convention only after work is ready. Verify before merge that accepted onboarding, branding, UI and StoreKit contracts are not overwritten by old code.
- Only change durable Markdown product/technical documents when the underlying requirements or contracts change. Ordinary Bug fixes/PRs do not require document updates.
