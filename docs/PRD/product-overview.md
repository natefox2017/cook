# Recipe Pals — V1 Product Overview (historical goal + current boundary)

## Positioning

Recipe converts recipes found on social platforms into structured personal recipes.

**Target experience (not all capabilities released):**

Share supported public source / user-authorized link
→ Recipe Pals Share Extension's durable local receipt
→ owner-scoped main App import job + server evidence (deployment must be verified)
→ only when available, AI evidence-grounded draft or user questions
→ private Recipe library → Cooking / Groceries.

This is a **product target**. The current repository has local import, app Share receipts and backend worker source, but does not prove universal social-video decoding or deployed multi-turn AI. Login/paywall/DRM-limited sources remain inaccessible; keep a safe fallback.

## V1 User Goal

Save a recipe with almost the same effort as saving a video.

Normal flow:
1. Tap Share
2. Choose Recipe Pals
3. Return to original app

Long parsing belongs in the owner-authorized server job, **not in the Share Extension**. Source complete → automatic private save; important missing fields → optional review, once #238 is implemented and validated.

## Main Features

P0:
- Share Extension import
- Recipe extraction
- Personal recipe library
- Recipe detail
- Cooking mode
- Grocery list
- Search
- Collections

P1:
- Meal planning
- OCR/photo import
- PDF import

## Excluded

No community system in V1.

## Approved extension (2026-10-09) — PLANNED, NOT SHIPPED

- Evidence-grounded AI conversation and substitutions [#238–#241](https://github.com/natefox2017/cook/issues/238), supported public media only when legally obtainable.
- Optional per-recipe private-by-default publish → anonymous read-only Web page → attractive poster/QR [#242–#244](https://github.com/natefox2017/cook/issues/242); **not** a public social feed or full Web client.
- Privacy-safe invitation measurement [#245](https://github.com/natefox2017/cook/issues/245), optional future reward program [#246](https://github.com/natefox2017/cook/issues/246) only after separate approval, and improved private Recipe Detail [#247/#248](https://github.com/natefox2017/cook/issues/247).
- Verify new staging/environment separately via [#250](https://github.com/natefox2017/cook/issues/250) and selected release via [#251](https://github.com/natefox2017/cook/issues/251). No automatic public exposure of imported recipe media or private notes.
