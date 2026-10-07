# Cook UI spacing normalization

Status: APPROVED by the user on 2026-10-08. The simulator screenshots are unmodified references captured from the merged app on iPhone 18 Pro Max (iOS 27.0). The supplied `settings-reference.jpg` is the visual reference for section spacing and direct menu icons.

## Observed scope

The Recipes, Meal Plan, Groceries, Profile, recipe detail, and Settings flows use visibly different title positions and vertical rhythm. The Meal Plan helper text and secondary-page content can sit beneath the custom bottom tab bar. The empty Groceries state leaves a large uneven gap below its filters. Profile has a large gap between its profile header and first menu card.

## Proposed correction

- Normalize page side insets to 20 pt and use a shared 8 / 12 / 16 / 24 pt spacing rhythm for content groups.
- Align root-page content to a consistent start below the status and navigation areas; remove accidental top offsets while preserving each page's existing hierarchy.
- Keep content clear of the bottom tab bar and safe-area controls on root and pushed pages.
- Match the supplied Settings reference: use consistent vertical gaps from page title to section labels and from section labels to their cards; show Profile menu icons directly without circular backgrounds.
- Preserve every existing page, section, control, route, and behavior. This proposal changes spacing and removes the Profile menu icon circles only.

The icon treatment follows the user's supplied screenshot. No colors, typography, cards, or feature content are redesigned.
