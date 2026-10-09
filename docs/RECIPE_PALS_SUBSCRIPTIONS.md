# Recipe Pals subscription configuration — #132

Confirmed by the coordination chat on 2026-10-09. ASC app: Recipe Pals,
Apple ID `6820907753`, bundle `com.shopkivoo.recipe`, subscription group
`22457671` (Recipe Pals Pro). The coordinator confirmed from the saved ASC page
that monthly record `6820909171` and annual record `6820910384` both use
subscription level **1** in that group, at the prices below. This records ASC
configuration confirmation; product availability and real-device purchase
acceptance remain to be verified.

| Duration | Formal product ID | USD base price | English US display name |
| --- | --- | --- | --- |
| 1 month | `com.shopkivoo.recipe.pro.monthly` | $4.99 | Recipe Pals Pro Monthly |
| 1 year | `com.shopkivoo.recipe.pro.yearly` | $39.99 | Recipe Pals Pro Annual |

Both products provide the same `pro` entitlement and belong to the same group
at the same service level (level 1). There is no introductory offer or new lifetime
product in this configuration. The annual price saves 33.2% against twelve
monthly payments ($59.88); its monthly equivalent is approximately $3.33.
These values are a configuration decision, not a profitability assessment.

English US descriptions: “Premium recipe features, billed monthly.” and
“Premium recipe features, billed annually.” Group display name: Recipe Pals
Pro. Preserve the four-language catalogs; only English release is currently
approved. StoreKit supplies storefront prices/currency and actual offer
eligibility. Other storefront prices should be reviewed in ASC using Apple's
available price points; do not embed conversion rates in the client.

## Official price comparison checked 2026-10-09

- [Crouton US App Store](https://apps.apple.com/us/app/crouton-recipe-manager/id1461650987)
  lists Discover Monthly $1.99 and Discover Yearly $14.99, plus separate purchases.
- [Umami US App Store](https://apps.apple.com/us/app/umami-recipe-manager/id1597523594)
  lists multiple monthly ($0.99/$3.99) and annual ($9.99/$19.99) products.
  This listing does not establish which pair is offered to a new customer.
- [ReciMe's English pricing help](https://recime.app/help/en/articles/11630592-wie-viel-kostet-das-recime-abo)
  gives US annual $39.99. Other language variants differ, and the
  [US App Store](https://apps.apple.com/us/app/recime-recipes-meal-planner/id1593779280)
  lists multiple Plus prices without their periods. No monthly price is inferred.

The selected starting prices match the existing backend USD monthly/annual
baseline and ReciMe's documented US annual example.

## Client contract and compatibility

Debug and Release app build settings default `RECIPE_SUBSCRIPTION_PRODUCT_IDS`
to the two formal IDs. An explicit xcodebuild assignment still overrides them:

```sh
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  RECIPE_SUBSCRIPTION_PRODUCT_IDS='desired.monthly,desired.yearly' \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The existing Debug-only `--uitesting` /
`RECIPE_STOREKIT_TEST_PRODUCT_IDS` override still allows local fixtures and an
explicit empty/unavailable configuration. The legacy plist/build key remains
readable as a fallback; explicitly configured legacy IDs are also recognized
for entitlements. Verified legacy monthly, annual and lifetime purchases keep
access, but those IDs are not added to the default sale list. Unverified,
revoked and expired transactions do not grant access.

The current paywall has no hardcoded $5.99 label. It uses `Product.displayPrice`
and shows trial copy only when StoreKit reports an eligible free introductory
offer. There is no design change or global suppression of legitimate future
offers. Fixture prices live only in `RecipeSubscriptionTests.storekit`.

The current client uses StoreKit 2 directly; it does not read RevenueCat
Offerings. Keep the backend entitlement identifier `pro`. A new RevenueCat
Offering may use `default` with `$rc_monthly` / `$rc_annual`, but actual Dashboard
configuration is unverified here; reuse an existing identifier after inspection.
Product creation alone does not establish RevenueCat event delivery from this
StoreKit client.

## Backend proposal and remaining acceptance

A read-only catalog check found legacy App Store plans pointing to
`com.natefox.cookapp.pro.monthly`, `com.natefox.cookapp.pro.yearly` and
`com.natefox.cookapp.lifetime`. Those rows are not evidence that ASC products
exist. The unique product key is `(platform, product_id)`, so an additive
proposal can preserve the old rows and historical finance records:
[`supabase/review/recipe_pals_subscription_plans.sql`](../supabase/review/recipe_pals_subscription_plans.sql).
It is outside migrations, ends with ROLLBACK, and was not executed on production.
Do not apply it until new products and the commerce integration are confirmed;
an existing conflicting formal row must be inspected rather than overwritten.

Only real devices may be used for iOS runtime testing. Unsigned generic iOS
builds and build-for-testing compile the client/test targets; they do not run
StoreKit transactions. The new StoreKitTest cases cover both formal IDs, no
introductory offer, and legacy monthly/lifetime access using a local fixture;
they are delivered for a separate signed real-device run by the coordinator.
The existing `RecipeTests` hosted target also contains
`RecipeSubscriptionStoreTests`: it directly checks default IDs, loaded product
periods/prices, absent introductory offers, service purchase state and legacy
monthly/lifetime entitlements against the same local fixture. This avoids the
separate UI runner but still requires a signed real-device test host and local
StoreKit testing support. The fixture is a test-target resource, not an app
release resource. The original UI tests remain unchanged; button titles,
visible price labels and page layout still require UI automation.

The coordinator can select only the hosted cases when running on the real
device: `-only-testing:RecipeTests/RecipeSubscriptionStoreTests`. Do not use
generic build-for-testing results as runtime acceptance or substitute these
fixture transactions for ASC Sandbox/TestFlight purchases.

No StoreKit runtime PASS is claimed in this delivery. A simulator attempt was
interrupted before any test case ran; its dedicated device and temporary test
data were removed after the policy correction.

Manual verification on 2026-10-09:

- Release `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**.
- Debug `generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO build-for-testing`:
  **TEST BUILD SUCCEEDED**. Test cases were compiled, not executed.
- Both built app plists resolve the two formal product IDs and bundle
  `com.shopkivoo.recipe`. Explicit CLI product IDs override the defaults in
  `-showBuildSettings`; Debug fixture and empty overrides remain in source.
- Swift files formatted with four-space `swift-format`; `git diff --check` passed.
- HMAC executable source hashes still match `release.json`; only its README
  changed. The backend SQL proposal was not executed, and no production or
  real payment state was changed.

#132 remains open until actual ASC Sandbox/TestFlight
product loading, purchase/restore and entitlement lifecycle results are recorded
with environment, product ID, transaction evidence and screenshots.
