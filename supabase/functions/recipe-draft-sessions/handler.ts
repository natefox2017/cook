// Developer: gengyun
// Purpose: Map verified owner requests to durable draft RPCs without dispatching providers.
import { canonicalHash, canonicalJSON, scalarString } from "./canonicalJSON.ts";
import { readRequestJSON, RequestJSONError } from "./requestJSON.ts";
import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";

type Row = Record<string, unknown>;
export interface Dependencies {
  verifiedOwner(
    request: Request,
  ): Promise<{ id: string; isAnonymous: boolean } | null>;
  isEnabled(): boolean | Promise<boolean>;
  // Production adapters MUST preserve bigint revisions and the complete job CAS snapshot losslessly.
  // Rounded SDK JSON numbers cannot be repaired here. Each read must carry its explicit owner predicate.
  loadOwnedJob(owner: string, job: string): Promise<unknown>;
  loadOwnedSession(owner: string, session: string): Promise<unknown>;
  loadOwnedSessionByCreationKey(owner: string, key: string): Promise<unknown>;
  loadOwnedTurn(owner: string, session: string, turn: string): Promise<unknown>;
  loadOwnedApprovalForTurn(
    owner: string,
    session: string,
    turn: string,
  ): Promise<unknown>;
  rpc(name: string, args: Row): Promise<unknown>;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PATH =
  /^(title|servings|ingredients\[(?:[0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[(?:[0-9]|[1-9][0-9])\]\.instruction)$/;
const HASH = /^[0-9a-f]{64}$/;
const MAX_REV = 9223372036854775807n;
const statuses: Record<string, number> = {
  AUTH_REQUIRED: 401,
  NOT_FOUND: 404,
  JOB_NOT_READY: 409,
  STALE_REVISION: 409,
  IDEMPOTENCY_CONFLICT: 409,
  TURN_ALREADY_DECIDED: 409,
  REVISION_EXHAUSTED: 409,
  INPUT_TOO_LARGE: 413,
  INVALID_INPUT: 422,
  INVALID_EVIDENCE: 422,
  INVALID_REVIEW_PATH: 422,
  BUDGET_EXHAUSTED: 429,
  DRAFT_DISABLED: 503,
  PROVIDER_UNAVAILABLE: 503,
  INTERNAL_ERROR: 500,
};
class Failure extends Error {
  code: string;
  constructor(code: string) {
    super(code);
    this.code = code;
  }
}
function requireThat(
  condition: unknown,
  code = "INTERNAL_ERROR",
): asserts condition {
  if (!condition) throw new Failure(code);
}
function object(value: unknown, code = "INTERNAL_ERROR"): Row {
  requireThat(
    value !== null && typeof value === "object" && !Array.isArray(value),
    code,
  );
  return value as Row;
}
function exact(row: Row, keys: string[], code = "INTERNAL_ERROR") {
  requireThat(
    Object.keys(row).length === keys.length &&
      keys.every((key) => Object.hasOwn(row, key)),
    code,
  );
}
function uuid(value: unknown, code = "INTERNAL_ERROR"): string {
  requireThat(typeof value === "string" && UUID.test(value), code);
  return value;
}
function revision(value: unknown, code = "INTERNAL_ERROR"): string {
  const text = typeof value === "bigint" ? value.toString() : value;
  requireThat(
    typeof text === "string" && /^[1-9][0-9]{0,18}$/.test(text),
    code,
  );
  requireThat(BigInt(text) <= MAX_REV, code);
  return text;
}
function hash(value: unknown): string {
  requireThat(typeof value === "string" && HASH.test(value));
  return value;
}
function count(value: unknown, max: number): number {
  requireThat(
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0 &&
      value <= max,
  );
  return value;
}
function strings(
  value: unknown,
  max: number,
  test: (value: unknown) => boolean,
  code = "INTERNAL_ERROR",
): string[] {
  requireThat(
    Array.isArray(value) && value.length <= max && value.every(test) &&
      new Set(value).size === value.length,
    code,
  );
  return value as string[];
}
function reviewPath(value: unknown): boolean {
  return typeof value === "string" &&
    (PATH.test(value) || value === "ingredients" || value === "steps");
}
function field(value: unknown, strict: boolean, code: string): Row {
  const row = object(value, code);
  if (strict) {
    exact(row, ["raw_value", "evidence_ids", "user_confirmed", "origin"], code);
  }
  requireThat(
    row.raw_value === null || scalarString(row.raw_value, 1, 1500),
    code,
  );
  requireThat(
    typeof row.user_confirmed === "boolean" && scalarString(row.origin, 1, 64),
    code,
  );
  return {
    raw_value: row.raw_value,
    evidence_ids: strings(
      row.evidence_ids,
      60,
      (x) => typeof x === "string" && UUID.test(x),
      code,
    ),
    user_confirmed: row.user_confirmed,
    origin: row.origin,
  };
}
function context(value: unknown, strict = true, code = "INTERNAL_ERROR"): Row {
  const row = object(value, code);
  if (strict) {
    exact(row, ["status", "fields", "evidence", "review_fields"], code);
  }
  requireThat(row.status === "ready" || row.status === "needs_review", code);
  const rawFields = object(row.fields, code);
  requireThat(Object.keys(rawFields).length <= 100, code);
  const fields: Row = Object.create(null);
  for (const [path, value] of Object.entries(rawFields)) {
    requireThat(
      PATH.test(path),
      code === "INVALID_INPUT" ? "INVALID_REVIEW_PATH" : code,
    );
    fields[path] = field(value, strict, code);
  }
  requireThat(Array.isArray(row.evidence) && row.evidence.length <= 60, code);
  let total = 0;
  const seen = new Set<string>();
  const evidence = row.evidence.map((value) => {
    const e = object(value, code);
    if (strict) exact(e, ["id", "excerpt"], code);
    const id = uuid(e.id, code === "INVALID_INPUT" ? "INVALID_EVIDENCE" : code);
    requireThat(
      scalarString(e.excerpt, 1, 1500) && !seen.has(id),
      code === "INVALID_INPUT" ? "INVALID_EVIDENCE" : code,
    );
    seen.add(id);
    total += [...e.excerpt].length;
    return { id, excerpt: e.excerpt };
  });
  requireThat(
    total <= 20000,
    code === "INVALID_INPUT" ? "INVALID_EVIDENCE" : code,
  );
  for (const f of Object.values(fields)) {
    requireThat(
      (object(f).evidence_ids as string[]).every((id) => seen.has(id)),
      code === "INVALID_INPUT" ? "INVALID_EVIDENCE" : code,
    );
  }
  const flags = strings(
    row.review_fields,
    100,
    reviewPath,
    code === "INVALID_INPUT" ? "INVALID_REVIEW_PATH" : code,
  );
  requireThat((row.status === "ready") === (flags.length === 0), code);
  for (const flag of flags) {
    if (PATH.test(flag)) {
      requireThat(
        !object(fields[flag] ?? { user_confirmed: false }).user_confirmed,
        code,
      );
    } else {
      const group = Object.entries(fields).filter(([path]) =>
        path.startsWith(flag + "[")
      );
      requireThat(
        group.length === 0 || group.some(([, f]) =>
          !object(f).user_confirmed
        ) || flags.some((path) =>
          path.startsWith(flag + "[") &&
          !object(fields[path] ?? { user_confirmed: false }).user_confirmed
        ),
        code,
      );
    }
  }
  const result = { status: row.status, fields, evidence, review_fields: flags };
  requireThat(
    new TextEncoder().encode(canonicalJSON(result)).length <= 1048576,
    code,
  );
  return result;
}
function owned(value: unknown, owner: string, matches: Row): Row {
  requireThat(value !== null && value !== undefined, "NOT_FOUND");
  const row = object(value);
  requireThat(
    row.owner_id === owner &&
      Object.entries(matches).every(([key, val]) => row[key] === val),
    "NOT_FOUND",
  );
  return row;
}
function session(row: Row): Row {
  const overlayRaw = object(row.overlay), overlay: Row = Object.create(null);
  requireThat(Object.keys(overlayRaw).length <= 100);
  for (const [path, value] of Object.entries(overlayRaw)) {
    requireThat(PATH.test(path));
    const f = object(value);
    exact(f, [
      "raw_value",
      "evidence_ids",
      "user_confirmed",
      "origin",
      "confirmed_revision",
    ]);
    const projected = field(
      {
        raw_value: f.raw_value,
        evidence_ids: f.evidence_ids,
        user_confirmed: f.user_confirmed,
        origin: f.origin,
      },
      true,
      "INTERNAL_ERROR",
    );
    requireThat(
      f.user_confirmed === true && f.origin === "AI_suggested" &&
        (projected.evidence_ids as string[]).length > 0 && f.raw_value !== null,
    );
    overlay[path] = {
      ...projected,
      confirmed_revision: revision(f.confirmed_revision),
    };
  }
  const reserved = count(row.reserved_tokens, 32768),
    settled = count(row.settled_tokens, 32768);
  requireThat(
    reserved + settled <= 32768 && scalarString(row.source_fingerprint, 1, 512),
  );
  const output = {
    session_id: uuid(row.id),
    job_id: uuid(row.job_id),
    client_request_id: uuid(row.client_request_id),
    revision: revision(row.revision),
    source_fingerprint: row.source_fingerprint,
    context_hash: hash(row.effective_context_hash),
    context: context(row.effective_context),
    overlay,
    budget: {
      reserved_tokens: reserved,
      settled_tokens: settled,
      dispatch_count: count(row.dispatch_count, 8),
    },
  };
  const ctx = object(output.context);
  for (const [path, value] of Object.entries(overlay)) {
    const f = object(value), base = object(object(ctx.fields)[path]);
    requireThat(
      BigInt(revision(f.confirmed_revision)) <= BigInt(output.revision),
    );
    requireThat(
      canonicalJSON({
        raw_value: f.raw_value,
        evidence_ids: f.evidence_ids,
        user_confirmed: f.user_confirmed,
        origin: f.origin,
      }) === canonicalJSON(base),
    );
  }
  return output;
}
function receipt(value: unknown, sessionID: string, turnID: string): Row {
  const r = object(value);
  exact(r, [
    "session_id",
    "turn_request_id",
    "request_id",
    "action",
    "selected_paths",
    "applied_revision",
  ]);
  requireThat(r.session_id === sessionID && r.turn_request_id === turnID);
  const paths = strings(
    r.selected_paths,
    20,
    (x) => typeof x === "string" && PATH.test(x),
  );
  requireThat(
    (r.action === "accept" && paths.length > 0) ||
      (r.action === "reject" && paths.length === 0),
  );
  return {
    session_id: uuid(r.session_id),
    turn_request_id: uuid(r.turn_request_id),
    request_id: uuid(r.request_id),
    action: r.action,
    selected_paths: paths,
    applied_revision: revision(r.applied_revision),
  };
}
function generation(value: unknown): Row {
  const r = object(value);
  if (r.status === "no_review_needed") {
    exact(r, ["status"]);
    return { status: r.status };
  }
  if (r.status === "rejected" || r.status === "unavailable") {
    exact(r, ["status", "code"]);
    requireThat(
      typeof r.code === "string" &&
        [
          "INVALID_INPUT",
          "INVALID_EVIDENCE",
          "INVALID_REVIEW_PATH",
          "INVALID_PROVIDER_OUTPUT",
          "INPUT_BUDGET",
          "OUTPUT_BUDGET",
          "STALE_REVISION",
          "PROVIDER_TIMEOUT",
          "PROVIDER_UNAVAILABLE",
          "PROVIDER_OUTCOME_UNKNOWN",
        ].includes(r.code),
    );
    return { status: r.status, code: r.code };
  }
  exact(r, [
    "status",
    "origin",
    "requires_approval",
    "questions",
    "suggestions",
  ]);
  requireThat(
    r.status === "proposal" && r.origin === "AI_suggested" &&
      r.requires_approval === true,
  );
  requireThat(
    Array.isArray(r.questions) && r.questions.length <= 3 &&
      Array.isArray(r.suggestions) && r.suggestions.length <= 20,
  );
  const questions = r.questions.map((value) => {
    const q = object(value);
    exact(q, ["path", "question", "evidence_ids"]);
    requireThat(reviewPath(q.path) && scalarString(q.question, 1, 300));
    const ids = strings(
      q.evidence_ids,
      60,
      (x) => typeof x === "string" && UUID.test(x),
    );
    requireThat(ids.length > 0);
    return { path: q.path, question: q.question, evidence_ids: ids };
  });
  const suggestions = r.suggestions.map((value) => {
    const s = object(value);
    exact(s, ["path", "raw_value", "evidence_ids", "reason"]);
    requireThat(
      typeof s.path === "string" && PATH.test(s.path) &&
        scalarString(s.raw_value, 1, 1500) && scalarString(s.reason, 1, 500),
    );
    const ids = strings(
      s.evidence_ids,
      60,
      (x) => typeof x === "string" && UUID.test(x),
    );
    requireThat(ids.length > 0);
    return {
      path: s.path,
      raw_value: s.raw_value,
      evidence_ids: ids,
      reason: s.reason,
    };
  });
  requireThat(
    new Set(questions.map((q) => canonicalJSON(q))).size === questions.length &&
      new Set(suggestions.map((s) => canonicalJSON(s))).size ===
        suggestions.length,
  );
  return {
    status: r.status,
    origin: r.origin,
    requires_approval: true,
    questions,
    suggestions,
  };
}
async function turn(
  row: Row,
  owner: string,
  sessionID: string,
  requestID: string,
  deps: Dependencies,
): Promise<Row> {
  owned(row, owner, { session_id: sessionID, request_id: requestID });
  requireThat(row.state === "pending" || row.state === "terminal");
  const result = row.state === "pending" ? null : generation(row.result);
  requireThat(row.state !== "pending" || row.result === null);
  const approval = await deps.loadOwnedApprovalForTurn(
    owner,
    sessionID,
    requestID,
  );
  let decision = null;
  if (approval !== null && approval !== undefined) {
    const a = owned(approval, owner, {
      session_id: sessionID,
      turn_request_id: requestID,
    });
    decision = receipt(a.receipt, sessionID, requestID);
    requireThat(
      a.request_id === decision.request_id && a.action === decision.action &&
        revision(a.applied_revision) === decision.applied_revision &&
        canonicalJSON(a.selected_paths) ===
          canonicalJSON(decision.selected_paths),
    );
  }
  requireThat(row.state !== "pending" || decision === null);
  return {
    session_id: sessionID,
    request_id: requestID,
    based_revision: revision(row.based_revision),
    context_hash: hash(row.context_hash),
    state: row.state,
    result,
    decision,
  };
}
async function contextHash(s: Row, ctx: Row, rev: string): Promise<string> {
  return await canonicalHash({
    job_id: s.job_id,
    source_fingerprint: s.source_fingerprint,
    revision: rev,
    context: {
      status: ctx.status,
      fields: ctx.fields,
      evidence: ctx.evidence,
      reviewFields: ctx.review_fields,
    },
  });
}
function approvalContext(s: Row, t: Row, body: Row): Row {
  const current = context(s.effective_context);
  if (body.action === "reject") return current;
  const result = generation(t.result);
  requireThat(result.status === "proposal", "INVALID_INPUT");
  const fields = { ...object(current.fields) };
  const selected = body.selected_paths as string[];
  const flags = current.review_fields as string[];
  for (const path of selected) {
    const suggestions = (result.suggestions as Row[]).filter((item) =>
      item.path === path
    );
    const existing = fields[path] ? object(fields[path]) : null;
    requireThat(
      suggestions.length === 1 &&
        (!existing || existing.user_confirmed !== true) &&
        (existing !== null || flags.includes(path)) && flags.some((flag) =>
          flag === path ||
          ((flag === "ingredients" || flag === "steps") &&
            path.startsWith(flag + "["))
        ),
      "INVALID_INPUT",
    );
    const suggestion = suggestions[0];
    fields[path] = {
      raw_value: suggestion.raw_value,
      evidence_ids: suggestion.evidence_ids,
      user_confirmed: true,
      origin: "AI_suggested",
    };
  }
  const nextFlags = flags.filter((flag) => {
    if (selected.includes(flag)) return false;
    if (flag !== "ingredients" && flag !== "steps") return true;
    const keys = Object.keys(fields).filter((path) =>
      path.startsWith(flag + "[")
    );
    const exactFlags = flags.filter((path) => path.startsWith(flag + "["));
    return !(keys.length > 0 && keys.every((path) =>
      object(fields[path]).user_confirmed === true
    ) && exactFlags.every((path) =>
      fields[path] && object(fields[path]).user_confirmed === true
    ) && selected.some((path) => path.startsWith(flag + "[")));
  });
  return context(
    {
      ...current,
      fields,
      review_fields: nextFlags,
      status: nextFlags.length ? "needs_review" : "ready",
    },
    true,
    "INVALID_INPUT",
  );
}
function validateBody(body: Row, kind: string): void {
  if (kind === "create") {
    exact(body, ["job_id", "client_request_id"], "INVALID_INPUT");
    uuid(body.job_id, "INVALID_INPUT");
    uuid(body.client_request_id, "INVALID_INPUT");
    return;
  }
  exact(
    body,
    kind === "claim"
      ? ["request_id", "expected_revision", "message"]
      : ["request_id", "expected_revision", "action", "selected_paths"],
    "INVALID_INPUT",
  );
  uuid(body.request_id, "INVALID_INPUT");
  revision(body.expected_revision, "INVALID_INPUT");
  if (kind === "claim") {
    requireThat(scalarString(body.message, 0, 2000), "INVALID_INPUT");
    return;
  }
  const paths = strings(
    body.selected_paths,
    20,
    (x) => typeof x === "string" && PATH.test(x),
    "INVALID_INPUT",
  );
  requireThat(
    (body.action === "accept" && paths.length > 0) ||
      (body.action === "reject" && paths.length === 0),
    "INVALID_INPUT",
  );
}
function rpcObject(value: unknown): Row {
  const row = object(value);
  if (Object.hasOwn(row, "code")) {
    const code = row.code === "REQUEST_CONFLICT"
      ? "IDEMPOTENCY_CONFLICT"
      : row.code;
    requireThat(typeof code === "string" && Object.hasOwn(statuses, code));
    throw new Failure(code);
  }
  return row;
}
function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      ...publicCorsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}
export async function handleRequest(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  const preflight = handleCors(request);
  if (preflight) return preflight;
  try {
    const path = new URL(request.url).pathname;
    const parts = path.split("/").filter(Boolean);
    let kind = "";
    if (path === "/recipe-draft-sessions" && request.method === "POST") {
      kind = "create";
    } else if (
      path === "/" + parts.join("/") && parts[0] === "recipe-draft-sessions" &&
      parts.length >= 2 && UUID.test(parts[1])
    ) {
      if (parts.length === 2 && request.method === "GET") kind = "session";
      if (
        parts.length === 3 && parts[2] === "turns" && request.method === "POST"
      ) kind = "claim";
      if (
        parts.length === 4 && parts[2] === "turns" && UUID.test(parts[3]) &&
        request.method === "GET"
      ) kind = "turn";
      if (
        parts.length === 5 && parts[2] === "turns" && UUID.test(parts[3]) &&
        parts[4] === "approval" && request.method === "POST"
      ) kind = "approve";
    }
    requireThat(kind, "NOT_FOUND");
    requireThat(
      /^Bearer\s+\S+$/i.test(request.headers.get("authorization") ?? ""),
      "AUTH_REQUIRED",
    );
    let auth;
    try {
      auth = await deps.verifiedOwner(request);
    } catch {
      throw new Failure("AUTH_REQUIRED");
    }
    requireThat(
      auth && typeof auth.id === "string" && UUID.test(auth.id) &&
        auth.isAnonymous === false,
      "AUTH_REQUIRED",
    );
    const owner = auth.id;
    if (request.method === "POST") {
      requireThat(await deps.isEnabled() === true, "DRAFT_DISABLED");
    }
    const body = request.method === "POST"
      ? await readRequestJSON(request)
      : {};
    if (request.method === "POST") {
      validateBody(body, kind === "approve" ? "approve" : kind);
    }
    if (kind === "create") {
      const jobID = body.job_id as string,
        key = body.client_request_id as string;
      const replay = await deps.loadOwnedSessionByCreationKey(owner, key);
      if (replay !== null && replay !== undefined) {
        const s = owned(replay, owner, { client_request_id: key });
        requireThat(s.job_id === jobID, "IDEMPOTENCY_CONFLICT");
        return json(session(s));
      }
      const j = owned(await deps.loadOwnedJob(owner, jobID), owner, {
        id: jobID,
      });
      requireThat(j.status === "completed", "JOB_NOT_READY");
      requireThat(scalarString(j.source_fingerprint, 1, 512));
      const ctx = context(j.result, false, "INVALID_INPUT");
      const fingerprint = await contextHash(
        { job_id: jobID, source_fingerprint: j.source_fingerprint },
        ctx,
        "1",
      );
      const output = rpcObject(
        await deps.rpc("create_recipe_draft_session", {
          p_owner_id: owner,
          p_client_request_id: key,
          p_job_id: jobID,
          p_expected_job_result: j.result,
          p_base_context: ctx,
          p_base_context_hash: fingerprint,
          p_enabled: true,
        }),
      );
      requireThat(output.outcome === "created" || output.outcome === "replay");
      return json(
        session(
          owned(output.session, owner, {
            job_id: jobID,
            client_request_id: key,
          }),
        ),
        output.outcome === "created" ? 201 : 200,
      );
    }
    const sessionID = parts[1];
    const s = owned(await deps.loadOwnedSession(owner, sessionID), owner, {
      id: sessionID,
    });
    const wireSession = session(s);
    if (kind === "session") return json(wireSession);
    if (kind === "claim") {
      const result = rpcObject(
        await deps.rpc("claim_recipe_draft_turn", {
          p_owner_id: owner,
          p_session_id: sessionID,
          p_request_id: body.request_id,
          p_expected_revision: body.expected_revision,
          p_message: body.message,
          p_request_hash: await canonicalHash(body),
          p_context_hash: wireSession.context_hash,
          p_enabled: true,
        }),
      );
      requireThat(result.outcome === "accepted" || result.outcome === "replay");
      const output = await turn(
        object(result.turn),
        owner,
        sessionID,
        body.request_id as string,
        deps,
      );
      return json(output, output.state === "pending" ? 202 : 200);
    }
    const turnID = parts[3];
    const t = owned(await deps.loadOwnedTurn(owner, sessionID, turnID), owner, {
      session_id: sessionID,
      request_id: turnID,
    });
    if (kind === "turn") {
      return json(await turn(t, owner, sessionID, turnID, deps));
    }
    // A stale approval may be an exact durable replay: storage checks its key before CAS.
    // Never reject it on current proposal/revision/max checks before that authoritative replay.
    let next: Row | null = null;
    let nextHash = wireSession.context_hash;
    if (
      revision(body.expected_revision) === wireSession.revision &&
      BigInt(wireSession.revision as string) < MAX_REV
    ) {
      next = approvalContext(s, t, body);
      nextHash = await contextHash(
        s,
        next,
        (BigInt(wireSession.revision as string) + 1n).toString(),
      );
    }
    const output = rpcObject(
      await deps.rpc("approve_recipe_draft_turn", {
        p_owner_id: owner,
        p_session_id: sessionID,
        p_turn_request_id: turnID,
        p_request_id: body.request_id,
        p_expected_revision: body.expected_revision,
        p_action: body.action,
        p_selected_paths: body.selected_paths,
        p_approval_hash: await canonicalHash(body),
        p_next_context: next,
        p_next_context_hash: nextHash,
        p_enabled: true,
      }),
    );
    const r = receipt(output.receipt, sessionID, turnID);
    requireThat(
      r.request_id === body.request_id && r.action === body.action &&
        canonicalJSON(r.selected_paths) === canonicalJSON(body.selected_paths),
    );
    return json(r);
  } catch (error) {
    const code = error instanceof Failure || error instanceof RequestJSONError
      ? error.code
      : "INTERNAL_ERROR";
    const status = statuses[code] ?? 500;
    return json({
      code: status === 500 ? "INTERNAL_ERROR" : code,
      message: status === 404
        ? "Resource not found."
        : status === 500
        ? "Request failed."
        : "Draft request could not be completed.",
      recoverable: [409, 429, 503].includes(status),
      request_id: crypto.randomUUID(),
    }, status);
  }
}
