# Account sign-in design

Implemented on 2026-10-08 following the user's direct request to redesign the
native login page, remove explanatory copy, use official provider styles, and
default the app to Simplified Chinese. This record does not claim final visual
approval or successful real authentication.

## Screen and flow

- One account screen for sign-in and account creation: email → Next → Sign In →
  verification code. Password sign-in remains an alternative in the same flow.
- A simple title and input replace the grouped form cards and explanatory text.
- The primary action and both provider buttons share a 52-point height and
  12-point corner radius, with a 12-point gap between provider buttons.
- Google uses the downloaded full-color brand icon, Google Sans Medium, white
  background, dark text, and a neutral border. Apple uses the native
  `SignInWithAppleButton` control and its official black/white variants.
- Authentication alerts use localized product copy, rather than raw server
  diagnostics. Password recovery and sign-out remain available.

## Official asset provenance

- [Google Sign in branding guidelines](https://developers.google.com/identity/branding-guidelines)
- Google icon: `https://developers.google.com/static/identity/images/g-logo.png`,
  downloaded 2026-10-08 and stored unchanged in `GoogleSignInLogo.imageset`.
- Google Sans: the `google/fonts` repository's `ofl/googlesans` variable font,
  stored with its accompanying SIL Open Font License in `Resources/Fonts`.
- [Apple native button documentation](https://developer.apple.com/documentation/signinwithapple/displaying-sign-in-with-apple-buttons-in-your-app)

## Language and validation

New application preferences default to `zh-Hans` independently of the device's
language. Explicit per-app language selection in iOS Settings remains supported;
UI-test language overrides remain available. The String Catalog's source language
stays English while the application fallback region is Simplified Chinese.
Static product labels passed through the Profile and empty-state components now
use localized keys; user-entered profile names and email addresses remain data.

The unsigned simulator build succeeded. A normal launch without language
arguments displayed the redesigned screen, including the native Apple button,
in Simplified Chinese. XCTest, Dynamic Type, dark mode, provider sign-in,
verification-code delivery and cloud writes were not verified for this redesign.
