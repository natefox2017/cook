# Testing & Release — Manual Acceptance Contract

> **Live task and test evidence:** [Linear DEV Recipe Pals Development](https://linear.app/gengyun/project/recipe-pals-development-8c015c72cb6a); [release acceptance DEV-49](https://linear.app/gengyun/issue/DEV-49) and [controlled staging DEV-50](https://linear.app/gengyun/issue/DEV-50). GitHub automatic PR merge is deliberately **lightweight and source-focused** (`.github/workflows/ios-ci.yml`); it does not run Xcode/Core/StoreKit, database migrations, actual QA or device acceptance. Historical GitHub issue #139 and #251/#250 are archival pointers only.

## 1. Verify only the intended launch scope

- Freeze actual main SHA, signed IPA/bundle/CFBundleVersion, device/OS, backend version and applicable launch regions. An Issue in ROADMAP or a passing mock is **not** an enabled App feature.
- Explicitly select which planned features in current Linear DEV Issues are shipping; unfinished controls must remain hidden/disabled with truthful copy. Invite rewards #246 are deferred until separately authorized.
- Use the user's currently designated **single physical iPhone** and normal text size for native acceptance. Reuse scoped historical evidence if code/config genuinely match; don't turn inability to run a runner into an application failure.

## 2. Test layers and required evidence

| Layer | Examples | What it does NOT prove |
| --- | --- | --- |
| Pure Core/contract | SwiftPM model migration, field parsing and precise units, import OpenAPI/schema and provider fake, long poster URL QR decoding | Signed App, hosted AI/provider, real background notification |
| Local backend/isolated SQL | pgTAP/RLS/idempotent queue, owner separation, synthetic webhook, rate/size/media rules | Production migration, real ASC/RevenueCat event, login-wall/real video legality |
| Controlled staging (DEV-50) | Signed owner/JWT requests, permitted media source matrix, AI dialogue, public share read/withdrawal, CDN caching and public website | Production launch approval or actual App Store installs |
| Signed iPhone | 4 Tab, add/edit/recipe/cooking, expiry/notifications, locales, Share sheet, StoreKit Sandbox/Auth, privacy/VoiceOver | Other device types or global live purchases without evidence |
| Web visitors | Real HTTPS host, guest readable authorization fields, OG preview, stable URL + QR, App Store CTA, revoke status | Identity of a person who clicked download/install |

For each row record `PASS | FAIL | PARTIAL | BLOCKED | NOT RUN`, commit/versions, environment, test fixture, reproducible steps and sanitized logs/screenshots. Mock-only success must be labeled as such. Keep private user data and credentials out of artifacts.

## 3. Evergreen release acceptance requirements (execution and checkboxes live only in DEV-49)

- Current signed iOS app and relevant native Core tests build and launch; existing local recipes and old persisted data survive upgrade.
- Auth, App Store Connect StoreKit and cross-owner Sync cases selected for release have real evidence from DEV-104/DEV-101/DEV-99.
- Cooking/navigation/notification name/accessibility/performance actual observations and runner limitations have evidence from DEV-97/DEV-95/DEV-91 and DEV-49.
- Current English QA and expected locale behavior match code; international manual language/country feature DEV-88 gets its own actual QA when enabled.
- If AI import is included: source/field evidence, authorized media fallbacks, output revision safety, budget limits, 1-vs-multi recipe and edit diff validated via DEV-79/DEV-78/DEV-77/DEV-76 and DEV-50.
- If user-public Web is included: per-recipe opt-in, no private field disclosure, content-image rights, anonymous Web, HTTPS, noindex/OG/QR/caching/revoke and clear App CTA validated via DEV-73/DEV-71/DEV-68/DEV-66 and DEV-50. No installer identity inferred from raw App Store clicks.
- User privacy/export/delete, Apple platform policies, data retention, CORS/SSRF and rollback are reviewed. Rewards (DEV-64) require separate approval and cannot launch automatically.

## 4. Operational guardrails

The bullets above are durable test requirements, **not a separate task list**. Store each real PASS/FAIL/BLOCKED/NOT RUN and every executable checkbox in the corresponding Linear DEV issue. Do not treat this Markdown as a progress tracker.

Do not reopen canceled old #116–#120/#130/#135/#138/#141/#164 as mandatory launch tests. Their code/history can be reused but prior cancellation is real. A new owner-approved product scope uses its own Linear DEV issues and DEV-50.

Before changing production Supabase/Apple settings, provider secrets, public site hosting, DNS, subscription products or email campaigns, record the exact proposed change and obtain the user's separate authorization. Completing Linear DEV-49 means accepted **selected** launch checks, not that every planned optional feature exists.
