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

The coordinator's first signed real-device hosted run executed both cases:
**2 FAIL, 0 skip**. The configured-ID assertion passed, but StoreKit returned
no formal products and no usable verified legacy entitlement. This is a real
runtime failure, not the earlier UI runner launch failure.

The original `Recipe` scheme had no active StoreKit configuration. The host
creates `Transaction.updates` during app initialization and calls StoreKit in
its root `.task`, before a testcase creates `SKTestSession(contentsOf:)`.
Copying a fixture into a test bundle did not establish the host's StoreKit
environment before those calls. Missing launch configuration is confirmed;
the previous log does not prove that early connection timing was the only
cause, or rule out local transaction verification errors.

Use the dedicated **RecipeStoreKit** scheme and **RecipeStoreKit** test plan
for the next signed real-device run. Its Run action selects
`RecipeSubscriptionTests.storekit` using the same scheme reference form as
[Apple's StoreKit sample](https://developer.apple.com/documentation/storekit/implementing-a-store-in-your-app-using-the-storekit-api).
Its test action retains Run argument/environment inheritance; the plan starts the host with
`--uitesting` and selects only `RecipeSubscriptionStoreTests` in the existing
hosted target. The normal `Recipe` scheme is unchanged for actual ASC testing.
`SKTestSession` still initializes inside each testcase after host initialization;
this change does not move it ahead of the host. The intended ordering is Xcode
syncing the Run action's active fixture before launching the host, followed by
the testcase resetting and controlling that environment. The ordering depends
on actual Xcode/device synchronization and is not proven by scheme XML alone.

```sh
xcodebuild -project ios/Recipe.xcodeproj -scheme RecipeStoreKit \
  -testPlan RecipeStoreKit -destination 'platform=iOS,id=<real-device-id>' \
  -derivedDataPath '<fresh-signed-test-output>' \
  -only-testing:RecipeTests/RecipeSubscriptionStoreTests \
  -parallel-testing-enabled NO DEVELOPMENT_TEAM='<authorized-team>' test
```

Rebuild signed test artifacts for this scheme before execution; do not reuse
the old `Recipe` scheme's `.xctestrun`. The generic generated runfile confirms
the host bundle, `--uitesting` and the selected suite; it does not serialize a
StoreKit path or prove that a CLI/device launch actually synced the fixture.
That launch behavior remains a real-device acceptance requirement. The tests
now additionally require each fixture entitlement to be **verified** with
environment **Xcode**, and report an unverified transaction's error. No custom
receipt certificate or signature bypass is added: this client uses StoreKit 2
`VerificationResult`, not manual receipt validation. See
[Apple's setup guidance](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

Do not use generic build-for-testing results as runtime acceptance or substitute
fixture transactions for ASC Sandbox/TestFlight purchases. The original UI
assertions and all hosted assertions remain; none are removed or converted to skip.

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

## Admin finance integrity boundary (2026-10-10, partial #276)

The Admin dashboard and Billing page **must not** derive monthly recurring revenue
by multiplying an average active catalog price by the number of paid subscriptions.
An active subscriber might be trialing, annual, lifetime, discounted, in a
different currency, or already canceled but still entitled. Catalog pricing
alone cannot establish verified recurring amounts.

Until the backend can reconcile entitlement-level product/period/currency,
refunds and active billing status to a chosen reporting currency, the JSON
field `mrr` / `revenueMrr` is explicitly **null (not calculated)**.
Admin UI renders a dash and states the methodology is unavailable. The
`activePaid`/subscriber-count field remains a separate count, **not cash flow**.

The other recorded-purchase revenue figures are **not yet certified**: before
finance acceptance, #276 must enforce native currency grouping or documented FX,
test/sandbox/refund exclusion, event deduplication, pagination/error handling
and settlement-vs-gross definitions. No actual payout, tax or refund values
are inferred from nullable MRR. This change is source-only and not a deployment.

### Recorded currency-safe purchase aggregates (2026-10-10)

Admin recorded purchase reports preserve the **original event currency**.
RevenueCat webhook `price_in_purchased_currency` is denominated in `currency`,
whereas `price` is a USD amount. The latter may be used as a fallback **only
for USD purchases**; a non-USD event without its native amount stays unavailable
and flags the report as incomplete. This contract is shared by the revenue
ledger, latest subscription purchase amount and Dashboard recent payments.
See [RevenueCat webhook fields](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields)
and [DEV-47](https://linear.app/gengyun/issue/DEV-47).
`byCurrency` lists native purchase totals per ISO-style three-letter code, with
App Store and Google Play subtotal columns; no automatic FX conversion is used.
The scalar totals and six-month charts are only shown when every included
purchase amount has a valid currency, exactly **one** currency is represented,
and the fetched page is below its hard 5,000-event boundary. Otherwise the
scalars are `null`, and Billing displays the currency groups without a
meaningless combined total. A null figure is not a zero-dollar result.

These are **recorded positive purchase-event amounts**, not verified net
settlement revenue. Refund/reversal, event deduplication, sandbox filtering,
full pagination, MRR and finance reconciliation require further DEV-47 acceptance.
A `byCurrency` array may itself be **partial** if any source record was
unusable or the query reached its cap; never use it as an authoritative report
without its completeness metadata. No production data has been modified.

### Partial-report detection (2026-10-10)

The Admin subscriptions list (500-row ceiling) and its 2,000-event
purchase-enrichment query now reject a page at the configured limit instead
of implying all matching records are shown. The read-only Dashboard
requires successful exact counts and confirms that the fetched profile,
subscription, download, user-growth and recipe-growth rows cover those counts.
Missing SQL results or a default PostgREST row cap produce an **explicit
service-unavailable/error state** in the Admin UI, not a fabricated zero or a
complete-looking report.

This is fail-closed detection, **not full pagination**. If the dataset grows
beyond these bounds, use an authorized, bounded paginated query or server-side
aggregation and complete DEV-47 acceptance before claiming a complete finance report.
The existing recent-activity limits remain intentional. Live billing and
account data were not read or modified as part of this code change.

### Recorded purchase-event filter (2026-10-10)

Only `INITIAL_PURCHASE`, `RENEWAL` and `NON_RENEWING_PURCHASE`
contribute to preliminary **positive purchase-event** amounts.
RevenueCat `PRODUCT_CHANGE` represents a plan/entitlement transition and
may be emitted alongside a distinct renewal or initial purchase during an
immediate change. Counting both can double-count the charge. See the
[official event flows](https://www.revenuecat.com/docs/integrations/webhooks/event-flows).
Historical source records are preserved, but product-change events no longer
count as a new purchase in Admin dashboard totals or the per-subscription
last-purchase display.

This is **not net revenue**: refunded historical periods and refund reversals,
duplicate deliveries, purchase environment, settlement timing and recognized
financial currency remain separate unresolved reconciliation work under #276.
