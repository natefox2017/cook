# Recipe V1 Documentation

## Scope

Recipe V1 core code currently develops:

- iOS App (SwiftUI)
- iOS Share Extension
- Supabase Backend

Explicitly approved **next-phase additions (not shipped)**:
- Public read-only **shared recipe** web pages for specific owner-published recipes only; not a general Web app or a public community.
- AI-assisted recipe import/edit enhancements, better Recipe Detail, share posters/QR, invitation attribution; referral rewards deferred.

Not in V1:

- Android

- General purpose Web recipe library client (the approved sharing landing is an exception)
- Mac
- Community feed
- Posts/comments/followers

## Task and verification authority

- The only live task, Todo, owner, issue state and test evidence source is [Recipe Pals Development in Linear DEV](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a). GitHub Issues, old Todoist and dated Markdown audits are historical references only.
- Signed-iPhone, Auth, StoreKit, Supabase, privacy and release results belong in [DEV-49](https://linear.app/gengyun/issue/DEV-49); protected AI/import/share deployment and staging verification belong in [DEV-50](https://linear.app/gengyun/issue/DEV-50). PR merge is not acceptance.
- A local documentation-link check is available from the repository root via `python3 scripts/check_documentation_links.py`; it does not verify external URLs, production services or rendered UI.

## New product planning (2026-10-09)

- [AI import/chat/media/multiple recipe/edit scope](PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md)
- [Private-by-default recipe share → image/QR → public Web → invite measurement](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)
- [Current Recipe Detail field and UI competitive gap](PRODUCT/RECIPE_DETAIL_COMPETITOR_AUDIT_2026-10-09.md)
- [Durable product roadmap and capability dependencies](ROADMAP.md) — use the Linear DEV Board for current assignments

## Reading order

1. [Product baseline](PRODUCT_BASELINE_V1.md)
2. [Current feature coverage](PRODUCT_COMPLETENESS_V1.md)
3. [Architecture](ARCHITECTURE.md)
4. [Recipe import pipeline](RECIPE_IMPORT_PIPELINE.md)
5. [Design system](DESIGN_SYSTEM.md)
6. [Development standard](DEVELOPMENT_STANDARD.md)
7. [Agent workflow](DEVELOPMENT/agent-workflow.md)
