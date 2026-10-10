# Agent Workflow — evidence-driven parallel delivery

> This is a durable collaboration guide, not a task status report. Repo-root `AGENTS.md` defines the live workflow. [Cook Linear Issues and Board](https://linear.app/gengyun/project/cook-recipe-pals-development-8c015c72cb6a) are the only requirements, Todo, claiming, owners and status source; GitHub is code/PR/CI only; Markdown is architecture and product design, not backlog.

## Before splitting work

1. Start with the current Cook Linear Issue/Board state, assignee, blocked dependencies, latest GitHub default-branch source, active/recent PRs and committed behavior. Never use old GitHub Issue snapshots or Todoist as the active task queue.
2. Research **already shipped, sustained-use or commercially successful comparable products** and supported open-source alternatives. Record *which repeated behaviors* matter, official links, licenses and compatibility; do not recreate infrastructure that exists in RecipeCore, SwiftUI, Apple frameworks or Supabase.
3. Freeze shared import/job, Recipe model, public snapshot, RLS/API and source-evidence contracts before parallel implementation. Explicitly identify files the same time two agents may write.
4. Every independent Linear Issue must pass the full zero-context ten-part contract in `AGENTS.md`: background; objective; existing code; accurate file/API/data scope; input/output/edge/error behaviors; security/compat/reuse constraints; linked dependencies; verifiable Todo checkboxes; test commands/expected/actual results; branch/PR/acceptance evidence. Include UI state (`APPROVED / SCOPED / PENDING`) when applicable; mark unknown values TO VERIFY.

## Assignment and delivery sequence

Do not start feature work without a verified Linear claim. Only `Ready` is claimable. Re-read Board and issue, latest code/PR/dependencies, confirm no assignee or competing changes, assign yourself and set `In Progress`, then immediately re-read both owner and status. Ordinary Linear mutations do not guarantee atomic lock; conflicting claims are blocked and require coordination. GEN team may initially lack Ready and Blocked; if so keep imported work in Backlog pending administrator configuration, never substitute Todo.

PR branch/title/body references the Linear identifier (`GEN-n`). Move the Linear issue to `In Review` on PR creation, record review/test evidence and update each accepted Todo immediately. PR auto-merge does not automatically establish acceptance. Move to `Done` only when PR merge, tests, all checkboxes and dependencies are verified. A blocker includes actual cause and unblock steps; existing branches/PRs remain intact. No GitHub Issue or Todoist task is created for new work.

## Parallelism rule

Independent data/UI tests can run in parallel **only if their changes don't conflict**. Example: #238 owns new evidence/AI draft contract, #239/240 consume it; #247 owns nullable Recipe fields, #248 consumes them; #242 public permission must precede #243 Web and #244 poster. Avoid several agents simultaneously rewriting `CookingView.swift` or `Models.swift` before contracts agree.

Keep every task in its own branch/PR with source test evidence and honest `NOT RUN / BLOCKED` when runtime is unavailable. The private GitHub Free auto-merge source check is not Apple signing, Supabase deployment, real provider access or user acceptance. See controlled staging #250 and selected-release #251. Production credentials, destructive migration, Apple plan changes or publishing personal content need separate explicit authorization.
