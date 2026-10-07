# Cook iOS

Open `Cook.xcodeproj` with Xcode 26.2 or later and select the shared `Cook` scheme.

- iPhone app: iOS 18.0 or later, `com.modelhub.cook`.
- SwiftUI screens: `Cook/Features/`; shared appearance: `Cook/Design/`.
- Local domain and persistence: the `CookCore` Swift package, with no external package dependency.
- UI tests: `CookUITests/`; `--uitesting` uses an isolated in-memory sample library and clears only Cook cooking-session keys.
- Fonts: Source Sans 3 under SIL OFL; sample photos reuse existing project design resources. See `Cook/Resources/ASSET_SOURCES.md`.
- Native iOS 26 navigation uses the system materials. iOS 18 uses that OS's native appearance.

```sh
swift test --package-path CookCore
xcodebuild -project Cook.xcodeproj -scheme Cook \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO test
```

For a physical iPhone, choose your development team in Xcode's Signing & Capabilities. No team ID or signing credential is committed.

The current app operates locally. Structured recipe webpages, pasted text, Apple Vision OCR, and selectable-text PDFs feed the library. Supabase account/sync, social-video AI parsing, the Share Extension and background import queue remain separate integration work; no fake remote progress or imported sample content is shown.

Implementation and verification: [UI_IMPLEMENTATION.md](../docs/IOS/UI_IMPLEMENTATION.md).
