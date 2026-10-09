# Repository Documentation & GitHub Issue Reconciliation — 2026-10-09

## Snapshot and method

- Repository: private [natefox2017/cook](https://github.com/natefox2017/cook), audited baseline `main@1b7fc8b43f50edb3b20ad8067437e8ed8bfa1629` (PR #249), with no open PRs at the inventory point.
- Inventoried **461 tree nodes** and screened **70 tracked Markdown/YAML documentation/config paths** (66 Markdown and four YAML config/templates). Checked local relative Markdown links against the tracked tree (not external domains or rendered anchors); found **one dangling image link** in `docs/DESIGN/proposals/2026-10-08/secondary-page-navigation/README.md`.
- Enumerated GitHub issues: **24 open after adding #250/#251; 52 closed Issues** (13 closed as not_planned), **175 closed PRs**. Multiple earlier closed QA tasks retain historical unchecked boxes; verified live issue state before choosing what to change.
- Read operational docs/README, AGENTS, localization, UI approvals, recipes/import/StoreKit/Auth/Share Extension, snapshot QA, current product plans and deployment provenance alongside current source (RecipeLanguage/InfoPlist/build product IDs/ShareViewController/model).
- No Xcode, real iPhone, ASC Sandbox, live provider tests, Supabase production queries or external link availability checks performed in this audit. Static evidence is not runtime evidence.

## Confirmed corrections in the documentation PR

| Finding | Verified current truth | Correction |
| --- | --- | --- |
| Wrong font | `ios/Recipe/Info.plist` registers Lora, current Theme uses Lora | Fix `ios/README.md`, don't reinstate Source Sans 3 from the 2026-10-07 prototype |
| Conflicting locale policy | `RecipeLanguage.resolve` returns `en` for ordinary launches; locale smoke requires test flags | Correct secondary-page doc; feature #230 owns planned manual language+country selectors |
| Subscription IDs incorrectly called nonexistent | Xcode Debug/Release `RECIPE_SUBSCRIPTION_PRODUCT_IDS` use `com.shopkivoo.recipe.pro.monthly,com.shopkivoo.recipe.pro.yearly` | Mark `AUTH_STOREKIT_SYNC_READINESS.md` old config section as historical, link #132 current actual-ASC blocker |
| Brand / extensions | App/Extension `CFBundleDisplayName` = Recipe Pals, extension consumes URL/text and has image/PDF handling paths (but activation supports URL/text) | Rename customer-facing docs, preserve legacy NSError domain & bundle/storage identifiers |
| Closed QA still says OPEN | GitHub #139/#134/#129/#128/#127/#126 are closed but old bodies include unchecked steps | Add archived-state notices *without reopening* or rewriting evidence; use live #251, with #250 for new staging |
| Canceled import tickets are mistakenly treated as dependencies | #116–#120/#130/#135/#138/#141/#164 are closed not_planned, yet new product scope approved #238–#248 | Leave history closed; link new legal-media/AI/public-Web work to **new #250**, selected release #251 |
| Broken relative image | Secondary-page proposal linked missing `secondary-page-navigation.svg` | Remove dead link, cite existing UI-016 visual reference and retained written UI-017 behavior |
| Current UI vs planned design | Several design-assets `PENDING` mean image approval pending, even where SwiftUI functionality is implemented | State distinction clearly; add new AI/share/detail concepts as **SCOPED**, not falsely APPROVED or shipped |
| Release / CI confusion | Private-repo auto merge performs source guard, not Xcode/SQL/StoreKit | Update release manual acceptance and development docs; don't add heavy mandatory CI |
| New sharing/data rights | Prior V1 'no Web' excluded general Web; user newly approved **opt-in single recipe landing only** | Align privacy/flow/data docs. No public feed, automatic publishing, email blasting, device fingerprinting or reward payout |
| Historic source status | Dated code/AI/StoreKit/DB documents refer to old commit/provider state | Preserve historical evidence, add current-status banner and link new live QA matrix instead of erasing provenance |

## Cross-doc source of truth and ownership

1. **Live task state:** [GitHub Open Issues](https://github.com/natefox2017/cook/issues?q=is%3Aissue+is%3Aopen); [current dated backlog](CURRENT_BACKLOG_2026-10-09.md) helps sequence but is not live.
2. **Current technical code:** `main`, `AGENTS.md`, `ios/Recipe.xcodeproj`, `ios/RecipeCore`, `ios/ShareExtension`, and verified deployed services only when runtime evidence exists.
3. **Approved product contracts:** `docs/PRODUCT_BASELINE_V1.md`, `docs/DESIGN_SYSTEM.md`, `docs/UI_DESIGN_APPROVALS.md`. `docs/DESIGN_ASSETS.md` registers historical design images; art approval differs from code implementation.
4. **Next features, not live:** `docs/PRODUCT/AI_RECIPE_EXPERIENCE_2026-10-09.md`, `docs/PRODUCT/RECIPE_PUBLIC_SHARING_V1.md`, `docs/PRODUCT/RECIPE_DETAIL_COMPETITOR_AUDIT_2026-10-09.md`, `docs/ROADMAP.md`.
5. **Acceptance vs deployment:** #250 staging for new AI/Share; #251 release selected-scope; existing open #131/#132/#133/#136/#137/#155/#189 still control their own scoped evidence.

## Unresolved conditions, not secretly fixed

- Actual third-party audiovisual access and permission/platform policy, prompt/provider price+latency, multi-recipe evidence, precise allergen/nutrition mapping: no broad provider or production pass. #238–#241 / #250.
- User-approved domain, SSL/public hosting/App Store CTA/Apple Universal Links & AASA, rights to photos/text and revocation/CDN cache: no site deployed. #242–#245 / #250.
- Real iPhone notification settings old name, installed binary equivalence, full Auth/StoreKit/Sync and Live user acceptance: #131/#132/#133/#136 and #251.
- Manual language/country preferences and non-English catalog coverage: #230, **not** fixed by the existing four-language test catalogs.
- Actual release date/features/rollout region/reward policy: owner must explicitly decide; backlog priorities do not silently enable features.

## Repeatable check

Run `python3 scripts/check_documentation_links.py` from the repo root. Checks only **tracked local relative Markdown target paths**; external HTTPS references and anchors need separate live/manual verification. Re-run before a broad docs PR and cite the real command/output.
