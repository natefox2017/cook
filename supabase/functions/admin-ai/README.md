# Admin AI Edge Function

This is a replacement implementation based on the current `admin/src/api.ts`,
`admin/src/types.ts`, `admin/src/pages/LLMPage.tsx`, and the read-only live
database catalog captured in
`supabase/ISSUE_155_EDGE_FUNCTION_SOURCE_MANIFEST.md`. It is not recovered
source and does not claim deployed bundle SHA parity.

The handler supports owner/admin sessions, provider listing, safe usage
aggregation, one-time HTTPS provider probes, and limited provider metadata
updates. Provider secrets are never selected, returned, or logged. A supplied
key for create/update is rejected because the old encryption format and key
custody cannot be recovered. Testing an existing saved key is unavailable for
the same reason. Empty-key edits preserve `secret_ref` and the existing secret
ciphertext, nonce, and key version. The provider name, base URL, and enabled
state can be updated on the provider row. Model changes remain rejected because
the UI's single model field cannot safely update the live multi-model and route
relationships.

Provider deletion always returns 409 before creating a service-role client.
Count-then-delete checks have a race with concurrent inserts, while the live
foreign keys can cascade models and health rows or detach usage and route
references. Disable a provider with `active: false` until an approved atomic
history guard exists. `ai_usage_events` is read with only live columns;
cached-input tokens remain `null` because production has no such column. No
schema, migration, `_shared` module, production data, or secret is changed by
this function.

## Secret protocol status

The live catalog has `ai_secrets`, with unique `secret_ref`, opaque `ciphertext`
and `nonce` text columns, and integer `key_version` defaulting to 1. It does not
have `ai_provider_secrets`. The deployed wrapper names `COOKAPP_AI_MASTER_KEY`,
but its implementation source is unavailable, so its key encoding/derivation,
ciphertext and nonce encoding, authentication tag layout, AAD, key-version
meaning, and rotation rules are unknown. The import worker's OCR key is a
separate function environment variable. The repository AES-GCM helper is for
admin TOTP and uses different storage and key custody; it must not be reused for
provider keys.

The following is a proposed, unapproved v2 contract, not deployed behavior:

- Keep using `ai_secrets`; do not create a parallel secret table.
- Use a separate function secret `COOKAPP_AI_SECRET_KEY_V2` containing a
  base64url-encoded 32-byte key. Decode it to the 256-bit AES key.
- Encrypt with WebCrypto AES-256-GCM, a fresh random 12-byte nonce encoded as
  base64url, and AAD `ai-secrets:v2:${secret_ref}`. Store the base64url
  WebCrypto ciphertext including its authentication tag in `ciphertext`, the
  nonce in `nonce`, and `key_version = 2`.
- Decrypt v2 only. Preserve v1 rows byte-for-byte and return an explicit
  unsupported-version error for v1 until the original source and key protocol
  are recovered. Do not infer or convert the wrapper's `COOKAPP_AI_MASTER_KEY`
  format.
- Create or rotate a key inside one database transaction: insert the new
  `ai_secrets` row and update the provider's `secret_ref` atomically. Retain the
  prior secret row unless a separate cleanup operation proves it is unreferenced
  and is authorized.
- Provider plus initial model creation also needs an atomic database operation
  and a frozen mapping for existing route/fallback behavior before enabling
  create or model updates.
- Keep deletion disabled unless an approved database function performs the
  reference checks and delete under transaction locks, including route primary
  and fallback references, usage, models, health, and secret references.

Freeze and review this protocol and its database transaction contract before
implementing saved-key writes or probes. No production key presence or value was
queried.

Provider probes require a caller-supplied key, public HTTPS host, default port,
public DNS answers pinned to the connection, no redirects, and an eight-second
timeout. The response body is discarded. No provider probe writes health state.
