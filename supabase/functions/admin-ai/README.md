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
ciphertext, nonce, and key version. Edits that change the single UI model or
provider enabled state are rejected because the database also has multi-model
and route relationships.

Provider deletion is rejected when a secret, model, provider-health record, or
usage event is attached. This prevents secret/cascade loss and history rows from
losing their provider reference. `ai_usage_events` is read with only live
columns; cached-input tokens remain `null` because production has no such
column. No schema, migration, `_shared` module, production data, or secret is
changed by this function.

Provider probes require a caller-supplied key, public HTTPS host, default port,
public DNS answers pinned to the connection, no redirects, and an eight-second
timeout. The response body is discarded. No provider probe writes health state.
