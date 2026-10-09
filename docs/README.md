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

## Current development and verification

- [Remaining development vs test backlog](DEVELOPMENT/REMAINING_DEV_AND_TEST_2026-10-09.md) — authoritative split of open code work, automated tests, local Mac checks, and Apple/Supabase integration acceptance.
- [Release testing contract](TESTING_RELEASE.md) — required evidence and release gates.

## New product planning (2026-10-09)

- [AI import/chat/media/multiple recipe/edit scope](PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md)
- [Private-by-default recipe share → image/QR → public Web → invite measurement](PRODUCT/RECIPE_PUBLIC_SHARING_V1.md)
- [Current Recipe Detail field and UI competitive gap](PRODUCT/RECIPE_DETAIL_COMPETITOR_AUDIT_2026-10-09.md)
- [Prioritized independent GitHub Issues and dependencies](ROADMAP.md)

## Reading order

1. [Product baseline](PRODUCT_BASELINE_V1.md)
2. [Current feature coverage](PRODUCT_COMPLETENESS_V1.md)
3. [Architecture](ARCHITECTURE.md)
4. [Recipe import pipeline](RECIPE_IMPORT_PIPELINE.md)
5. [Design system](DESIGN_SYSTEM.md)
6. [Development standard](DEVELOPMENT_STANDARD.md)
7. [Agent workflow](DEVELOPMENT/agent-workflow.md)
