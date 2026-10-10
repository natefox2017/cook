# iOS gesture interaction QA — 2026-10-10

Tracking: [#281](https://github.com/natefox2017/cook/issues/281)

## Interaction contract

- **Root tabs:** horizontal swipe left → next tab, right → previous tab. Order remains Recipes / Plan / Groceries / Profile. Never wrap from either end. A gesture is accepted only when horizontal displacement is at least 96 points and exceeds vertical displacement by 1.8×.
- **Gesture precedence:** root swipes use SwiftUI's lower-priority `.gesture`, so native horizontal filter/date-strip scrolling and each List row's `.swipeActions` have precedence. Only root screens install tab swipes; pushed screens retain native interactive back navigation. The app retains its native tab bar and separate NavigationStacks.
- **Meal Plan:** horizontal swipe on the displayed **date range**, not on the horizontally scrolling seven-day strip, advances or rewinds one week using existing calendar logic.
- **Cooking Mode:** horizontal swipe on the main step text navigates using the same functions as Previous and Done & Next. Swiping past the final step invokes the existing finish flow; timers and ingredient controls are outside the gesture surface. The full-screen sheet still requires its Close action.
- **Groceries:** a native **leading** row swipe marks an item bought or not bought; the existing trailing Edit/Delete gestures stay available. The visible check button remains an alternative.

## Automated test coverage

`ios/RecipeUITests/RecipeUITests.swift` adds:
- `testRootTabsSwipeBetweenAdjacentScreensWithoutWrapping`
- `testMealPlanWeekHeaderCanSwipeWithoutChangingTabs`
- `testCookingStepTextSwipesUseExistingStepControls`
- `testGroceryLeadingSwipeTogglesStateWithoutBreakingTrailingActions`

## Device acceptance (not yet executed in this non-macOS environment)

On iOS 18+ iPhone simulator **and physical device**:

1. From a seeded library, swipe both directions through all four tabs. Verify selection, native tab bar, preserved root titles, and no wrap.
2. Scroll Recipes vertically and horizontally scroll its filter chips. Scroll the Plan seven-day strip. Neither gesture should switch tabs.
3. On Plan, swipe only on the center week-range text. Verify week changes without tab changes; left/right arrows and date picker still work.
4. On Groceries, swipe right on a row to mark bought, then left to expose Edit/Delete. Check that neither action inadvertently changes tabs. Also verify the row check button.
5. Open recipe details, Profile → Settings, a sheet, and the manual editor. Verify root-tab swipes do not fire over them; edge-back navigation stays native; unsaved editor content cannot be lost by accidental dismissal.
6. In Cooking Mode, swipe between steps and verify the same done-state persistence as buttons; verify the final-step confirmation and that running timers survive navigation.
7. Repeat with VoiceOver, larger Dynamic Type, dark mode, and right-to-left localization if supported; check visible buttons remain accessible.
8. Capture screenshots/recording for test evidence before marking #281 as device-verified.

No change to Supabase, app data formats, branding, navigation hierarchy, or release language policy.

References: [Apple HIG — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [SwiftUI gesture precedence](https://developer.apple.com/documentation/swiftui/view/gesture(_:including:)).
