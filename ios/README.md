# Recipe iOS

Open `Recipe.xcodeproj` with Xcode 26.2 or later and select the shared `Recipe` scheme.

- iPhone app: iOS 18.0 or later, `com.shopkivoo.recipe`.
- SwiftUI screens: `Recipe/Features/`; shared appearance: `Recipe/Design/`.
- Local domain and persistence: the `RecipeCore` Swift package, with no external package dependency.
- UI tests: `RecipeUITests/`; `--uitesting` uses an isolated in-memory sample library and clears only legacy cooking-session keys.
- Fonts: bundled **Lora** under SIL OFL; sample photos reuse existing project design resources. See `Recipe/Resources/ASSET_SOURCES.md`.
- Native iOS 26 navigation uses the system materials. iOS 18 uses that OS's native appearance.

```sh
swift test --package-path RecipeCore
xcodebuild -project Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO test
```

For a physical iPhone, choose your development team in Xcode's Signing & Capabilities. No team ID or signing credential is committed.

The current iOS app has local structured-webpage/text/Vision-OCR/PDF import, RecipeCore storage, Supabase Auth/sync clients, and an embedded Share Extension with durable local receipts. **Existence in source does not prove provider configuration, deployment, signed Share handoff, real StoreKit or backend E2E** (current QA: #131–#133/#136 and #251). AI conversational generation, lawful audiovisual extraction and opt-in public recipe sharing remain **planned** (#238–#248) with controlled staging #250; do not present them as shipped.

Implementation and verification: [UI_IMPLEMENTATION.md](../docs/IOS/UI_IMPLEMENTATION.md).
