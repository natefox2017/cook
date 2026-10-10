# Optional Recipe Sharing → Public Web → App Acquisition (No Community)

**Status: PLANNED / NOT SHIPPED.** User explicitly requested opt-in recipe sharing and an attractive long image with QR opening a mobile recipe webpage and an app download CTA. Replaces *only* the prior assumption that all public sharing is deferred; **does not approve a public user feed or profiles**.


## V1 public-share API contract (DEV-216; normative design, NOT DEPLOYED)

**Scope and implementation boundary.** This section freezes the first-party wire contract for [DEV-73](https://linear.app/gengyun/issue/DEV-73), to be implemented by its Server/iOS/QA children. It does **not** certify an existing database, reachable endpoint, authorized staging, public domain, or App Store listing. It reuses `PublicRecipeSnapshot.preview`, `RecipePublicCitation.eligibleURL` and the source-only `web/recipe-share/` consumer; no community feed, public profile, social graph, cross-app fingerprinting, or third-party photo publishing.

### Data ownership and trust

- The private Swift `Recipe` and Supabase `user_snapshots` remain owner-only. Anonymous Data API never receives SELECT permission to any private recipe, snapshot, sharing registry, or version-history table. Do **not** reconfigure historical `public.recipes` as an anonymous share store.
- An authenticated owner *submits* an independently sanitized public document, not a pointer that instructs the server to fetch arbitrary users' private Recipe data. Server identity comes exclusively from a verified Supabase Auth JWT, never an owner ID in the request. Each share row is bound to the verified `auth.uid()`; authenticated RLS enforces this for own-list, create, update and revoke. Public read is a dedicated GET-only Edge handler that rechecks the share state and returns only the allowlisted document. Server-only credentials never reach the iOS App, browser or QR.
- Sharing is unlisted and off by default, and requires an explicit owner action each time. `summaryAndSource` publishes only the permitted title, user-approved summary and safe source citation, with empty `ingredients` and `steps` arrays. `fullInstructions` requires affirmative `hasDistributionRights` attestation and explicit review of the exact exported text. This attestation is *not* independently verified copyright ownership; imported third-party materials must not be auto-promoted to full public text. No cover/step photos or remotely retrievable private attachment links in V1.
- `RecipeShareApproval.expectedUpdatedAt` is a **local** preflight guard checked by `PublicRecipeSnapshot.preview` immediately before confirmation and send. It is not Supabase library `revision`. The publish backend stores the client source ID/revision as **unverified lineage metadata**, not evidence that a private cloud record was current or owned. The server's authoritative optimistic concurrency token is a separate monotonic `shareVersion` on its own share row.

### Exact public payload

Successful visitor GET is JSON with **exactly** the eight properties below; no envelope, metadata, share ID, owner ID, source recipe ID, rights attestation, analytics token, private notes, email, local media path or unknown extra property. The JSON body must pass `validatePublicRecipe` in `web/recipe-share/src/page.mjs` and be produced by the Swift `PublicRecipeSnapshot` allowlist.

```json
{
  "title": "Lemon Pasta",
  "summary": "A bright weeknight pasta.",
  "sourceURL": "https://example.com/recipes/lemon-pasta",
  "servings": 2,
  "prepMinutes": 10,
  "cookMinutes": 12,
  "ingredients": [
    {"name": "Pasta", "amountText": "200 g"},
    {"name": "Lemon", "amountText": "1"}
  ],
  "steps": [
    {"title": "Cook pasta", "instruction": "Cook until al dente."},
    {"title": "Finish", "instruction": "Toss with lemon."}
  ]
}
```

Contract bounds: `title` is nonblank, max 180 Unicode characters; `summary` is a string up to 2,000; `sourceURL` is null or a public **HTTPS** URL passing server-side equivalent of `RecipePublicCitation.eligibleURL` (no userinfo, fragments, credential-bearing queries or private hosts); `servings` is null or integer 1–100; `prepMinutes` and `cookMinutes` are null or integers 0–10,080; `ingredients` has at most 200 entries, each `name` nonblank ≤180 and `amountText` ≤120; `steps` has at most 100 entries, each `title` ≤220 and nonblank `instruction` ≤6,000. If an item fails validation, **reject the publish**, never silently export a partial original text or substitute invented recipe facts. Text encoding is UTF-8 and the input body has a configured bounded byte limit (recommended at most 2 MiB; must also honor the Web reader's 2 MiB response limit). Date and version metadata do **not** belong in public JSON.

For `summaryAndSource`, the same JSON shape is returned with `ingredients: []` and `steps: []` regardless of what the owner's private Recipe contains. The existing public Web reader uses these arrays to decide which sections to show.

### HTTP routes and identity

Use two dedicated Supabase Edge Functions, not a broad public RPC or a common handler accidentally disabling JWT enforcement:

| Route (path relative to Supabase Edge base) | Authentication | Semantics |
| --- | --- | --- |
| `POST /functions/v1/recipe-share-manage` | Valid owner bearer JWT; gateway JWT verified | Create exactly one unlisted authorized share and return own metadata |
| `GET /functions/v1/recipe-share-manage` | Valid owner JWT | List *only this owner's* share metadata |
| `GET /functions/v1/recipe-share-manage/{shareID}` | Valid owner JWT | Read one owned share's metadata; not a public payload |
| `PUT /functions/v1/recipe-share-manage/{shareID}` | Valid owner JWT and current `If-Match` | Explicitly replace public document; increment shareVersion |
| `DELETE /functions/v1/recipe-share-manage/{shareID}` | Valid owner JWT | Revoke, destroy public payload, and invalidate slug; repeat is idempotent |
| `GET /functions/v1/recipe-share-public/{slug}` | No login; handler accepts GET only | Fetch current non-revoked **eight-field** snapshot, not list/search |
| `HEAD /functions/v1/recipe-share-public/{slug}` | No login | Same visibility/status/header decision, no body |

The **public** function has `verify_jwt=false` only because its handler explicitly limits methods and fields; the **management** function has `verify_jwt=true` and independently revalidates the authenticated user before any privileged database operation. Both default deny unsupported verbs. Implementer must verify Supabase deployment path rewriting and feature compatibility locally; if the runtime cannot reliably support route suffixes, expose an explicitly versioned equivalent and update this contract + existing Web client in the **same reviewed contract change**, not ad hoc per agent.

`web/recipe-share/src/server.mjs` already fetches `RECIPE_PALS_PUBLIC_RECIPE_API/<slug>`: configure that variable to the verified HTTPS *base* of `recipe-share-public`. Do not alter the Web loader or mint guest authentication tokens. The native/share poster URL is a **separate** verified first-party HTTPS `/r/{slug}` on the public Web host; it is never the raw Edge API URL. The real Web hostname is **TO VERIFY (DEV-50)**. All `example.com` hostnames here are reserved example values, **not deployed services**.

### Management JSON and concurrency

Create request (owner ID intentionally absent):

```json
{
  "idempotencyKey": "e8a3e5d3-38c7-4fd8-9580-999d75f787b2",
  "sourceRecipeID": "f3d04935-aed9-4086-aacc-83723db92d13",
  "sourceRecipeUpdatedAt": "2026-10-10T11:00:00Z",
  "scope": "fullInstructions",
  "hasDistributionRights": true,
  "snapshot": {
    "title": "Lemon Pasta",
    "summary": "A bright weeknight pasta.",
    "sourceURL": "https://example.com/recipes/lemon-pasta",
    "servings": 2,
    "prepMinutes": 10,
    "cookMinutes": 12,
    "ingredients": [{"name": "Pasta", "amountText": "200 g"}],
    "steps": [{"title": "Cook", "instruction": "Cook until al dente."}]
  }
}
```

Both `sourceRecipeID` and `sourceRecipeUpdatedAt` are client-provided lineage, not an authorization grant or a remote-CAS proof. Clients MUST call `preview(of:approvedBy:)` for the exact current local recipe revision, display the actual summary/full content and receive explicit consent before POST or PUT. On the wire encode dates as RFC 3339 UTC strings; do not rely on default Swift `JSONEncoder` Date numbers.

`201 Created` returns private management metadata with `shareID` (UUID), `slug` (cryptographically random 32 bytes → base64url ≈43 chars, no sequential ID), `shareVersion` (positive integer starting at 1), `scope`, `createdAt`, `updatedAt`, `revokedAt` (null while active), and `publicURL`. The latter is derived **server-side** from an owner-approved verified Web host (never request body), and must pass `RecipePublicShareURL.isValid`; if no real verified host is configured, **do not create or advertise a publicly accessible share** and return `503 service_unavailable`. No service-role keys or private stored source fields are returned. List/get-own may return the same metadata and the owner's already-approved public snapshot, only after verifying the caller owns the share.

- Idempotency key is a UUID unique per owner/create intent. Identical POST retry returns original metadata with `200 OK` and **same slug/version**; reusing the same key with different body returns `409 idempotency_conflict`. Replaying a key for a revoked share never republishes it.
- PUT supplies full new consented request fields (excluding a new create idempotency key) and `If-Match: "v1"` for current `shareVersion=1`. Success `200 OK` returns version 2 metadata; stale `If-Match` returns `409 revision_conflict` and **does not modify** stored content. Revoked shares cannot be updated in place or resurrected; a new explicit POST/key is required.
- DELETE is owner-only and **revoke wins** over any concurrent update. Success and repeated owner DELETE both return `204 No Content`; unknown or other-owner returns indistinguishable `404`. Mark revoked and make stored public payload inaccessible immediately at the source (prefer erasure/nulling of payload); all future guest reads return 404 even if an old client still knows slug.
- Validate mutable body field allowlist, content length, UUID/ISO timestamps, scope and rights. `summaryAndSource` must have empty arrays; `fullInstructions` requires `hasDistributionRights=true` and fresh explicit consent. Reject unknown fields, URLs, rights mismatch and over-limit payload rather than discarding them.
- Failure content type is `application/json` with a stable error code and generic message, e.g. `{"code":"revision_conflict","message":"This shared version changed. Refresh and confirm again."}`. Exact HTTP map: missing/invalid JWT 401; own rights or invalid payload 400/403 (do not disclose someone else's identity); unknown/other-owner share 404; stale update or idempotency payload mismatch 409; over-limit 413; rate limit 429; unavailable provider/config 503. `GET public` maps missing/hidden/revoked uniformly to 404 (or 410 if no enumeration risk is documented), never includes private identifiers or a user-readable reason.

### Storage, revocation and privacy

Suggested new isolated server-owned share table: `share_id, owner_id (auth.users ON DELETE CASCADE), opaque_slug UNIQUE, source_recipe_id (owner-provided reference only), source_client_updated_at, share_version, scope, has_distribution_rights, sanitized_snapshot JSONB, idempotency_key, created_at, updated_at, revoked_at`. Use a unique owner/idempotency index, CAS for updates, RLS with both `USING` and `WITH CHECK` owner guards for mutable rows, and **no anonymous direct-table grants**. Implementer chooses exact table/column names and tests them against local Supabase before the server PR; do not silently mutate existing `user_snapshots`, cloud CAS or old `public.recipes`. A privileged public-read Edge handler may query the isolated table only to emit a validated eight-field response; no list endpoint or direct Storage object URLs. See [DEV-50](https://linear.app/gengyun/issue/DEV-50) for an **approved isolated staging** and [DEV-49](https://linear.app/gengyun/issue/DEV-49) for release authorization.

Public API, Web/OG, and any first-party cache must emit `Cache-Control: private, no-store, max-age=0`, `X-Robots-Tag: noindex, nofollow` and not publish private media. If a reverse proxy/CDN cannot honor this, deployment stays blocked. After server-confirmed revoke/deletion, own JSON/page/OG endpoints return 404 without stale content. Previously copied screenshots, foreign crawlers, and third-party social preview caches **cannot be remotely erased with certainty**; product must not falsely promise third-party erasure.

An already-shared recipe cannot claim deletion/revoke completed while offline: native UI must confirm the server's revoke response **before** erasing the corresponding private local recipe; failure leaves the local recipe and public state explicit and retriable. Account deletion must revoke or cascade shares and must never leave guest-readable snapshots. Private edits do not auto-republish, and creating a new share requires explicit new consent.

### Contract verification vectors (mock tests are NOT deployment evidence)

| Scenario | Expected |
| --- | --- |
| Never-published recipe, anonymous slug guess, revoked slug, other-owner share ID | Guest 404; other-owner management 404; zero leaked fields |
| Owner A POST full instructions with attestation and complete allowed snapshot | 201 + random slug/version 1; guest 200 with **exact** eight fields |
| Same owner/idempotencyKey/body retried; same key with changed body | 200 same slug/version; changed body 409, never duplicate |
| Owner A PUT current If-Match followed by stale PUT | First 200 version increments, second 409 with unchanged snapshot |
| Owner B attempts GET/PUT/DELETE A's ID | 404 and no mutation; ordinary user cannot read private recipe tables |
| Full instructions without rights, summary mode with nonempty arrays, private URL, extra ownerID/email, oversized body | Reject 400/403/413; no public row or data |
| Owner DELETE then repeated DELETE, guest read, update after revoke | 204/204, guest 404, update 404/409; no stale SSR/OG body |
| Client edits private recipe after prior publish | Guest sees previous approved snapshot until new owner-confirmed PUT |
| Local share deletion offline or Edge unavailable | Native UI does not say revoked; preserves private record for retry |
| Real host unknown, Web API unavailable | Publish 503 (no fake public URL); existing SSR reader reports 503 |

Verify schema examples with a JSON parser; use existing `swift test --package-path ios/RecipeCore` and `cd web/recipe-share && npm test` whenever a complete checkout is available. Add backend role/RLS, race, retry and cache tests in the **server implementation task**; run A/B/anonymous signed staging only when [DEV-50](https://linear.app/gengyun/issue/DEV-50) authorizes it. Record CODE/STAGING/DEVICE/PRODUCTION separately in Linear; this document itself proves none of those runtime gates.


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

## QR poster building block — 2026-10-10 (not published yet)

`RecipeSharePosterRenderer` can render an opt-in, rights-filtered `PublicRecipeSnapshot` into 1080×1920/1080×2400 native SwiftUI graphics using Core Image QR with error correction H and a white quiet zone. The source URL must pass `RecipePublicShareURL.isValid`: external HTTPS domain and opaque `/r/<slug>` path, with no credentials. Photos require independent rights confirmation. User sharing buttons remain unavailable until #242/243 issue a real, revocable public URL; staging/real-device export and QR-decoding checks still belong to #244/#250/#251. Do not publish guessed screenshots or source-site media.

## Source-only Web visitor implementation (2026-10-10)

A small dependency-free SSR reader has been added under `web/recipe-share/`. With an injected mock public snapshot, Node tests verify HTML escaping, strict private-field rejection, guest readability, revoked-share unavailability, and no fake App Store CTA. Without the server-supplied authorized public API, it returns 503. `noindex`, CSP and no-store headers are default. This component **does not deploy** a Web domain, share database, revocation service, OG asset hosting, App Store listing or Universal Links. See #242/#243/#250/#251 for real-staging and launch gates.

## Optional referral-code validation module (2026-10-10, source only)

`web/recipe-share/src/referrals.mjs` now defines first-party anonymous aggregate-event validation and an **explicitly consented pending invitation-claim contract**. It rejects caller-supplied email/IP/UA/device data, unrecognized events, short/malformed tokens, forged/not-yet-verified inviter codes, self-referrals and repeated claims. It does not identify a person from an App Store click, issue codes, persist event counters, collect cookies or grant any reward. A future authenticated backend must verify inviter ownership and expiry, dedupe rate-limited server-side events, secure claims with RLS and a data-retention policy. Do not enable tracking before local/privacy-staging verification (#245/#250) or payouts before a separate user decision (#246).
