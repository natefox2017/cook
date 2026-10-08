# RecipePouch Share Extension (V1 URL/Text)

The native `RecipeShare` extension is embedded in the `Recipe` iOS app. It is offered in the iOS Share Sheet for **URL or plain text** from apps such as Safari and Notes. Image/video/file activation is **not yet enabled**, because that would advertise payloads the current extension cannot safely ingest.

## Lifecycle and durable receipt

1. `ShareViewController` reads `NSExtensionContext` item providers (URL first, then plain text), or a host's attributed text.
2. `RecipeShareInbox` writes the UTF-8 source into an App Group file using atomic write, flush and an exclusive hard-link, then saves a versioned receipt in a different file. A deterministic source hash provides the receipt ID and client request ID, so identical concurrent shares never overwrite an array or create extra local receipts.
3. Only **after the file receipt is committed** does the extension call `completeRequest`; a failure leaves a Retry/Cancel screen without claiming success.
4. The main app reloads pending receipts on startup/foreground. Recipes displays their count and original source text. Legacy `recipe.shareInbox`/`cook.shareInbox` arrays are migrated before those keys are removed.
5. `received` here means **saved locally on the device**. It does **not** imply an authenticated server job, durable queue insertion, recipe parse, or cloud sync. **No backend ACK is generated yet.** Future #31 work must POST with the active user's JWT and call `acknowledge(receipt,jobID,ownerID:)` only after a durable server job response. ACK files are keyed by both receipt and authenticated owner; `pendingReceipts(for:)` does not hide account B's source after account A submits it, and `acknowledgedJobID(for:ownerID:)` preserves the confirmed remote job ID for later polling after a restart. The main app re-filters receipts on authentication changes. **This only hardens the handoff storage; no server submission or polling is wired yet.**

Unacknowledged receipts survive host cancellation, extension process exit, app restart, offline state and sign-out; they are not assigned to an account until the owner explicitly submits through a logged-in main app session.

## Apple Developer signing still required

The host and extension must be signed by the **same Apple Developer Team** with the App Group `group.com.modelhub.cook` provisioned to **both** App IDs:

- Host: `com.modelhub.cook`, `ios/Recipe/Recipe.entitlements`
- Extension: `com.modelhub.cook.ShareExtension`, `ios/ShareExtension/ShareExtension.entitlements`

`DEVELOPMENT_TEAM` in the checked-in Xcode project is intentionally blank. A non-signing simulator build is **not** evidence of a working App Group on a device. Validate signing, profiles, app-group container and .appex installation on the actual developer account before release.

Relevant Apple references:
- https://developer.apple.com/documentation/xcode/configuring-app-groups
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionprincipalclass
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html

## Native acceptance checklist (#30 / #34)

```sh
xcodebuild -list -project ios/Recipe.xcodeproj
xcodebuild -project ios/Recipe.xcodeproj -scheme Recipe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO build
swift test --package-path ios/RecipeCore
```

On a **signed iPhone install**:
- Verify the `RecipeShare.appex` is embedded and RecipePouch appears in Safari Share Sheet and Notes Share Sheet.
- Share HTTPS links/text; return to source app promptly, then open RecipePouch and confirm the pending source/duplicate count.
- Force-quit the host app before sharing, reboot, go offline, share twice or rapidly in parallel; pending receipts and original text must remain available.
- Confirm unsupported images and attachments do not falsely claim a saved recipe and that Retry/Cancel returns to the host.
- Confirm login/logout does not silently attach receipts to another user, and that real backend job ACK/queue/recipe stages remain explicitly **not implemented until #31**.
- Include device, OS, commit, language (English default), App Group provisioning and actual status. Do not infer success from CI compatibility check.

Remaining: real signed host tests, authenticated backend submission/ACK, media imports, file-retention cleanup after cloud acknowledgement, and local-delete coordination with #18/#66. Do not close #30 or #34 without those results.
