# Recipe Design System V1

## Platform

iOS only.

## Visual direction

Apple Liquid Glass inspired navigation + premium European recipe app.

## Typography

Brand direction:
A restrained Lora editorial type system matched to the current Recipe Pals UI.

Implementation font:
Lora (SIL Open Font License), registered as `Lora-Regular`.

Fallback:
SF Pro / system font.

Rules:
- Large and inline native navigation titles: 34 / 17 pt
- Hero / page / section / card headings: 34 / 28 / 22 / 20 pt
- Body / secondary / footnote: 17 / 15 / 13 pt
- System navigation bar and safe-area title placement
- High-contrast primary text and system secondary metadata

This document reflects the current implementation. See
`../DESIGN_SYSTEM.md` for shared spacing, palette, and copy rules.

## UI Rules

- Food photography is the main visual element.
- Glass material is used for navigation and controls, not every card.
- Avoid dense dashboards.
- Avoid excessive icons.
- One primary action per screen.

## Navigation

Floating Liquid Glass Tab Bar.

> **New-scope note (2026-10-09):** optional detail enhancements #247/#248, AI editing #241, per-recipe opt-in share #242–#244 and cooking sound/voice #231/#232 are planned, not already rendered/approved just because the existing Lora/UI theme is recorded here. New UI should extend [DESIGN_SYSTEM.md](../DESIGN_SYSTEM.md); no default public feed or excessive Liquid Glass.
