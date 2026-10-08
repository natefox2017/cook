# RecipePouch V1 Export Formats

Updated: 2026-10-08

Both **Profile → Export Recipes & Data** and **Settings → Data & Privacy → Export Recipes & Data** offer exactly three choices. The picker is native iOS Files; no in-app restore/import workflow is available.

| Choice | File | Contents | Excluded |
| --- | --- | --- | --- |
| All Local Data (JSON) | `RecipePouch-All-Local-Data.json` | The versioned local snapshot: recipes, Collections/memberships, groceries, meal plan, local profile/preferences and local sync deletion markers | Cooking sessions stored separately in UserDefaults, App Store purchases, server secrets, remote-only data |
| Recipes Only (JSON) | `RecipePouch-Recipes.json` | `recipepouch.recipes` version 1: recipe fields, original source details, preserved amount wording, steps, favorites, notes, Collection stable IDs and membership relationships | Groceries, meal plan, app preferences, sync-state/tombstones, signing credentials |
| Recipes Only (HTML) | `RecipePouch-Recipes.html` | UTF-8 offline text: index, recipes, ingredient original wording, steps, timers/heat, source text/HTTPS source links, notes and Collection names | Images/attachments, groceries, meal plan, app preferences, executable scripts, network assets |

## Technical contract

- `RecipePortableExport.json(snapshot:)` returns a portable recipe-only JSON format independent of the device's complete local snapshot.
- `RecipePortableExport.html(snapshot:)` creates a standalone UTF-8 document with an explicit restrictive Content Security Policy. User text is HTML-escaped; only `https` source links without embedded credentials are clickable.
- Missing values remain missing. `to taste`, quantity ranges, approximate durations and original source text are never made precise during export.
- Source photos and binary attachments are intentionally omitted from HTML. Recipe-only JSON retains the existing model's source/cover fields, including `coverData` if present (encoded as JSON Data).
- Full-local JSON is meant for readable/portable data export. **None of these formats are a guaranteed restore backup**: no App UI restores a library from these files in V1.

## UI feedback / verification

- A format menu appears before the Files picker. Cancelling the format menu does not export anything.
- File selection success is shown only after the system confirms export. Errors are surfaced; a user-cancelled export is not reported as success.
- Test the two entry points on a device with English UI and separately test the formats with empty data, unknown quantities, Unicode, hostile HTML text and absent image assets.
- Actual iOS Files picker testing remains part of release acceptance Issue #34; tests existing in source or a lightweight PR auto-merge check are not evidence of a simulator run.

See Issues #7 and #34.
