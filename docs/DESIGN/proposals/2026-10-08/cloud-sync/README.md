# Cloud Sync interaction

Developer: gengyun

## Decision

On 2026-10-08 the user explicitly asked to stop producing separate design mockups and continue implementation using the existing RecipePouch UI and functionality. Cloud Sync therefore extends the current Settings visual language instead of introducing a new design system.

## Implemented interaction

- Show the real signed-in RecipePouch account, last successful sync time, and current sync status.
- Support Automatic, Wi-Fi Only, and Manually modes through the live sync coordinator.
- Expose **Sync Now** for a signed-in account.
- On first account connection when local data already exists, show local/cloud counts and require **Merge Local + Cloud** or **Keep Local for Now** before any upload can overwrite cloud data.
- On true concurrent edits, list each conflict and require an explicit **This iPhone** or **Cloud** choice.
- Treat Collection membership conflicts independently, and surface same-name Collections / same meal-plan slot collisions as explicit conflicts.
- Keep cloud-account deletion separate from local-library deletion.

## Safety boundaries

- The client never uses service-role credentials.
- Snapshot reads remain owner-scoped.
- Snapshot writes use revision compare-and-swap and an explicit target-account check.
- The final migration that revokes direct authenticated table mutations is committed in the repository but still requires production execution.
- Code completion is not the same as two-device production acceptance; that remains part of #29/#34.
