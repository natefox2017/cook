# Testing & Release — Current Manual Acceptance Contract (2026-10-09)

> GitHub automatic PR merge is deliberately **lightweight and source-focused** (`.github/workflows/ios-ci.yml`). It does not run Xcode/Core/StoreKit, database migrations, actual QA or device acceptance. Previous launch umbrella #139 and older #126–#129/#134 are **closed historical records**; the current live selected-release test ledger is [#251](https://github.com/natefox2017/cook/issues/251). New AI/import/share staging: [#250](https://github.com/natefox2017/cook/issues/250).

## 1. Verify only the intended launch scope

- Freeze actual main SHA, signed IPA/bundle/CFBundleVersion, device/OS, backend version and applicable launch regions. An Issue in ROADMAP or a passing mock is **not** an enabled App feature.
- Explicitly select which planned features #230–#248 are shipping; unfinished controls must remain hidden/disabled with truthful copy. Invite rewards #246 are deferred until separately authorized.
- Use the user's currently designated **single physical iPhone** and normal text size for native acceptance. Reuse scoped historical evidence if code/config genuinely match; don't turn inability to run a runner into an application failure.

## 2. Test layers and required evidence

| Layer | Examples | What it does NOT prove |
| --- | --- | --- |
| Pure Core/contract | SwiftPM model migration, field parsing and precise units, import OpenAPI/schema and provider fake, long poster URL QR decoding | Signed App, hosted AI/provider, real background notification |
| Local backend/isolated SQL | pgTAP/RLS/idempotent queue, owner separation, synthetic webhook, rate/size/media rules | Production migration, real ASC/RevenueCat event, login-wall/real video legality |
| Controlled staging (#250) | Signed owner/JWT requests, permitted media source matrix, AI dialogue, public share read/withdrawal, CDN caching and public website | Production launch approval or actual App Store installs |
| Signed iPhone | 4 Tab, add/edit/recipe/cooking, expiry/notifications, locales, Share sheet, StoreKit Sandbox/Auth, privacy/VoiceOver | Other device types or global live purchases without evidence |
| Web visitors | Real HTTPS host, guest readable authorization fields, OG preview, stable URL + QR, App Store CTA, revoke status | Identity of a person who clicked download/install |

For each row record `PASS | FAIL | PARTIAL | BLOCKED | NOT RUN`, commit/versions, environment, test fixture, reproducible steps and sanitized logs/screenshots. Mock-only success must be labeled as such. Keep private user data and credentials out of artifacts.

## 3. Release checklist

- [ ] Current signed iOS app and relevant native Core tests build and launch; existing local recipes and old persisted data survive upgrade.
- [ ] Auth, App Store Connect StoreKit and cross-owner Sync cases selected for release have real evidence from #131/#132/#133.
- [ ] Cooking/navigation/notification name/accessibility/performance actual observations and runner limitations have evidence from #136/#137/#189 and #251.
- [ ] Current English QA and expected locale behavior match code; international manual language/country feature #230 gets its own actual QA when enabled.
- [ ] If AI import is included: source/field evidence, authorized media fallbacks, output revision safety, budget limits, 1-vs-multi recipe and edit diff validated via #238–#241/#250.
- [ ] If user-public Web is included: per-recipe opt-in, no private field disclosure, content-image rights, anonymous Web, HTTPS, noindex/OG/QR/caching/revoke and clear App CTA validated via #242–#245/#250. No installer identity inferred from raw App Store clicks.
- [ ] User privacy/export/delete, Apple platform policies, data retention, CORS/SSRF and rollback are reviewed. Rewards (#246) require separate approval and cannot launch automatically.

## 4. Operational guardrails

Do not reopen canceled old #116–#120/#130/#135/#138/#141/#164 as mandatory launch tests. Their code/history can be reused but prior cancellation is real. A new owner-approved product scope uses new feature tickets and #250.

Before changing production Supabase/Apple settings, provider secrets, public site hosting, DNS, subscription products or email campaigns, record the exact proposed change and obtain the user's separate authorization. Closing #251 means completed **selected** launch checks, not that every planned optional feature exists.
