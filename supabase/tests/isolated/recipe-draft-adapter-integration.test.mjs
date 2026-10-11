// Developer: gengyun
// Purpose: Verify lossless REST and pinned HTTPS adapters across two real SQL draft flows offline.
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { PGlite } from "@electric-sql/pglite";
import { pgmq } from "@electric-sql/pglite-pgmq";
import { canonicalHash } from "../../functions/recipe-draft-sessions/canonicalJSON.ts";
import { handleRequest } from "../../functions/recipe-draft-sessions/handler.ts";
import { createRecipeDraftBackendAdapter } from "../../functions/recipe-draft-sessions/backendAdapter.ts";
import { createAIDraftDispatchWorker } from "../../functions/recipe-import-worker/aiDraftDispatch.ts";
import { createAIDraftSafeTransport } from "../../functions/recipe-import-worker/aiDraftSafeTransport.ts";

const root = new URL("../../", import.meta.url);
let db, source, assertions = 0;
const eq = (a, b) => {
  assert.deepEqual(a, b);
  assertions++;
};
const ok = (value) => {
  assert.ok(value);
  assertions++;
};
const query = async (sql, args = []) => (await db.query(sql, args)).rows;
const json = (value) => text(JSON.stringify(value));
const text = (value) =>
  new Response(value, { headers: { "content-type": "application/json" } });
const public4 = "93.184.216.34", public6 = "2606:4700:4700::1111";
const rest = "https://synthetic.invalid/rest/v1/";
const model = randomUUID(), provider = randomUUID();
// Closed SQL identifiers and parameters mirror the merged APIs; no general REST server is simulated.
const columns = {
  recipe_import_jobs: "id,owner_id,status,source_fingerprint,result",
  recipe_draft_sessions:
    "id,owner_id,job_id,client_request_id,source_fingerprint,base_context,base_context_hash,effective_context,effective_context_hash,overlay,revision::text,reserved_tokens,settled_tokens,dispatch_count,created_at,updated_at",
  recipe_draft_turns:
    "owner_id,session_id,request_id,request_body,request_hash,based_revision::text,context_snapshot,context_hash,state,result,fencing_token,lease_expires_at,dispatch_state,reserved_tokens,settled_tokens,budget_date,created_at,finished_at",
  recipe_draft_approvals:
    "owner_id,session_id,request_id,turn_request_id,approval_body,approval_hash,action,selected_paths,applied_revision::text,receipt",
  ai_routes:
    "route_key,primary_model_id,enabled,timeout_ms,max_retries,max_output_tokens,temperature",
  ai_models: "id,provider_id,upstream_model_id,display_name,enabled,created_at",
  ai_providers: "id,name,base_url,secret_ref,enabled,updated_at",
  ai_secrets: "secret_ref,ciphertext,nonce,key_version",
};
const uuidParams = [
  "p_owner_id",
  "p_session_id",
  "p_job_id",
  "p_request_id",
  "p_turn_request_id",
  "p_client_request_id",
  "p_fencing_token",
];
const jsonParams = [
  "p_expected_job_result",
  "p_base_context",
  "p_next_context",
  "p_result",
];
const rpcParams = {
  create_recipe_draft_session: [
    "p_owner_id",
    "p_client_request_id",
    "p_job_id",
    "p_expected_job_result",
    "p_base_context",
    "p_base_context_hash",
    "p_enabled",
  ],
  claim_recipe_draft_turn: [
    "p_owner_id",
    "p_session_id",
    "p_request_id",
    "p_expected_revision",
    "p_message",
    "p_request_hash",
    "p_context_hash",
    "p_enabled",
  ],
  approve_recipe_draft_turn: [
    "p_owner_id",
    "p_session_id",
    "p_turn_request_id",
    "p_request_id",
    "p_expected_revision",
    "p_action",
    "p_selected_paths",
    "p_approval_hash",
    "p_next_context",
    "p_next_context_hash",
    "p_enabled",
  ],
  recover_recipe_draft_turn: [
    "p_owner_id",
    "p_session_id",
    "p_request_id",
    "p_enabled",
  ],
  mark_recipe_draft_turn_dispatched: [
    "p_owner_id",
    "p_session_id",
    "p_request_id",
    "p_fencing_token",
    "p_enabled",
  ],
  finish_recipe_draft_turn: [
    "p_owner_id",
    "p_session_id",
    "p_request_id",
    "p_fencing_token",
    "p_result",
    "p_validated_usage",
    "p_expected_dispatch_state",
  ],
};
const filterSets = {
  recipe_import_jobs: [["id", "owner_id"]],
  recipe_draft_sessions: [["id", "owner_id"], [
    "client_request_id",
    "owner_id",
  ]],
  recipe_draft_turns: [["owner_id", "request_id", "session_id"]],
  recipe_draft_approvals: [["owner_id", "session_id", "turn_request_id"]],
  ai_routes: [["enabled", "route_key"]],
  ai_models: [["enabled", "id"]],
  ai_providers: [["enabled", "id"]],
  ai_secrets: [["secret_ref"]],
};
function expression(param) {
  if (jsonParams.includes(param)) return `$1::jsonb->'${param}'`;
  if (param === "p_selected_paths") {
    return `array(select jsonb_array_elements_text($1::jsonb->'${param}'))`;
  }
  const cast = uuidParams.includes(param)
    ? "uuid"
    : param === "p_expected_revision"
    ? "bigint"
    : param === "p_enabled"
    ? "boolean"
    : param === "p_validated_usage"
    ? "integer"
    : "text";
  return `($1::jsonb->>'${param}')::${cast}`;
}
const budget = async (owner) =>
  query(
    "select reserved_tokens,settled_tokens from public.recipe_draft_owner_budgets where owner_id=$1 order by utc_date",
    [owner],
  );
const durable = async (f) =>
  (await query(
    "select state,dispatch_state,reserved_tokens,settled_tokens,fencing_token from public.recipe_draft_turns where owner_id=$1 and session_id=$2 and request_id=$3",
    [f.owner, f.sid, f.tid],
  ))[0];
const preserved = async (f) =>
  (await query(
    "select (select to_jsonb(j)::text from public.recipe_import_jobs j where j.id=$1) as job,(select to_jsonb(s)::text from public.user_snapshots s where s.user_id=$2) as private",
    [f.job, f.owner],
  ))[0];

before(async () => {
  db = new PGlite({ extensions: { pgmq } });
  await db.exec("create extension pgmq;");
  for (
    const path of [
      "tests/isolated/bootstrap.sql",
      "migrations/20261007_user_snapshots.sql",
      "migrations/20261008155000_recipe_import_jobs_v1.sql",
      "migrations/20261011054227_recipe_draft_sessions_v1.sql",
    ]
  ) await db.exec(await readFile(new URL(path, root), "utf8"));
  const fixtures = JSON.parse(
    await readFile(
      new URL(
        "../../../docs/import-fixtures/contract-examples.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  source = fixtures.cases.find((c) =>
    c.schema === "JobResponse" && c.valid && c.data.status === "completed"
  ).data.result;
});
after(async () => {
  await db?.close();
  console.log(
    `LOCAL ADAPTER INTEGRATION: 2 flows, ${assertions} assertions; real JWT/PostgREST/TLS/provider/multi-connection/deployment NOT RUN.`,
  );
});

async function fixture(blockDNS = false) {
  const f = {
    owner: randomUUID(),
    foreign: randomUUID(),
    job: randomUUID(),
    createKey: randomUUID(),
    tid: randomUUID(),
    approvalKey: randomUUID(),
    dns: 0,
    sockets: 0,
    writes: [],
    rpc: [],
    checkpoints: 0,
  };
  await query("insert into auth.users(id) values($1),($2)", [
    f.owner,
    f.foreign,
  ]);
  const result = structuredClone(source);
  result.status = "needs_review";
  result.review_fields = ["ingredients", ...result.review_fields];
  const full = JSON.stringify(result).replace(
    /}$/,
    ',"ignoredNumericMetadata":[9007199254740993,1.234567890123456789]}',
  );
  await query(
    "insert into public.recipe_import_jobs(id,owner_id,client_request_id,input_type,source_value,source_fingerprint,status,stage,result) values($1,$2,$3,'url','https://synthetic.invalid/source',$4,'completed','done',$5::jsonb)",
    [f.job, f.owner, randomUUID(), "source:" + f.job, full],
  );
  await query(
    "insert into public.user_snapshots(user_id,payload,client_updated_at) values($1,$2,now())",
    [f.owner, {
      private: "untouched local fixture",
      recipes: [{ id: result.recipe_id }],
    }],
  );
  f.before = await preserved(f);
  const registry = {
    ai_routes: [{
      route_key: "recipe_import_draft_v1",
      primary_model_id: model,
      enabled: true,
      timeout_ms: 10000,
      max_retries: 0,
      max_output_tokens: 1000,
      temperature: null,
    }],
    ai_models: [{
      id: model,
      provider_id: provider,
      upstream_model_id: "synthetic-model",
      display_name: "Synthetic",
      enabled: true,
      created_at: "2026-01-01T00:00:00Z",
    }],
    ai_providers: [{
      id: provider,
      name: "Synthetic",
      base_url: "https://provider.example.test/v1",
      secret_ref: "synthetic-ref",
      enabled: true,
      updated_at: "2026-01-01T00:00:00Z",
    }],
    ai_secrets: [{
      secret_ref: "synthetic-ref",
      ciphertext: "synthetic-not-encrypted",
      nonce: "synthetic-nonce",
      key_version: 2,
    }],
  };
  f.rest = async (req, policy) => {
    eq(req.redirect, "error");
    eq(req.headers.get("authorization"), "Bearer synthetic-service");
    eq(req.headers.get("apikey"), "synthetic-service");
    eq(req.headers.get("content-type"), "application/json");
    eq(policy.maxResponseBytes, 4194304);
    ok(!policy.signal.aborted);
    const url = new URL(req.url);
    eq(url.origin, "https://synthetic.invalid");
    ok(req.url.startsWith(rest));
    const name = url.pathname.slice("/rest/v1/".length);
    if (req.method === "POST") {
      ok(name.startsWith("rpc/"));
      const rpc = name.slice(4);
      ok(Object.hasOwn(rpcParams, rpc));
      eq(url.search, "");
      const body = await req.text();
      // Inspect only keys in JavaScript. All values, including full numeric CAS, enter SQL from original text.
      eq(
        (await query(
          "select array_agg(k order by k) as keys from jsonb_object_keys($1::jsonb) k",
          [body],
        ))[0].keys,
        [...rpcParams[rpc]].sort(),
      );
      f.rpc.push(rpc);
      if (rpc === "create_recipe_draft_session") {
        eq(
          (await query(
            "select result IS NOT DISTINCT FROM ($2::jsonb->'p_expected_job_result') as same from public.recipe_import_jobs where id=$1",
            [f.job, body],
          ))[0].same,
          true,
        );
        ok(body.includes("9007199254740993"));
        ok(body.includes("1.234567890123456789"));
      }
      const value = (await query(
        `select public.${rpc}(${
          rpcParams[rpc].map((p) => `${p}=>${expression(p)}`).join(",")
        })::text as value`,
        [body],
      ))[0].value;
      return text(value);
    }
    eq(req.method, "GET");
    ok(Object.hasOwn(columns, name));
    eq(url.searchParams.get("select"), columns[name]);
    eq(url.searchParams.get("limit"), "2");
    const keys = [...url.searchParams.keys()].filter((k) =>
      k !== "select" && k !== "limit"
    ).sort();
    ok(
      filterSets[name].some((set) =>
        JSON.stringify(set) === JSON.stringify(keys)
      ),
    );
    const values = keys.map((k) => {
      const filter = url.searchParams.get(k);
      if (k === "enabled") {
        eq(filter, "eq.true");
        return true;
      }
      ok(/^eq\."[a-zA-Z0-9_:\-]+"$/.test(filter));
      return filter.slice(4, -1);
    });
    if (Object.hasOwn(registry, name)) {
      return json(
        registry[name].filter((row) =>
          keys.every((k, i) => row[k] === values[i])
        ),
      );
    }
    const select = columns[name].split(",").map((column) =>
      column.includes("::text")
        ? `${column} as ${column.split("::")[0]}`
        : column
    ).join(",");
    const value = (await query(
      `select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)::text as value from (select ${select} from public.${name} where ${
        keys.map((k, i) => `${k}=$${i + 1}`).join(" and ")
      } limit 2) r`,
      values,
    ))[0].value;
    return text(value);
  };
  f.backend = createRecipeDraftBackendAdapter({
    enabled: true,
    supabaseRESTBaseURL: new URL(rest.slice(0, -1)),
    serviceRoleKey: "synthetic-service",
    encodedAISecretKey: "synthetic-test-key",
    postgrestTransport: f.rest,
    // This is a synthetic verified-owner boundary, not JWT verification; actual bindings are separately tested.
    authenticate: async (request) => {
      const who = request.headers.get("authorization")?.replace(/^Bearer /, "");
      assert([f.owner, f.foreign].includes(who));
      return { user: { id: who, is_anonymous: false } };
    },
    decryptAISecret: async (secret, key) => {
      eq(secret.secret_ref, "synthetic-ref");
      eq(key, "synthetic-test-key");
      return "synthetic-provider-secret";
    },
  });
  f.http = async (method, path, body, as = f.owner) => {
    const response = await handleRequest(
      new Request("https://synthetic.invalid" + path, {
        method,
        headers: {
          authorization: "Bearer " + as,
          "content-type": "application/json",
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      f.backend.handlerDependencies,
    );
    return { status: response.status, body: await response.json() };
  };
  const amount = result.fields["ingredients[0].amount"];
  const inner = {
    questions: [{
      path: "ingredients",
      question: "Which amount should be reviewed?",
      evidence_ids: amount.evidence_ids,
    }],
    suggestions: [{
      path: "ingredients[0].amount",
      raw_value: amount.raw_value,
      evidence_ids: amount.evidence_ids,
      reason: "Original source wording",
    }],
  };
  const safeTransport = createAIDraftSafeTransport({
    enabled: true,
    resolveDNS: async (host, record, signal) => {
      eq(host, "provider.example.test");
      ok(!signal.aborted);
      ok(["A", "AAAA"].includes(record));
      f.dns++;
      // The async hook checks actual SQL after mark; the synchronous native hook consumes this checkpoint.
      const t = await durable(f);
      eq(t.state, "pending");
      eq(t.dispatch_state, "dispatched_unknown");
      eq(t.reserved_tokens, 4096);
      f.checkpoints++;
      return record === "A" ? [public4] : [blockDNS ? "fd00::1" : public6];
    },
    requestHTTPS: (options, callback) => {
      f.sockets++;
      eq(f.checkpoints, 2);
      eq(options.hostname, "provider.example.test");
      eq(options.servername, options.hostname);
      eq(options.port, 443);
      eq(options.method, "POST");
      eq(options.path, "/v1/chat/completions");
      eq(options.agent, false);
      eq(options.rejectUnauthorized, true);
      eq(options.headers.Authorization, "Bearer synthetic-provider-secret");
      eq(options.headers["Content-Type"], "application/json");
      options.lookup(options.hostname, { all: true }, (error, addresses) => {
        eq(error, null);
        eq(addresses, [{ address: public4, family: 4 }, {
          address: public6,
          family: 6,
        }]);
      });
      const outgoing = new EventEmitter();
      outgoing.destroyed = false;
      outgoing.destroy = () => {
        outgoing.destroyed = true;
        return outgoing;
      };
      outgoing.write = (bytes) => {
        f.writes.push(Buffer.from(bytes));
        return true;
      };
      outgoing.end = () => {
        const bytes = Buffer.concat(f.writes);
        eq(Number(options.headers["Content-Length"]), bytes.length);
        const payload = JSON.parse(bytes.toString("utf8"));
        eq(payload.model, "synthetic-model");
        eq(payload.max_tokens, 1000);
        eq(
          payload.messages.at(-1).content.includes(
            "Keep the original evidence",
          ),
          true,
        );
        queueMicrotask(() => {
          const incoming = new EventEmitter();
          incoming.destroyed = false;
          incoming.destroy = () => {
            incoming.destroyed = true;
            return incoming;
          };
          incoming.statusCode = 200;
          incoming.headers = { "content-type": "application/json" };
          callback(incoming);
          incoming.emit(
            "data",
            Buffer.from(
              JSON.stringify({
                choices: [{
                  finish_reason: "stop",
                  message: {
                    role: "assistant",
                    content: JSON.stringify(inner),
                  },
                }],
                usage: { total_tokens: 25 },
              }),
            ),
          );
          incoming.emit("end");
          incoming.emit("close");
        });
      };
      return outgoing;
    },
  });
  f.run = (as = f.owner) =>
    createAIDraftDispatchWorker({
      enabled: true,
      ...f.backend.workerDependencies,
      safeTransport,
      outerTimeoutMs: 10000,
    }).runTurn({ ownerID: as, sessionID: f.sid, requestID: f.tid });
  f.createBody = { job_id: f.job, client_request_id: f.createKey };
  f.turnBody = {
    request_id: f.tid,
    expected_revision: "1",
    message: "Keep the original evidence wording.",
  };
  f.start = async () => {
    const created = await f.http(
      "POST",
      "/recipe-draft-sessions",
      f.createBody,
    );
    eq(created.status, 201);
    f.sid = created.body.session_id;
    f.created = created;
    const accepted = await f.http(
      "POST",
      `/recipe-draft-sessions/${f.sid}/turns`,
      f.turnBody,
    );
    eq(accepted.status, 202);
    const row = (await query(
      "select request_hash from public.recipe_draft_turns where owner_id=$1 and session_id=$2 and request_id=$3",
      [f.owner, f.sid, f.tid],
    ))[0];
    eq(row.request_hash, await canonicalHash(f.turnBody));
    eq(await budget(f.owner), [{ reserved_tokens: 4096, settled_tokens: 0 }]);
  };
  return f;
}

test("lossless REST → fenced SQL → pinned HTTPS → validated usage → approval and stable owner replay", async () => {
  const f = await fixture();
  await f.start();
  const generated = await f.run();
  eq(generated.state, "terminal");
  eq(generated.result.status, "proposal");
  eq(f.sockets, 1);
  eq(f.dns, 2);
  eq(await budget(f.owner), [{ reserved_tokens: 0, settled_tokens: 25 }]);
  const polled = await f.http(
    "GET",
    `/recipe-draft-sessions/${f.sid}/turns/${f.tid}`,
  );
  eq(polled.status, 200);
  eq(polled.body.result, generated.result);
  const approvalBody = {
    request_id: f.approvalKey,
    expected_revision: "1",
    action: "accept",
    selected_paths: ["ingredients[0].amount"],
  };
  const approved = await f.http(
    "POST",
    `/recipe-draft-sessions/${f.sid}/turns/${f.tid}/approval`,
    approvalBody,
  );
  eq(approved.status, 200);
  eq(approved.body.applied_revision, "2");
  const current = await f.http("GET", `/recipe-draft-sessions/${f.sid}`);
  eq(current.body.revision, "2");
  eq(current.body.budget.dispatch_count, 1);
  const beforeTurn = await durable(f), beforeBudget = await budget(f.owner);
  const createdReplay = await f.http(
    "POST",
    "/recipe-draft-sessions",
    f.createBody,
  );
  eq(createdReplay.status, 200);
  eq(createdReplay.body.revision, "2");
  eq(createdReplay.body.session_id, f.sid);
  const turnReplay = await f.http(
    "POST",
    `/recipe-draft-sessions/${f.sid}/turns`,
    f.turnBody,
  );
  eq(turnReplay.status, 200);
  eq(turnReplay.body.result, generated.result);
  eq(turnReplay.body.decision, approved.body);
  eq(
    await f.http(
      "POST",
      `/recipe-draft-sessions/${f.sid}/turns/${f.tid}/approval`,
      approvalBody,
    ),
    approved,
  );
  eq(await f.run(), generated);
  eq(
    (await f.http(
      "GET",
      `/recipe-draft-sessions/${f.sid}/turns/${f.tid}`,
      undefined,
      f.foreign,
    )).status,
    404,
  );
  eq((await f.run(f.foreign)).code, "NOT_FOUND");
  eq(await durable(f), beforeTurn);
  eq(await budget(f.owner), beforeBudget);
  eq(f.dns, 2);
  eq(f.sockets, 1);
  eq(f.rpc.filter((n) => n === "mark_recipe_draft_turn_dispatched").length, 1);
  eq(f.rpc.filter((n) => n === "finish_recipe_draft_turn").length, 1);
  eq(await preserved(f), f.before);
});

test("mixed private DNS after durable mark opens no socket and conservatively settles once", async () => {
  const f = await fixture(true);
  await f.start();
  const generated = await f.run();
  eq(generated.state, "terminal");
  eq(generated.result, { status: "unavailable", code: "PROVIDER_UNAVAILABLE" });
  eq(f.checkpoints, 2);
  eq(f.dns, 2);
  eq(f.sockets, 0);
  eq(f.writes, []);
  eq(await budget(f.owner), [{ reserved_tokens: 0, settled_tokens: 4096 }]);
  const polled = await f.http(
    "GET",
    `/recipe-draft-sessions/${f.sid}/turns/${f.tid}`,
  );
  eq(polled.status, 200);
  eq(polled.body.result, generated.result);
  eq(await f.run(), generated);
  const replay = await f.http(
    "POST",
    `/recipe-draft-sessions/${f.sid}/turns`,
    f.turnBody,
  );
  eq(replay.status, 200);
  eq(replay.body.result, generated.result);
  eq(f.dns, 2);
  eq(f.sockets, 0);
  eq(f.rpc.filter((n) => n === "mark_recipe_draft_turn_dispatched").length, 1);
  eq(f.rpc.filter((n) => n === "finish_recipe_draft_turn").length, 1);
  eq(await budget(f.owner), [{ reserved_tokens: 0, settled_tokens: 4096 }]);
  eq(await preserved(f), f.before);
});
