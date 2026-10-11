// Developer: gengyun
// Purpose: Exercise fixed offline backend requests and full numeric PostgreSQL CAS preservation.
import test from "node:test";
import assert from "node:assert/strict";
import { createRecipeDraftBackendAdapter } from "./backendAdapter.ts";
import { handleRequest } from "./handler.ts";
const id = (n) =>
  `${n.toString(16).padStart(8, "0")}-0000-0000-0000-000000000000`;
const owner = id(1),
  job = id(2),
  sessionID = id(3),
  requestID = id(4),
  modelID = id(5),
  providerID = id(6),
  hash = "a".repeat(64);
const raw = (text) =>
  new Response(text, { headers: { "content-type": "application/json" } });
const response = (value) => raw(JSON.stringify(value));
const resultText =
  '{"metadata":[9007199254740993,9223372036854775807,1.234567890123456789,1e400,-0,-9223372036854775808,{"nested":42,"quoted":"9007199254740993","rawJSON":"9007199254740993"},true,null],"status":"needs_review"}';
const row = () => ({
  id: sessionID,
  owner_id: owner,
  job_id: job,
  client_request_id: requestID,
  revision: "9223372036854775807",
  reserved_tokens: 0,
  settled_tokens: 0,
  dispatch_count: 0,
  effective_context: { status: "needs_review" },
  effective_context_hash: hash,
});
function fixture(extra = {}) {
  const calls = [];
  const options = {
    enabled: true,
    supabaseRESTBaseURL: new URL("https://synthetic.invalid/rest/v1"),
    serviceRoleKey: "synthetic-service",
    encodedAISecretKey: "synthetic-key",
    authenticate: async () => ({ user: { id: owner, is_anonymous: false } }),
    decryptAISecret: async () => "synthetic-plaintext",
    postgrestTransport: async (req, policy) => {
      calls.push({ req, policy });
      return response([]);
    },
    ...extra,
  };
  return { options, calls, ...createRecipeDraftBackendAdapter(options) };
}
const createArgs = (snapshot) => ({
  p_owner_id: owner,
  p_client_request_id: requestID,
  p_job_id: job,
  p_expected_job_result: snapshot,
  p_base_context: { status: "needs_review" },
  p_base_context_hash: hash,
  p_enabled: true,
});
const finishArgs = () => ({
  p_owner_id: owner,
  p_session_id: sessionID,
  p_request_id: requestID,
  p_fencing_token: id(7),
  p_result: { status: "no_review_needed" },
  p_validated_usage: null,
  p_expected_dispatch_state: "dispatched_unknown",
});

test("default and invalid factories are closed without Auth, storage, or secrets", async () => {
  for (
    const overrides of [
      { enabled: false },
      { supabaseRESTBaseURL: new URL("http://synthetic.invalid/rest/v1") },
      { supabaseRESTBaseURL: new URL("https://u@synthetic.invalid/rest/v1") },
      { requestTimeoutMs: 0 },
      { postgrestTransport: undefined },
    ]
  ) {
    let calls = 0;
    const f = fixture({
      ...overrides,
      authenticate: async () => {
        calls++;
        throw Error();
      },
      decryptAISecret: async () => {
        calls++;
        throw Error();
      },
    });
    assert.equal(f.handlerDependencies.isEnabled(), false);
    assert.equal(
      await f.handlerDependencies.verifiedOwner(
        new Request("https://synthetic.invalid"),
      ),
      null,
    );
    await assert.rejects(f.handlerDependencies.loadOwnedJob(owner, job));
    assert.equal(calls, 0);
    assert.equal(f.calls.length, 0);
  }
  assert.equal(
    createRecipeDraftBackendAdapter().handlerDependencies.isEnabled(),
    false,
  );
});
test("missing native rawJSON capability fails closed without fallback", () => {
  const original = JSON.rawJSON;
  try {
    JSON.rawJSON = undefined;
    assert.equal(fixture().handlerDependencies.isEnabled(), false);
  } finally {
    JSON.rawJSON = original;
  }
});

test("verified Auth must return explicitly non-anonymous lowercase owner", async () => {
  for (
    const user of [
      { id: owner, is_anonymous: false },
      { id: owner, is_anonymous: true },
      { id: owner },
      { id: owner.replace("00000001", "ABCDEFAB"), is_anonymous: false },
      { id: "no", is_anonymous: false },
    ]
  ) {
    const f = fixture({ authenticate: async () => ({ user }) });
    assert.deepEqual(
      await f.handlerDependencies.verifiedOwner(
        new Request("https://synthetic.invalid"),
      ),
      user.id === owner && user.is_anonymous === false
        ? { id: owner, isAnonymous: false }
        : null,
    );
    assert.equal(f.calls.length, 0);
  }
});
test("Auth timeout and late result fail closed", async () => {
  let release;
  const f = fixture({
    requestTimeoutMs: 5,
    authenticate: () => new Promise((r) => release = r),
  });
  assert.equal(
    await f.handlerDependencies.verifiedOwner(
      new Request("https://synthetic.invalid"),
    ),
    null,
  );
  release({ user: { id: owner, is_anonymous: false } });
  await Promise.resolve();
});
test("fixed job query preserves complete numeric literals into original RPC body", async () => {
  let body;
  const f = fixture({
    postgrestTransport: async (req) => {
      f.calls.push({ req });
      if (req.method === "GET") {
        return raw(
          `[{"id":"${job}","owner_id":"${owner}","status":"completed","source_fingerprint":"x","result":${resultText}}]`,
        );
      }
      body = await req.text();
      return response({ code: "STALE_REVISION" });
    },
  });
  const j = await f.handlerDependencies.loadOwnedJob(owner, job);
  assert.equal(JSON.stringify(j.result), resultText);
  assert(Object.isFrozen(j.result));
  assert.throws(() => structuredClone(j.result));
  await f.handlerDependencies.rpc(
    "create_recipe_draft_session",
    createArgs(j.result),
  );
  assert(body.includes(`"p_expected_job_result":${resultText}`));
  const req = f.calls[0].req, u = new URL(req.url);
  assert.equal(u.pathname, "/rest/v1/recipe_import_jobs");
  assert.equal(u.searchParams.get("owner_id"), `eq."${owner}"`);
  assert.equal(u.searchParams.get("id"), `eq."${job}"`);
  assert.equal(u.searchParams.get("limit"), "2");
  assert.equal(req.redirect, "error");
  assert.equal(req.headers.get("authorization"), "Bearer synthetic-service");
  await assert.rejects(
    f.handlerDependencies.rpc(
      "create_recipe_draft_session",
      createArgs(JSON.parse(resultText)),
    ),
  );
  await assert.rejects(
    f.handlerDependencies.rpc("create_recipe_draft_session", {
      ...createArgs(j.result),
      p_job_id: id(8),
    }),
  );
});
test("all owned read predicates and revision casts are explicit", async () => {
  const f = fixture();
  const d = f.handlerDependencies;
  await d.loadOwnedSession(owner, sessionID);
  await d.loadOwnedSessionByCreationKey(owner, requestID);
  await d.loadOwnedTurn(owner, sessionID, requestID);
  await d.loadOwnedApprovalForTurn(owner, sessionID, requestID);
  for (const { req } of f.calls) {
    assert.equal(
      new URL(req.url).searchParams.get("owner_id"),
      `eq."${owner}"`,
    );
  }
  assert(
    new URL(f.calls[0].req.url).searchParams.get("select").includes(
      "revision::text",
    ),
  );
  assert(
    new URL(f.calls[2].req.url).searchParams.get("select").includes(
      "based_revision::text",
    ),
  );
  assert(
    new URL(f.calls[3].req.url).searchParams.get("select").includes(
      "applied_revision::text",
    ),
  );
});
test("foreign, duplicate, malformed rows are rejected and valid counters normalized", async () => {
  for (
    const rows of [[{ ...row(), owner_id: id(9) }], [row(), row()], [{
      ...row(),
      revision: 2,
    }]]
  ) {
    const f = fixture({ postgrestTransport: async () => response(rows) });
    await assert.rejects(
      f.handlerDependencies.loadOwnedSession(owner, sessionID),
    );
  }
  const f = fixture({ postgrestTransport: async () => response([row()]) });
  const s = await f.handlerDependencies.loadOwnedSession(owner, sessionID);
  assert.equal(s.revision, "9223372036854775807");
  assert.equal(s.reserved_tokens, 0);
  assert.doesNotThrow(() => structuredClone(s));
  for (const numeric of ["1.00000000000000000001", "1e0", "32769", "-1"]) {
    const f = fixture({
      postgrestTransport: async () =>
        raw(
          JSON.stringify([row()]).replace(
            '"reserved_tokens":0',
            `"reserved_tokens":${numeric}`,
          ),
        ),
    });
    await assert.rejects(
      f.handlerDependencies.loadOwnedSession(owner, sessionID),
    );
  }
});
test("RPC allowlist exact parameters and plain payload shapes reject before transport", async () => {
  const f = fixture();
  await assert.rejects(f.handlerDependencies.rpc("evil", {}));
  for (
    const args of [
      { ...finishArgs(), extra: true },
      { ...finishArgs(), p_result: [] },
      { ...finishArgs(), p_result: { n: NaN } },
      { ...finishArgs(), p_expected_dispatch_state: "other" },
      { ...finishArgs(), p_validated_usage: 4097 },
    ]
  ) {
    await assert.rejects(
      f.handlerDependencies.rpc("finish_recipe_draft_turn", args),
    );
  }
  const approval = {
    p_owner_id: owner,
    p_session_id: sessionID,
    p_turn_request_id: requestID,
    p_request_id: id(8),
    p_expected_revision: "1",
    p_action: "accept",
    p_selected_paths: ["title"],
    p_approval_hash: hash,
    p_next_context: {},
    p_next_context_hash: hash,
    p_enabled: true,
  };
  for (
    const delta of [
      { p_selected_paths: [] },
      { p_selected_paths: ["title", "title"] },
      { p_selected_paths: ["secret"] },
      { p_action: "reject" },
      { p_next_context: [] },
    ]
  ) {
    await assert.rejects(
      f.handlerDependencies.rpc("approve_recipe_draft_turn", {
        ...approval,
        ...delta,
      }),
    );
  }
  assert.equal(f.calls.length, 0);
});
test("RPC valid safe results retain decimal revisions and discard incidental error data", async () => {
  const f = fixture({
    postgrestTransport: async () =>
      response({ outcome: "replay", session: row() }),
  });
  const value = await f.handlerDependencies.rpc("recover_recipe_draft_turn", {
    p_owner_id: owner,
    p_session_id: sessionID,
    p_request_id: requestID,
    p_enabled: true,
  });
  assert.equal(value.session.revision, "9223372036854775807");
  const e = fixture({
    postgrestTransport: async () =>
      response({ code: "NOT_FOUND", message: "private" }),
  });
  assert.deepEqual(
    await e.workerDependencies.storage("recover_recipe_draft_turn", {
      p_owner_id: owner,
      p_session_id: sessionID,
      p_request_id: requestID,
      p_enabled: true,
    }, { signal: new AbortController().signal }),
    { code: "NOT_FOUND" },
  );
});
function registry(req, reference = 'configured\\"ref') {
  const table = new URL(req.url).pathname.split("/").at(-1);
  if (table === "ai_routes") {
    return response([{
      route_key: "recipe_import_draft_v1",
      primary_model_id: modelID,
      enabled: true,
      timeout_ms: 10000,
      max_retries: 0,
      max_output_tokens: 1000,
      temperature: null,
    }]);
  }
  if (table === "ai_models") {
    return response([{
      id: modelID,
      provider_id: providerID,
      upstream_model_id: "synthetic",
      display_name: "Synthetic",
      enabled: true,
    }]);
  }
  if (table === "ai_providers") {
    return response([{
      id: providerID,
      name: "Synthetic",
      base_url: "https://synthetic.invalid/v1",
      secret_ref: reference,
      enabled: true,
    }]);
  }
  return response([{
    secret_ref: reference,
    ciphertext: "synthetic-ciphertext",
    nonce: "synthetic-nonce",
    key_version: 2,
  }]);
}
test("route model provider binding, nullable temperature and fresh secret authorization", async () => {
  let reference = 'configured\\"ref', decrypts = 0;
  const f = fixture({
    postgrestTransport: async (req) => {
      f.calls.push({ req });
      return registry(req, reference);
    },
    decryptAISecret: async (secret, key) => {
      decrypts++;
      assert.equal(secret.secret_ref, reference);
      assert.equal(key, "synthetic-key");
      return "synthetic-clear";
    },
  });
  const signal = new AbortController().signal;
  const config = await f.workerDependencies.loadRouteConfiguration(signal);
  assert.equal(config.route.temperature, null);
  assert.equal(config.route.max_retries, 0);
  assert.equal(
    await f.workerDependencies.resolveSecret(reference, signal),
    "synthetic-clear",
  );
  const secretReq = f.calls.at(-1).req;
  assert.equal(
    new URL(secretReq.url).searchParams.get("secret_ref"),
    'eq."configured\\\\\\"ref"',
  );
  reference = "new-ref";
  await assert.rejects(
    f.workerDependencies.resolveSecret('configured\\"ref', signal),
  );
  assert.equal(decrypts, 1);
  assert.equal(
    f.calls.filter((c) => new URL(c.req.url).pathname.endsWith("ai_routes"))
      .length,
    3,
  );
  for (
    const { req } of f.calls.filter((c) =>
      !new URL(c.req.url).pathname.endsWith("ai_secrets")
    )
  ) assert.equal(new URL(req.url).searchParams.get("enabled"), "eq.true");
});
test("disabled registry, mismatched chain and fractional key version fail closed", async () => {
  for (
    const mutate of [
      (r) => r.replace('"enabled":true', '"enabled":false'),
      (r) => r.replace('"id":"' + modelID, '"id":"' + id(9)),
    ]
  ) {
    const f = fixture({
      postgrestTransport: async (req) =>
        raw(mutate(await registry(req).text())),
    });
    await assert.rejects(
      f.workerDependencies.resolveSecret(
        'configured\\"ref',
        new AbortController().signal,
      ),
    );
  }
  const f = fixture({
    postgrestTransport: async (req) =>
      raw(
        (await registry(req).text()).replace(
          '"key_version":2',
          '"key_version":2.000000000000000000001',
        ),
      ),
  });
  await assert.rejects(
    f.workerDependencies.resolveSecret(
      'configured\\"ref',
      new AbortController().signal,
    ),
  );
});
test("non-JSON, oversized, UTF8-invalid, redirected and error bodies reject with cleanup", async () => {
  let canceled = 0;
  const bad = () =>
    new ReadableStream({
      cancel() {
        canceled++;
      },
    });
  for (
    const init of [
      { status: 503, headers: { "content-type": "application/json" } },
      { headers: { "content-type": "text/plain" } },
      {
        headers: {
          "content-type": "application/json",
          "content-length": "4194305",
        },
      },
    ]
  ) {
    const f = fixture({
      postgrestTransport: async () => new Response(bad(), init),
    });
    await assert.rejects(f.handlerDependencies.loadOwnedJob(owner, job));
  }
  assert.equal(canceled, 3);
  for (
    const bytes of [
      new Uint8Array([255]),
      new TextEncoder().encode("not-json"),
      new Uint8Array(4194305),
    ]
  ) {
    const f = fixture({
      postgrestTransport: async () =>
        new Response(bytes, {
          headers: { "content-type": "application/json" },
        }),
    });
    await assert.rejects(f.handlerDependencies.loadOwnedJob(owner, job));
  }
});
test("outer cancellation and ignored abort late response cleanup", async () => {
  let release, canceled = 0;
  const f = fixture({
    postgrestTransport: () => new Promise((r) => release = r),
  });
  const controller = new AbortController();
  const pending = f.workerDependencies.loadRouteConfiguration(
    controller.signal,
  );
  await new Promise((r) => setTimeout(r, 0));
  controller.abort();
  await assert.rejects(pending);
  release(
    new Response(
      new ReadableStream({
        cancel() {
          canceled++;
        },
      }),
      { headers: { "content-type": "application/json" } },
    ),
  );
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(canceled, 1);
});
test("monotonic deadline rejects a synchronously late Auth result even before timer fires", async () => {
  const f = fixture({
    requestTimeoutMs: 2,
    authenticate: async () => {
      const until = performance.now() + 10;
      while (performance.now() < until) {}
      return { user: { id: owner, is_anonymous: false } };
    },
  });
  assert.equal(
    await f.handlerDependencies.verifiedOwner(
      new Request("https://synthetic.invalid"),
    ),
    null,
  );
});

test("deadline before delayed request construction forbids late transport", async () => {
  const OriginalRequest = globalThis.Request;
  const f = fixture({ requestTimeoutMs: 2 });
  try {
    globalThis.Request = class extends OriginalRequest {
      constructor(...args) {
        super(...args);
        const until = performance.now() + 10;
        while (performance.now() < until) {}
      }
    };
    await assert.rejects(f.handlerDependencies.loadOwnedJob(owner, job));
    assert.equal(f.calls.length, 0);
  } finally {
    globalThis.Request = OriginalRequest;
  }
});

test(
  "real PGlite full numeric job CAS accepts original rawJSON and rejects SDK rounding",
  { skip: typeof Deno !== "undefined" },
  async () => {
    const { createRequire } = await import("node:module");
    const require = createRequire(
      new URL("../../tests/isolated/package.json", import.meta.url),
    );
    const { PGlite } = require("@electric-sql/pglite");
    const { pgmq } = require("@electric-sql/pglite-pgmq");
    const { readFile } = await import("node:fs/promises");
    const root = new URL("../../", import.meta.url);
    const sql = (path) => readFile(new URL(path, root), "utf8");
    const db = new PGlite({ extensions: { pgmq } });
    try {
      await db.exec("create extension pgmq");
      await db.exec(await sql("tests/isolated/bootstrap.sql"));
      for (
        const file of [
          "20261007_user_snapshots.sql",
          "20261008155000_recipe_import_jobs_v1.sql",
          "20261011054227_recipe_draft_sessions_v1.sql",
        ]
      ) await db.exec(await sql("migrations/" + file));
      const examples = JSON.parse(
        await readFile(
          new URL(
            "../../../docs/import-fixtures/contract-examples.json",
            import.meta.url,
          ),
          "utf8",
        ),
      );
      const source = examples.cases.find((c) =>
        c.schema === "JobResponse" && c.valid && c.data.status === "completed"
      ).data.result;
      source.review_fields = ["title"];
      source.status = "needs_review";
      source.fields.title.user_confirmed = false;
      source.fields.title.origin = "extracted";
      const full = JSON.stringify(source).replace(
        /}$/,
        ',"ignoredNumericMetadata":[9007199254740993,9223372036854775807,1.234567890123456789,1e400,-0]}',
      );
      await db.query("insert into auth.users(id) values($1)", [owner]);
      await db.query(
        "insert into public.recipe_import_jobs(id,owner_id,client_request_id,input_type,source_value,source_fingerprint,status,stage,result) values($1,$2,$3,'url','https://synthetic.invalid','synthetic-source','completed','done',$4::jsonb)",
        [job, owner, id(9), full],
      );
      let originalBody, roundedCode;
      const f = fixture({
        postgrestTransport: async (req) => {
          if (req.method === "GET") {
            if (!new URL(req.url).pathname.endsWith("recipe_import_jobs")) {
              return response([]);
            }
            return raw(
              `[{"id":"${job}","owner_id":"${owner}","status":"completed","source_fingerprint":"synthetic-source","result":${full}}]`,
            );
          }
          originalBody = await req.text();
          const execute = async (body) =>
            (await db.query(
              `select public.create_recipe_draft_session(p_owner_id=>($1::jsonb->>'p_owner_id')::uuid,p_client_request_id=>($1::jsonb->>'p_client_request_id')::uuid,p_job_id=>($1::jsonb->>'p_job_id')::uuid,p_expected_job_result=>$1::jsonb->'p_expected_job_result',p_base_context=>$1::jsonb->'p_base_context',p_base_context_hash=>$1::jsonb->>'p_base_context_hash',p_enabled=>($1::jsonb->>'p_enabled')::boolean) as value`,
              [body],
            )).rows[0].value;
          const rounded = JSON.stringify(JSON.parse(originalBody));
          roundedCode = (await execute(rounded)).code;
          return response(await execute(originalBody));
        },
      });
      const out = await handleRequest(
        new Request("https://synthetic.invalid/recipe-draft-sessions", {
          method: "POST",
          headers: {
            authorization: "Bearer synthetic-owner",
            "content-type": "application/json",
          },
          body: JSON.stringify({ job_id: job, client_request_id: requestID }),
        }),
        f.handlerDependencies,
      );
      assert.equal(out.status, 201, await out.clone().text());
      assert.equal(roundedCode, "STALE_REVISION");
      assert(originalBody.includes("9007199254740993"));
      assert(originalBody.includes("1.234567890123456789"));
      assert(originalBody.includes("1e400"));
      const equality = (await db.query(
        "select result IS NOT DISTINCT FROM ($2::jsonb->'p_expected_job_result') as equal from public.recipe_import_jobs where id=$1",
        [job, originalBody],
      )).rows[0].equal;
      assert.equal(equality, true);
    } finally {
      await db.close();
    }
  },
);
