# RecipePouch Share Extension (V1 URL/Text)

The native `RecipeShare` extension is embedded in the `Recipe` iOS app. It is offered in the iOS Share Sheet for **URL or plain text** from apps such as Safari and Notes. Image/video/file activation is **not yet enabled**, because that would advertise payloads the current extension cannot safely ingest.

## Lifecycle and durable receipt

1. `ShareViewController` reads `NSExtensionContext` item providers (URL first, then plain text), or a host's attributed text.
2. `RecipeShareInbox` writes the UTF-8 source into an App Group file using atomic write, flush and an exclusive hard-link, then saves a versioned receipt in a different file. A deterministic source hash provides the receipt ID and client request ID, so identical concurrent shares never overwrite an array or create extra local receipts.
3. Only **after the file receipt is committed** does the extension call `completeRequest`; a failure leaves a Retry/Cancel screen without claiming success.
4. The main app reloads pending receipts on startup/foreground. Recipes displays their count and original source text. Legacy `recipe.shareInbox`/`cook.shareInbox` arrays are migrated before those keys are removed.
5. Local `received` still means **saved on this iPhone**. The main app submits the same `client_request_id` with the active user's session. API `received` means only that the server persisted a job row, so its job ID is saved in a separate owner-scoped checkpoint and the local receipt stays pending. The app writes the owner-scoped ACK only after `queue_confirmed_at` proves durable queue admission. ACKs retain the job ID for startup/foreground recovery; job status is polled every five seconds for up to one minute while the app is active, and recoverable failures use the API's idempotent retry route. `completed`/`recipe_status` remain server parse states and do not imply that a local RecipeStore write occurred.

6. The client uses the frozen `docs/schemas/import-v1.openapi.json` and `import-v1.schema.json` contract: authenticated `POST /recipe-imports`, owner-scoped `GET /recipe-imports/{job_id}`, and `POST /recipe-imports/{job_id}/retry`. Submission retries reuse the receipt's original `client_request_id`; no second job API is introduced. The backend deployment and real authenticated handoff have not been verified.

7. The current response has a `RecipeResult` with field/evidence records, not a client `Recipe` snapshot or the local model's user-edit precedence metadata. The app therefore does not upsert the result into `RecipeStore`; this prevents duplicate recipes and silent replacement of local edits until a lossless mapping contract is available.

Unacknowledged receipts survive host cancellation, extension process exit, app restart, offline state and sign-out; they are not assigned to an account until the owner explicitly submits through a logged-in main app session.

## Apple Developer signing still required

The host and extension must be signed by the **same Apple Developer Team** with the App Group `group.com.shopkivoo.recipe` provisioned to **both** App IDs:

- Host: `com.shopkivoo.recipe`, `ios/Recipe/Recipe.entitlements`
- Extension: `com.shopkivoo.recipe.ShareExtension`, `ios/ShareExtension/ShareExtension.entitlements`

The new App IDs and App Group must be registered and provisioned in the Apple Developer account before signing. Changing the App Group identifier does not migrate files or defaults from the old `group.com.modelhub.cook` container.

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
- Confirm login/logout does not silently attach receipts to another user. Verify local receipt, server `received`, server `queued`, and parse completion as separate states.
- Include device, OS, commit, language (English default), App Group provisioning and actual status. Do not infer success from CI compatibility check.

Remaining: real signed Safari/Notes host tests, production App Group provisioning, authenticated handoff against a deployed API, client mapping of RecipeResult into RecipeStore with edit precedence, media imports, and a reviewed retention policy for source files after ACK. Do not close #30 or #34 without those results.
