# Agent Workflow — evidence-driven parallel delivery

> This is the durable collaboration guide; see repository-root `AGENTS.md` for the authoritative task protocol. **GitHub Issues** own full requirements/Todo/acceptance, the [Cook Todoist Board](https://app.todoist.com/app/project/6hj76CCMgwhrRp6m) owns live claiming/status, GitHub PRs own delivery, and `docs/` only holds long-lived specifications. `ROADMAP.md` is product direction, never the current backlog.

## Before splitting work

1. Start with the user's current product requirement, live Todoist card, latest default-branch source, active/recent Issues and PRs. Distinguish feature requested from existing code, completed acceptance and deployed behavior. Never use dated Markdown snapshots as the active task queue.
2. Research **already shipped, sustained-use or commercially successful comparable products** and supported open-source alternatives. Record *which repeated behaviors* matter, official links, licenses and compatibility; do not recreate infrastructure that exists in RecipeCore, SwiftUI, Apple frameworks or Supabase.
3. Freeze shared import/job, Recipe model, public snapshot, RLS/API and source-evidence contracts before parallel implementation. Explicitly identify files the same time two agents may write.
4. A small independent Issue must pass the ten-part zero-context contract in `AGENTS.md`: background, goal, current code, real touched-file/API/data scope, concrete input/output/edge/error behavior, technical constraints, dependency links, verifiable Todo checkboxes, test commands/expected results, PR/evidence/Todoist delivery. Include UI design state (`APPROVED / SCOPED / PENDING`) where relevant. A context-free AI must be able to implement/test/verify it using GitHub alone.

## Assignment and delivery sequence

Do not start feature work without a successful Todoist claim. One independent Issue equals one Board card (full requirement details remain in GitHub) and normally one PR. Only `Ready` is claimable. Read current main/issues/PRs/dependencies, verify the Todoist card is still Ready, move to `In Progress`, immediately re-read to confirm and check for competing claims, and log the claim/UTC/branch in the GitHub Issue. Todoist native assignee is optional; its Section move is not an atomic lock. On conflict stop and coordinate, do not overwrite other agents.

Move a card to `In Review` when its PR is submitted and linked in both systems. After each independently verifiable Todo, check the box in GitHub and log commit/test evidence. Move to `Blocked` with a recovery condition if necessary. `Done` is allowed only after required tests pass, the PR has merged, and all Issue Todo items are accepted: **move the Todoist card into the Done Section without completing the task**, re-read the card, then close the Issue. Parent Issues wait for required children. Keep statuses `Backlog`, `Ready`, `In Progress`, `In Review`, `Blocked`, `Done` exactly; do not introduce a competing Markdown progress tracker.

## Parallelism rule

Independent data/UI tests can run in parallel **only if their changes don't conflict**. Example: #238 owns new evidence/AI draft contract, #239/240 consume it; #247 owns nullable Recipe fields, #248 consumes them; #242 public permission must precede #243 Web and #244 poster. Avoid several agents simultaneously rewriting `CookingView.swift` or `Models.swift` before contracts agree.

Keep every task in its own branch/PR with source test evidence and honest `NOT RUN / BLOCKED` when runtime is unavailable. The private GitHub Free auto-merge source check is not Apple signing, Supabase deployment, real provider access or user acceptance. See controlled staging #250 and selected-release #251. Production credentials, destructive migration, Apple plan changes or publishing personal content need separate explicit authorization.
