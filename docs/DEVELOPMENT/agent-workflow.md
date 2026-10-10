# Agent Workflow — evidence-driven parallel delivery

> This is a durable collaboration guide, not a task status report. Repo-root `AGENTS.md` defines the live workflow. [Cook Linear Issues and Board](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a) are the only requirements, Todo, claiming, owners and status source; GitHub is code/PR/CI only; Markdown is architecture and product design, not backlog.

## Before splitting work

1. Start with the current Cook Linear Issue/Board state, assignee, blocked dependencies, latest GitHub default-branch source, active/recent PRs and committed behavior. Never use old GitHub Issue snapshots or Todoist as the active task queue.
2. Research **already shipped, sustained-use or commercially successful comparable products** and supported open-source alternatives. Record *which repeated behaviors* matter, official links, licenses and compatibility; do not recreate infrastructure that exists in RecipeCore, SwiftUI, Apple frameworks or Supabase.
3. Freeze shared import/job, Recipe model, public snapshot, RLS/API and source-evidence contracts before parallel implementation. Explicitly identify files the same time two agents may write.
4. Every independent Linear Issue must pass the full zero-context ten-part contract in `AGENTS.md`: background; objective; existing code; accurate file/API/data scope; input/output/edge/error behaviors; security/compat/reuse constraints; linked dependencies; verifiable Todo checkboxes; test commands/expected/actual results; branch/PR/acceptance evidence. Include UI state (`APPROVED / SCOPED / PENDING`) when applicable; mark unknown values TO VERIFY.

## Assignment and delivery sequence

Do not start feature work without a verified Linear claim. Only an eligible, unassigned `Todo` issue in the Cook project is claimable. Re-read Board and issue, latest main/PRs/dependencies; verify scope and no competing changes; assign yourself and set `In Progress`, then immediately re-read both owner and status. Linear mutations are not an atomic lock; stop on conflicts. The DEV team intentionally retains native statuses without introducing Ready or Blocked; keep unreviewed imported work in Backlog.

PR branch/title/body references the Linear identifier (`DEV-<number>`). The current GitHub automation settings move ordinary PR creation/review to `In Review` and take No action on PR merge; confirm real transition, or manually update/re-read if it did not occur. PR auto-merge does not establish acceptance. Move to `Done` only when merge, tests, checked Todos and dependencies are verified. For blocked tasks, comment with cause, owner, dependency and recovery steps; keep unfinished work open. Never create new GitHub Issues or Todoist tasks.

## Parallelism rule

Independent data/UI tests can run in parallel **only if their changes don't conflict**. For current canonical planning, `DEV-79` owns AI evidence/draft scope and `DEV-78`/`DEV-77` consume it; `DEV-52` owns recipe metadata and `DEV-51` consumes it; `DEV-73` public permissions precede `DEV-71` Web and `DEV-68` poster. Verify actual dependencies on the live Board before work. Avoid simultaneous edits to `CookingView.swift` or `Models.swift` without frozen contracts.

Keep every task in its own branch/PR with source test evidence and honest `NOT RUN / BLOCKED` when runtime is unavailable. The private GitHub Free auto-merge source check is not Apple signing, Supabase deployment, real provider access or user acceptance. See canonical Linear staging `DEV-50` and release acceptance `DEV-49`. Production credentials, destructive migration, Apple plan changes or publishing personal content need separate explicit authorization.
