# Recipe Detail Gap Audit vs Shipped Recipe Apps

**Audit date: 2026-10-09. Status: CURRENT MODEL OBSERVED / ENHANCEMENTS PROPOSED.** Do not describe proposed fields as released.

## Source-to-product comparison

- [Samsung Food Recipe Page 101](https://support.samsungfood.com/hc/en-us/articles/18588916048276-Recipe-Page-101): prominent recipe photo/title and creator, servings/prep/cook details, ingredient/instruction/health areas, user notes, Save/Plan/share.
- [Samsung Food nutrition methodology](https://support.samsungfood.com/hc/en-us/articles/18725068057620-Nutrition-calculations-Macronutrients-Micronutrients-and-Health-Score): nutrient metrics rely on a database and ingredient normalization; **AI alone is not adequate evidence of grams/calories or allergen safety**.
- [ReciMe features](https://recime.app/help/en/articles/11594896-qu-est-ce-que-recime): recipe import, meal planner, shopping, scaled units, nutrition and step cooking.
- [Paprika iOS](https://paprikaapp.com/help/ios/): ingredients scaling/convert, timers embedded in directions, recipes/photos/notes.
- [Honeydew AI Edit](https://honeydewcook.com/support/en/using-the-app/ai-edit/): plain-language adjustment with preview, save/discard.

## Code audit

Current `ios/RecipeCore/Sources/RecipeCore/Models.swift`:
- Present: Recipe title, summary, 5-value category, servings, prep/cook times, ingredients (quantity/unit/raw amount), steps (instruction, linked IDs, temp/heat raw text, multi-timers), source URL/name/text, image cover, private notes, favorite, created/updated and import record.
- Missing as independent typed Recipe fields: `difficulty`, `cuisine`, meaningful `dietaryTags`, grouped ingredients & preparation markers, `equipment`, `yieldDescription`, own multiple/step images, `tips` and `storageNotes`, provenance-qualified `nutrition` with complete ingredient mapping, explicit publishing visibility/snapshot IDs.
- Current `ios/Recipe/Features/RecipeDetailView.swift`: hero image height ~270, title, aggregate total duration, servings, category, summary; Ingredients Stepper/list; steps with linked ingredients/temp/timer static labels; bottom Start Cooking; then notes and source, favorite and menu (Plan, Collections, Edit, Delete). Existing #233 has **not yet shipped** parameter tap information; AI Edit and Publish/Share entry do not exist.
- Current `RecipeEditorView.swift` edits cover/title/summary/category/servings/prep/cook, ingredients/steps/notes/source. Its values and old JSON need compatibility while new optional fields are introduced.

## Priority table

| Tier | New behavior/field | Data safety, visual behavior, issue |
| --- | --- | --- |
| P0 | Clear prep vs cook time, precise servings and one-line source identity | Use existing values; no invented difficulty or time; improved overview #248 |
| P0 | AI Edit entry with before/after and optional variant | Reuse proposed #241, don't overwrite user revisions |
| P0 | Optional private/public share status and actions | Only after opt-in server #242/web #243/poster #244; UI wiring #248 |
| P0 | Ingredient/time/temperature interactive context | Already tracked in #233, **don't duplicate** popover implementation |
| P0 | Optional difficulty/cuisine and sparse tagged categorization | Typed nullable fields and backward-compatible Core migration #247 |
| P1 | Equipment, tips, storage notes, grouped ingredient/preparation hints | Compact secondary details, empty state hidden; #247/#248 |
| P1 | Multi-photo and step illustration | User-licensed only, compact page gallery; #247/#248 |
| P1 | Verifiable per-serving calories/macros | Only when trusted source+portion basis exists; show 'not available' otherwise; #247 |
| P2 | Personal cooking history, completed count / private rating | Candidate future, **no public social reviews**, requires separate approval |

## Native presentation contract

1. **First screen:** photo (licensed or placeholder) → name + short real description → simple Prep / Cook / Servings / Difficulty (difficulty only when known) → compact source/author attribution → favorite/Share/AI Edit quick actions.
2. **During reading:** Ingredients grouped if actual section info exists, precise scaling and unit conversion; steps readable with linked ingredient highlights and defined timers (reuse #233), start-cooking CTA remains fixed. No new per-step duplicate walls of instructional copy.
3. **Below fold:** private notes and useful equipment/tips/storage/source text, optional verified nutrition disclosure; metadata absent → section hidden, not AI-filled.
4. **Privacy:** save ≠ publish. Imported copyrighted instructions and third-party photos may not be republished by default. Local user notes, Cloud sync, personal data never enter a public snapshot. Don't introduce a feed/followers/ratings.
5. **iOS:** keep RecipeTheme green, Lora hierarchy, native sheets, 44pt hit targets, VoiceOver, light/dark, long titles; maintain existing 4 tabs, no dead controls. Multi-country localization #230.
6. **Acceptance:** first screen useful on target iPhone; an eight-step multi-timer/ingredient fixture + missing-info fixture + long Chinese/Japanese strings + 0-image case; conversions safe, old recipe storage/export preserved. No generated screenshot or PR status should be called a live UI test.

## Delivery dependencies

- [#247](https://github.com/natefox2017/cook/issues/247): nullable schema and backward compatibility first.
- [#248](https://github.com/natefox2017/cook/issues/248): native hierarchy and entry wiring second, coordinating #233 parameter cards, #241 AI Edit and #242–#244 share.
- Existing #231 timer sounds, #232 voice control and #233 parameter popovers remain separate scopes.
