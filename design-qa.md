# Subscription page design QA

final result: blocked

## Scope and approved target

User requested native SwiftUI code based on RecipePouch typography, imagery, and actual functionality. The latest annotated screenshot supersedes the earlier three-column icon strip and side-by-side plan cards.

Source: user annotated subscription screenshot provided on 2026-10-09 (feature strip and free-plan card marked in red).

Approved changes implemented:

- Left-aligned small SF Symbol and short copy per feature row; AI first, links/social second, cooking/planning third.
- Full-width Monthly card followed by Annual card. Annual is the default selection, including while StoreKit metadata is loading/unavailable.
- Light text Free entry beneath the main CTA. During onboarding this explicitly completes the onboarding flow.
- StoreKit prices and trial eligibility remain live inputs. An unavailable selected plan disables purchase, never silently switches to Free or charges a different product.
- Close, Retry, Restore, Terms and Privacy remain available. Larger accessibility sizes move price beneath plan copy and allow vertical scrolling.
- Same shared cards and features are used in onboarding and Settings.

Implementation: `ios/Recipe/Features/SubscriptionView.swift`.

## Verification evidence

Latest source compiled successfully for generic iOS with signing disabled:

```sh
xcodebuild -quiet -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .tmp/product-design-subscription/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

Log: `.tmp/product-design-subscription/device-build-final.log`.

Swift formatting lint with repository task configuration and `git diff --check` passed. Build is not installation, signing, purchase, or visual acceptance.

Earlier simulator results concern the superseded two-column design: one accessibility exit test passed; two onboarding tests failed (local StoreKit product unavailable and normal-size exit displayed a blank screen). Evidence is retained in `.tmp/product-design-subscription/verification-repaired.xcresult` and `captures-first/`. Those results are not acceptance of the current design. Test assertions were updated for the new vertical/default-annual layout and explicit free exit, but were not rerun.

UI-test launch isolation now distinguishes `isUITesting` from `bypassOnboarding`, retaining isolated share-inbox behavior when exercising onboarding.

## Visual comparison blocker

No rendered screenshot of the latest revision exists. Simulator work was stopped after receiving the coordination instruction that future testing must use the connected physical iPhone; that iPhone is being used by the coordinating conversation and was not operated here. Therefore no same-state side-by-side source/implementation comparison was performed for this revision, and typography, one-screen fit, tap flows, Dynamic Type and purchasing remain pending physical-device inspection. The previous screenshot must not be presented as the latest revision.

## Product limits

Production annual/monthly products are not configured in the current application environment. No production prices, trials or quotas were invented. Actual App Store purchase/restore is unverified. The user requested AI recipe generation copy; the codebase search did not find its independent generation screen/API. This visual change does not implement AI generation.

## Repository delivery

Working branch: `codex/first-launch-visual-refresh`.

Fresh `origin/main` is `f19c345` and its changes since this branch base affect admin/backend files, not the touched iOS layout. Existing uncommitted onboarding/assets/catalog work was preserved. The user subsequently requested a PR. This work is being committed and submitted as a draft because physical-device and visual acceptance remain incomplete. No merge, Issue closure, production deployment or physical-device installation is part of this submission. Issues #127/#128 remain open; draft PR #179 covers separate verification work.
