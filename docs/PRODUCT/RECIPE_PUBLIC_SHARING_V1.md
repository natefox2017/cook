# Optional Recipe Sharing → Public Web → App Acquisition (No Community)

**Status: PLANNED / NOT SHIPPED.** User explicitly requested opt-in recipe sharing and an attractive long image with QR opening a mobile recipe webpage and an app download CTA. Replaces *only* the prior assumption that all public sharing is deferred; **does not approve a public user feed or profiles**.

## Deployed competitive pattern

- [Samsung Food official individual-recipe sharing](https://support.samsungfood.com/hc/en-us/articles/18588679568532-How-to-Share-Your-Saved-Recipes-with-Anyone) uses native options (email, copy link, SMS, WhatsApp, social) and a readable recipe link for visitors without an account.
- [Samsung Food community guidelines](https://support.samsungfood.com/hc/en-us/articles/18365296571412-Getting-Started-with-Samsung-Food-Communities) restrict community reposting of modified third-party recipes for creator-rights reasons. **Do not auto-expose imported third-party instructions or photos.**
- [Ipsos US QR-menu research](https://www.ipsos.com/en-us/qr-code-menus-are-growing-even-less-popular): about 65% of respondents reported having used restaurant QR menus, yet 37% liked the experience and 58% preferred paper. This measures **restaurant menus**, not this app's sharing conversion: QR literacy is established but compulsory scans create friction.
- [YouGov 2026 US out-of-home ad behaviors](https://yougov.com/en-us/articles/55200-ooh-effectiveness-americans-frequently-notice-out-of-home-advertising-many-act-on-what-they-see): 12% reported scanning an advertising QR code or tapping NFC in that context; this is a different population/question and must not be treated as a universal QR use rate.

**Decision:** click-through **HTTPS share URL as primary**; beautiful 9:16 or long recipe image for social/image contexts; QR at poster bottom as a **secondary option** for print/desktop/second-device scanning; email/SMS/WhatsApp/iMessage supplied by iOS system share sheet, **no compulsory email step**. For the same-phone recipient, publish the clickable URL alongside the graphic.

## Permissioned user journey

`Private Recipe Detail (default)`
→ `Share Recipe` → explain public data/copyright choices → owner selects `Share via Link`
→ **versioned sanitized read-only public snapshot** `/r/<opaqueSlug>`
→ `Web recipe full steps, ingredients, source attribution, Save/Get App CTA`
→ native Share Sheet: **Copy Link | Share Image | Save Image** (optional QR / short URL)
→ viewer can read without login and decide to install.

Owner can `Update Shared Version` or `Stop Sharing` at any time. Deleted or revoked shares stop serving content and previews; cache TTL/robots/OG/CDN requirements must be tested. There is no auto-publication of AI drafts, ingredients from private notes or unlicensed image assets.

## Explicit privacy and content fields

- Public allowlist: permitted title, approved/owned cover, authorized steps and ingredients, prep/cook/servings, explicit author/source credit.
- Exclude: email, phone, owner UUID, private local notes and settings, original attachments, private import transcripts, location/device data, unpublished changes, billing/auth/session keys, AI inference presented as fact.
- Imported third-party source: check rights before exposing full text/media. Default restricted preview + credited link to creator if no permission for republication. Review [Apple App Review intellectual-property requirements](https://developer.apple.com/app-store/review/).
- Public database/cache separate from the owner RLS/private `user_snapshots`; no anonymous enumeration; revoke/delete/owner switching and URL-token guessing must fail securely.
- Initial shares are unlisted (noindex). Explicit opt-in to public search discovery is a **separate future product decision**.

## App / Web contracts

- Domain remains TBD; never hardcode fabricated domain. Proposed `https://<verified-host>/r/<shareSlug>`.
- Add iOS Associated Domains, `.well-known/apple-app-site-association`, and native recipe Universal Link handling only after actual domain/Bundle ID verified. Apple official [Universal Links](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content): installed app opens URL directly; without app, visitor reads same URL on web. **Not automatically deferred attribution across App Store install.**
- Add [Safari Smart App Banner](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners) and explicit App Store CTA. Keep full web recipe readable without registration. Public frontend must be **separate** from high-privilege `admin/`.
- Render native long poster with SwiftUI `ImageRenderer`, code via `CIQRCodeGenerator`; suggested 1080×1920 and 1080×2400 layouts plus readable short link, verified scannable QR and legal cover fallback. Do not depend on an unapproved paid AI image provider.

## Invitation measurement: different certainty levels

| Event | Available certainty | Meaning |
| --- | --- | --- |
| share page view / CTA click / copy URL | First-party aggregate, de-botted best effort | Attributed to an opaque share token, not a named downloader |
| App Store campaign click/download | Apple privacy-protected **aggregate** | Use only when App Store Connect campaign `pt/ct` actually issued; [Apple campaign guide](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links/) has reporting threshold and does **not** expose each invitee |
| Confirmed invitee account | Explicit in-app invite code or user-authorized account claim | Only after validated consent/login; reject self-claims / repeats |
| Reward | **Not in first delivery** | Later gated campaign #246, on verified legitimate activation rather than download clicks |

Never infer a unique person from IP/UA/device fingerprint/cross-app graph. See [Apple privacy restrictions](https://developer.apple.com/app-store/user-privacy-and-data-use/). Additional affiliate analytics SDKs need separate tracking/ATT and country-by-country privacy review, not automatic integration.

## Dependencies / concrete Issues

- **#242 P0** [Owner opt-in share, public snapshot and revoke](https://github.com/natefox2017/cook/issues/242) **must precede** public web and posters.
- **#243 P0** [Mobile web recipe page / OG / App CTA / Universal Links](https://github.com/natefox2017/cook/issues/243).
- **#244 P0** [Template-driven long image + QR + native share sheet](https://github.com/natefox2017/cook/issues/244).
- **#245 P1** [First-party aggregate events + optional explicit invitation claim](https://github.com/natefox2017/cook/issues/245). Never present attributed clicks as identified downloads.
- **#246 P2** [Potential referral rewards + fraud/Apple/legal review](https://github.com/natefox2017/cook/issues/246), deferred until activation and reward budget are approved.
- **#248 P0** [Recipe Detail share entry point](https://github.com/natefox2017/cook/issues/248) hooks into this flow, no new social tab.

**Do not equate GitHub PR merge with production sharing:** mobile Web staging/valid domain, signed iPhone universal links, third-party app link previews, revocation and CDN behavior, source-rights audit and consent need real environment results.

## 2026-10-10 privacy-filtered Core payload (source code only)

`RecipeShareApproval` requires an exact local recipe ID and saved revision plus a chosen scope. `PublicRecipeSnapshot.preview` returns a strictly allowlisted content-only payload without notes, owner IDs, private media, AI evidence transcripts, coverData, image paths, raw Recipe JSON or credentials. The default `summaryAndSource` mode omits steps and ingredient quantities; full instructions are rejected unless the user explicitly confirms distribution rights. URL attribution is restricted to http(s), with no embedded credentials. The public server **must still** enforce logged-in owner, rights, versioned publishing/revocation, unguessable share token, RLS, image rights and cache invalidation. There is **no live public Web** or publishing button yet, and this code must not be exposed via anon Data API before #250 staging and #251 release evidence.
