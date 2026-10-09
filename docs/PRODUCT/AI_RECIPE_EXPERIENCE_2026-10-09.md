# AI Recipe Import, Media Evidence and Editing — Next-phase Plan

**Status: PLANNED / NOT IMPLEMENTED.** Revised 2026-10-09 from user-requested features, deployed competitors, and live `main` readback. This document is not a claim of live third-party video support or a replacement for `RECIPE_IMPORT_PIPELINE.md`.

## Research: what actually recurs in deployed products

| Product | Observed operating practice | Useful decision |
| --- | --- | --- |
| ReciMe | iOS Share extension imports public web/social recipes with ingredients and steps; public pages only, login/paywall content inaccessible | Preserve 1-tap share ACK and asynchronous source handling; never block the source app waiting for a model. [Official 2026 guide](https://www.recime.app/help/en/articles/16058609-import-from-your-browser) |
| Honeydew | A saved recipe has AI Edit; user requests vegan/ingredient substitute/serving change, sees a proposal, then saves or discards | Require a preview and explicit acceptance before overwriting anything. [Official AI Edit](https://honeydewcook.com/support/en/using-the-app/ai-edit/) |
| Mealie | Open source recipe management and AI-assisted multi-source recipe imports | Study the flow and contracts; review AGPL-3.0 obligations and do not copy code into closed-source product without compliance. [Repository](https://github.com/mealie-recipes/mealie) |

## Actual code boundaries (audit on 2026-10-09)

- Existing native Share Extension, durable `RecipeShareInboxCoordinator`, `RecipeImportJobService` and `RecipeRemoteImportService` already receive/synchronize job receipts; `AddRecipeView` also handles paste URL, PDF/text/photo.
- Existing `supabase/functions/recipe-import-worker` has structured public HTML/JSON-LD, public page text/caption metadata and owner-checked private artifact work; basic `needs_review`, source evidence and repeat-safe job handling exist in code.
- There is **no universal privileged video downloader**, no guaranteed external ASR/visual provider and no implemented AI multi-turn review/edit session. Source code alone is not proof that the backend is deployed to production.
- Historical third-party import Issues previously closed **not planned** are not silently reopened; the user's present feature request is a new, separately scoped development phase.

## User journey

1. **Receive**: TikTok/Instagram/YouTube/public web/authorized user-uploaded file shared with Recipe Pals. Immediately preserve receipt and return to the originating app.
2. **Evidence capture**: Prefer Recipe JSON-LD / caption / public transcript, then **only authorized** audio/ASR and keyframe OCR/vision. Source support matrix must say 'not available' when content requires login, private access, DRM bypass, or lacks permission.
3. **Draft / review**: When evidence supports every important field, save automatically with provenance. Otherwise ask only the few high-value missing questions (1–3), offer skip and Save Draft.
4. **Faithful vs inspired**: **Faithful** preserves ambiguity and refuses to invent quantities/temperatures/ingredients; **Inspired** may make suggestions, each labeled `AI_suggested`, never impersonating the source.
5. **Multi-recipe**: Only if source contains identifiable distinct dishes, show candidate cards and let the user save selected recipes separately, with stable original-source links.
6. **AI Edit**: 'No butter, replace with olive oil; make for two' returns an editable diff. Before/after and undo/variant preserve the original and any user-confirmed input.
7. **Save**: Existing Recipe/RecipeEditor and private collection remain source of truth; public sharing is **never implied by saving**.

## Implementation issues, dependency order

- **#238 (P0)** [Conversational evidence-grounded drafts](https://github.com/natefox2017/cook/issues/238): one authorized owner-scoped session/field provenance contract and fast-path auto-save.
- **#241 (P0)** [AI substitutions and safe version diff](https://github.com/natefox2017/cook/issues/241): diff/apply or save variant, no destructive async overwrite; coordinate recipe metadata #247.
- **#239 (P1)** [Lawful public audio/subtitle/keyframe evidence](https://github.com/natefox2017/cook/issues/239): provider capability matrix, worker/queue cost and legal boundaries, fake/authorized source tests.
- **#240 (P1)** [Multiple recipes from one source](https://github.com/natefox2017/cook/issues/240): build on stable source/evidence/candidate IDs, preserving single-recipe flow.

**No fake features:** Never silently turn `to taste` into 5g, `until golden` into an exact timer, infer an allergen-free guarantee, conflate source creator with the user's copyright, or claim AI can view private platforms. Track parse success, review-needed %, average dialogue turns, cost/job, validated save rate, retry failures and source capability by platform before expanding paid usage.

**Verification gate:** fixture for public structured recipe, incomplete text, multi-dish, and denied/private video; staging provider responses, owner isolation, source citation, linked final recipe and actual iPhone flow. Each phase may end as PARTIAL if deployment or legal media access has not been established.

## Authorized audiovisual evidence contract (2026-10-10, source-only)

A bounded pure module `authorizedMediaEvidence.ts` now validates **already lawfully acquired** short captions/transcripts/keyframe OCR, permission proof references, source duration, timestamps, excerpt lengths, source kind and provider confidence before attaching immutable evidence. It deduplicates entries and does **not** invent quantities/steps, crawl social pages, download video, call third-party ASR/vision or bypass login/DRM. The upstream trusted worker (not a client) must verify media rights and owner access before calling it; this is **not yet integrated with a configured media source**. The active production project lacks recipe import Edge Functions and enabled AI providers. Full provider API, authorized user-upload media processing, audio/vision output and staging remain #239/#250; no live media capability claimed.
