# Cook iOS App

Functional SwiftUI V1 implementation for Issue #18.

## Run

Install XcodeGen, then:

```sh
cd ios/CookApp
xcodegen generate
xcodebuild -project Cook.xcodeproj -scheme Cook -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The app currently provides local-first recipe library/search/favorites, recipe detail/editing, URL/photo/manual intake, cooking steps/timer, grocery state and profile preferences. Backend recipe extraction remains an API integration task; URL intake deliberately preserves the source and marks the recipe for review instead of inventing recipe data.
