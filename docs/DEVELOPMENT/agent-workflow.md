# Agent Workflow — evidence-driven parallel delivery

> This is a collaboration guide, **not a fixed internal recipe for how to plan features**. The current source of truth is `AGENTS.md`, current `main`, live GitHub Issues and [ROADMAP.md](../ROADMAP.md).

## Before splitting work

1. Start with the user's current product requirement, existing main source and [current Issue snapshot](CURRENT_BACKLOG_2026-10-09.md). Distinguish feature requested from already implemented and deployed.
2. Research **already shipped, sustained-use or commercially successful comparable products** and supported open-source alternatives. Record *which repeated behaviors* matter, official links, licenses and compatibility; do not recreate infrastructure that exists in RecipeCore, SwiftUI, Apple frameworks or Supabase.
3. Freeze shared import/job, Recipe model, public snapshot, RLS/API and source-evidence contracts before parallel implementation. Explicitly identify files the same time two agents may write.
4. A small independent Issue names goal, input/output, touched-file boundaries, dependencies, UI design status (`APPROVED / SCOPED / PENDING`), deterministic acceptance and what requires a real device or staging. Link actual evidence, not an old unchecked box.

## Parallelism rule

Independent data/UI tests can run in parallel **only if their changes don't conflict**. Example: #238 owns new evidence/AI draft contract, #239/240 consume it; #247 owns nullable Recipe fields, #248 consumes them; #242 public permission must precede #243 Web and #244 poster. Avoid several agents simultaneously rewriting `CookingView.swift` or `Models.swift` before contracts agree.

Keep every task in its own branch/PR with source test evidence and honest `NOT RUN / BLOCKED` when runtime is unavailable. The private GitHub Free auto-merge source check is not Apple signing, Supabase deployment, real provider access or user acceptance. See controlled staging #250 and selected-release #251. Production credentials, destructive migration, Apple plan changes or publishing personal content need separate explicit authorization.
