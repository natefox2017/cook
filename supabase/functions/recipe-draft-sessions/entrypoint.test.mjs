// Developer: gengyun
// Purpose: Exercise the deployable draft session entry boundary: fail-closed config, cross-owner masking, and bounded timeout.

import test from "node:test";
import assert from "node:assert/strict";
import { createRecipeDraftBackendAdapter } from "./backendAdapter.ts";
import { handleRequest } from "./handler.ts";

const id = (n) =>
  `${n.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`;
const owner = id(1);
const other = id(2);
const jobID = id(3);
const sessionID = id(4);
const key = id(5);
const evidenceID = id(6);
const hash = "a".repeat(64);

const json = (value, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });

const base = () => ({
  status: "needs_review",
  fields: {
    title: {
      raw_value: null,
      evidence_ids: [evidenceID],
      user_confirmed: false,
      origin: "extracted",
    },
  },
  evidence: [{ id: evidenceID, excerpt: "Soup from the source" }],
  review_fields: ["title"],
});

// Mirrors what index.ts wires: a closed-by-default backend adapter whose
// enabled flag comes from server configuration and whose transport is the only
// network boundary.
function entrypoint(overrides = {}) {
  const calls = [];
  const adapter = createRecipeDraftBackendAdapter({
    enabled: true,
    supabaseRESTBaseURL: new URL("https://synthetic.invalid/rest/v1"),
    serviceRoleKey: "synthetic-service",
    encodedAISecretKey: "synthetic-key",
    authenticate: async () => ({ user: { id: owner, is_anonymous: false } }),
    decryptAISecret: async () => "synthetic-plaintext",
    postgrestTransport: async (request) => {
      calls.push(request);
      return json([]);
    },
    ...overrides,
  });
  return { calls, ...adapter };
}

const createRequest = () =>
  new Request("https://synthetic.invalid/recipe-draft-sessions", {
    method: "POST",
    headers: { authorization: "Bearer signed-synthetic" },
    body: JSON.stringify({ job_id: jobID, client_request_id: key }),
  });

const sessionRequest = () =>
  new Request(`https://synthetic.invalid/recipe-draft-sessions/${sessionID}`, {
    method: "GET",
    headers: { authorization: "Bearer signed-synthetic" },
  });

test("no configuration fails closed without any transport or provider access", async () => {
  const e = entrypoint({ enabled: false });
  assert.equal(await e.handlerDependencies.isEnabled(), false);
  assert.equal(
    await e.handlerDependencies.verifiedOwner(
      new Request("https://synthetic.invalid"),
    ),
    null,
  );
  const response = await handleRequest(createRequest(), e.handlerDependencies);
  assert.equal(e.calls.length, 0, "transport must never be called");
  assert.equal(response.status, 401, "auth closes before the disabled gate");
});

test("cross-owner session read is masked as 404 with owner predicate applied", async () => {
  const e = entrypoint();
  const response = await handleRequest(sessionRequest(), e.handlerDependencies);
  assert.equal(response.status, 404);
  assert.equal(e.calls.length, 1, "exactly one owned session read");
  const url = new URL(e.calls[0].url);
  const query = decodeURIComponent(url.search);
  assert.match(query, /owner_id=eq\."00000001-0000-4000-8000-000000000000"/);
});

test("bounded transport timeout returns a deterministic error instead of hanging", async () => {
  const e = entrypoint({
    requestTimeoutMs: 5,
    postgrestTransport: () => new Promise(() => {}),
  });
  const response = await handleRequest(createRequest(), e.handlerDependencies);
  assert.equal(response.status, 500);
  const body = await response.json();
  assert.equal(body.code, "INTERNAL_ERROR");
  assert.equal(typeof body.request_id, "string");
});

test("configured entry routes a completed job through create to 201", async () => {
  const e = entrypoint({
    postgrestTransport: async (request) => {
      e.calls.push(request);
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname.endsWith("/recipe_draft_sessions")) {
        return json([]);
      }
      if (request.method === "GET" && url.pathname.endsWith("/recipe_import_jobs")) {
        return json([{
          id: jobID,
          owner_id: owner,
          status: "completed",
          source_fingerprint: "source:immutable",
          result: base(),
        }]);
      }
      if (request.method === "POST" && url.pathname.endsWith("/rpc/create_recipe_draft_session")) {
        return json({
          outcome: "created",
          session: {
            id: sessionID,
            owner_id: owner,
            job_id: jobID,
            client_request_id: key,
            source_fingerprint: "source:immutable",
            base_context: base(),
            base_context_hash: hash,
            effective_context: base(),
            effective_context_hash: hash,
            overlay: {},
            revision: "1",
            reserved_tokens: 0,
            settled_tokens: 0,
            dispatch_count: 0,
          },
        });
      }
      return json([]);
    },
  });
  const response = await handleRequest(createRequest(), e.handlerDependencies);
  assert.equal(response.status, 201);
  const body = await response.json();
  assert.equal(body.session_id, sessionID);
  assert.equal(body.job_id, jobID);
  assert.equal(body.revision, "1");
  assert.equal(body.budget.reserved_tokens, 0);
  assert.equal(body.budget.settled_tokens, 0);
  assert.equal(e.calls.length, 3, "creation-key read, job read, then create RPC");
});
