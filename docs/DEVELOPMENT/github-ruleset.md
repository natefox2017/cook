# GitHub PR auto-merge policy (private GitHub Free)

Current source of truth: `.github/workflows/ios-ci.yml` and `AGENTS.md`. This replaces the older paid-plan ruleset / required `docs` + `Validate iOS project` status-check instructions.

- **Completed work:** create a **normal PR**, not a Draft. Same-repository, non-conflicting, open PRs with no changes-requested/review-required decision and no unresolved threads are handled by the `PR Auto Merge` GitHub Action. The bot uses immediate squash merge; GitHub's native `Enable auto-merge` button is not involved.
- **Drafts are work in progress:** the workflow intentionally does not merge them. When the implementing agent finishes a Draft, it can opt in using the `auto-ready` label or a completed-work PR-body marker defined in `AGENTS.md`; the bot promotes the PR to Ready automatically. Do not opt in unfinished work.
- **Missed mergeability:** GitHub may report `UNKNOWN` just after PR creation or draft promotion; the workflow retries for up to one minute. New commits, edit/label and review-submission events retrigger the attempt. A conflicting PR or outstanding review remains blocked.
- **Fast source regression guard:** the trusted workflow reads approved onboarding + paywall, both localized bundle names and changed-file patches **as data** from the PR head; it never checks out or executes PR code with its write-enabled token. The guard refuses previously reverted AI-first wording and newly added obsolete user-facing RecipePouch copy. Legitimate user-approved changes require updating the guard in a separate reviewed PR first.
- **No fake CI:** the workflow does **not** run Xcode, device, StoreKit, SwiftPM, Deno, or hosted Supabase tests. Required `docs` / `Validate iOS project` checks from the old public/paid configuration are not part of this private free-repo policy. A green auto-merge run only demonstrates metadata and source-invariant validation.
- Use the PR's **Events** history (`ready_for_review`, `merged`) and the corresponding Actions log to distinguish a manual **Ready for review** click from an actual manual **Merge**. Verify `merged_by=github-actions[bot]` and source SHA before reporting success.
- Keep unrelated production deploys, secret changes, SQL migrations, unsigned app installs, and destructive operations outside this workflow. Never silently remove `cook.*`/old receipt IDs that are needed for compatibility.

The repository's availability of branch-protection/ruleset features depends on GitHub plan/permissions and should not be assumed from historical documentation.
