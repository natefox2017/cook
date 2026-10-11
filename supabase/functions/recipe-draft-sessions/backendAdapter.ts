// Developer: gengyun
// Purpose: Bind fixed owner-scoped REST reads and lossless draft RPCs without default network access.

import type { Dependencies } from "./handler.ts";
import type { AISecret } from "../_shared/ai-secret.ts";
import type { createAIDraftDispatchWorker } from "../recipe-import-worker/aiDraftDispatch.ts";

type WorkerOptions = Parameters<typeof createAIDraftDispatchWorker>[0];
type WorkerDependencies = Pick<
  WorkerOptions,
  "storage" | "loadRouteConfiguration" | "resolveSecret"
>;
type Row = Record<string, unknown>;
export interface BackendAdapterOptions {
  enabled?: boolean;
  supabaseRESTBaseURL: URL;
  serviceRoleKey: string;
  postgrestTransport: (
    request: Request,
    policy: { signal: AbortSignal; maxResponseBytes: number },
  ) => Promise<Response>;
  authenticate: (
    request: Request,
  ) => Promise<{ user: { id: string; is_anonymous?: boolean } }>;
  decryptAISecret: (secret: AISecret, encodedKey: string) => Promise<string>;
  encodedAISecretKey: string;
  requestTimeoutMs?: number;
}
const MAX_BYTES = 4194304;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const SESSION = [
  "id",
  "owner_id",
  "job_id",
  "client_request_id",
  "source_fingerprint",
  "base_context",
  "base_context_hash",
  "effective_context",
  "effective_context_hash",
  "overlay",
  "revision",
  "reserved_tokens",
  "settled_tokens",
  "dispatch_count",
  "created_at",
  "updated_at",
];
const TURN = [
  "owner_id",
  "session_id",
  "request_id",
  "request_body",
  "request_hash",
  "based_revision",
  "context_snapshot",
  "context_hash",
  "state",
  "result",
  "fencing_token",
  "lease_expires_at",
  "dispatch_state",
  "reserved_tokens",
  "settled_tokens",
  "budget_date",
  "created_at",
  "finished_at",
];
const APPROVAL = [
  "owner_id",
  "session_id",
  "request_id",
  "turn_request_id",
  "approval_body",
  "approval_hash",
  "action",
  "selected_paths",
  "applied_revision",
  "receipt",
];
const RPC: Record<string, string[]> = {
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
const RPC_CODES = new Set([
  "DRAFT_DISABLED",
  "INVALID_INPUT",
  "NOT_FOUND",
  "JOB_NOT_READY",
  "STALE_REVISION",
  "IDEMPOTENCY_CONFLICT",
  "BUDGET_EXHAUSTED",
  "CLAIM_EXPIRED",
  "TURN_ALREADY_DECIDED",
  "REVISION_EXHAUSTED",
]);
const object = (v: unknown): v is Row =>
  typeof v === "object" && v !== null && !Array.isArray(v);
function fail(): never {
  throw new Error("DRAFT_BACKEND_UNAVAILABLE");
}
function requireThat(ok: unknown): asserts ok {
  if (!ok) fail();
}
function uuid(value: unknown): asserts value is string {
  requireThat(typeof value === "string" && UUID.test(value));
}
function rev(value: unknown): asserts value is string {
  requireThat(
    typeof value === "string" && /^[1-9][0-9]{0,18}$/.test(value) &&
      BigInt(value) <= 9223372036854775807n,
  );
}
function quoted(value: string) {
  return `eq."${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}
const nativeJSON = JSON as typeof JSON & {
  rawJSON(text: string): object;
  isRawJSON(value: unknown): boolean;
};
function lossless(text: string): unknown {
  return (JSON.parse as (
    text: string,
    reviver: (
      key: string,
      value: unknown,
      context: { source?: string },
    ) => unknown,
  ) => unknown)(text, (_key, value, context) => {
    if (typeof value !== "number") return value;
    requireThat(typeof context?.source === "string");
    return nativeJSON.rawJSON(context.source);
  });
}
function capable(): boolean {
  try {
    if (
      typeof nativeJSON.rawJSON !== "function" ||
      typeof nativeJSON.isRawJSON !== "function"
    ) return false;
    return JSON.stringify(lossless('{"number":9007199254740993}')) ===
      '{"number":9007199254740993}';
  } catch {
    return false;
  }
}
function number(
  value: unknown,
  min: number,
  max: number,
  integer = true,
): number {
  requireThat(nativeJSON.isRawJSON(value));
  const source = (value as { rawJSON: string }).rawJSON;
  requireThat(!integer || /^-?(0|[1-9][0-9]*)$/.test(source));
  const n = Number(source);
  requireThat(
    Number.isFinite(n) && (!integer || Number.isSafeInteger(n)) && n >= min &&
      n <= max,
  );
  return n;
}
function plain(value: unknown): void {
  requireThat(!nativeJSON.isRawJSON(value));
  requireThat(typeof value !== "number" || Number.isFinite(value));
  requireThat(
    value !== undefined && typeof value !== "function" &&
      typeof value !== "symbol" && typeof value !== "bigint",
  );
  if (Array.isArray(value)) { for (const item of value) plain(item); }
  else if (object(value)) {
    for (const item of Object.values(value)) {
      plain(item);
    }
  }
}
function freeze(value: unknown): void {
  if (value !== null && typeof value === "object") {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
}
function projectRow(
  value: unknown,
  kind: "session" | "turn" | "approval",
): Row {
  requireThat(object(value));
  const columns = kind === "session"
    ? SESSION
    : kind === "turn"
    ? TURN
    : APPROVAL;
  const row = Object.fromEntries(
    columns.filter((k) => k in value).map((k) => [k, value[k]]),
  );
  uuid(row.owner_id);
  if (kind === "session") {
    rev(row.revision);
    row.reserved_tokens = number(row.reserved_tokens, 0, 32768);
    row.settled_tokens = number(row.settled_tokens, 0, 32768);
    row.dispatch_count = number(row.dispatch_count, 0, 8);
    requireThat(
      (row.reserved_tokens as number) + (row.settled_tokens as number) <= 32768,
    );
  } else if (kind === "turn") {
    rev(row.based_revision);
    row.reserved_tokens = number(row.reserved_tokens, 0, 4096);
    row.settled_tokens = number(row.settled_tokens, 0, 4096);
    requireThat(
      (row.reserved_tokens as number) + (row.settled_tokens as number) <= 4096,
    );
  } else rev(row.applied_revision);
  plain(row);
  return row;
}
function wait<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const abort = () => {
      cleanup();
      reject(new Error("DRAFT_BACKEND_UNAVAILABLE"));
    };
    const cleanup = () => signal.removeEventListener("abort", abort);
    signal.addEventListener("abort", abort, { once: true });
    promise.then((value) => {
      cleanup();
      signal.aborted
        ? reject(new Error("DRAFT_BACKEND_UNAVAILABLE"))
        : resolve(value);
    }, () => {
      cleanup();
      reject(new Error("DRAFT_BACKEND_UNAVAILABLE"));
    });
    if (signal.aborted) abort();
  });
}
function discard(response: Response) {
  try {
    void response.body?.cancel().catch(() => {});
  } catch { /* Never await cleanup. */ }
}

/** Construction is closed by default. Every backend request requires explicit trusted transport. */
export function createRecipeDraftBackendAdapter(
  options: Partial<BackendAdapterOptions> = {},
): {
  handlerDependencies: Dependencies;
  workerDependencies: WorkerDependencies;
} {
  const timeout = options.requestTimeoutMs ?? 5000;
  let base: URL | null = null;
  let enabled = false;
  try {
    if (options.enabled === true) {
      const u = new URL(options.supabaseRESTBaseURL!.href);
      requireThat(
        u.protocol === "https:" && u.hostname && !u.username && !u.password &&
          !u.search && !u.hash && u.pathname === "/rest/v1",
      );
      requireThat(
        typeof options.serviceRoleKey === "string" &&
          options.serviceRoleKey.length > 0 &&
          !/[\r\n]/.test(options.serviceRoleKey),
      );
      requireThat(
        typeof options.encodedAISecretKey === "string" &&
          options.encodedAISecretKey.length > 0,
      );
      requireThat(
        [
          options.postgrestTransport,
          options.authenticate,
          options.decryptAISecret,
        ].every((f) => typeof f === "function"),
      );
      requireThat(
        Number.isInteger(timeout) && timeout >= 1 && timeout <= 10000 &&
          capable(),
      );
      base = u;
      enabled = true;
    }
  } catch { /* Misconfiguration leaves every dependency closed. */ }
  // Only provenance, not owner authorization or durable state; full snapshots are never rounded/cloned.
  const snapshots = new WeakMap<object, { owner: string; job: string }>();
  const key = options.serviceRoleKey;
  const encryptionKey = options.encodedAISecretKey;
  const transport = options.postgrestTransport;
  const authenticate = options.authenticate;
  const decrypt = options.decryptAISecret;
  async function bounded<T>(
    operation: (signal: AbortSignal, check: () => void) => Promise<T>,
    outer?: AbortSignal,
  ): Promise<T> {
    requireThat(enabled);
    const controller = new AbortController();
    const abort = () => controller.abort();
    outer?.addEventListener("abort", abort, { once: true });
    if (outer?.aborted) abort();
    const deadline = performance.now() + timeout;
    const timer = setTimeout(abort, timeout);
    const check = () => {
      if (performance.now() >= deadline) controller.abort();
      requireThat(!controller.signal.aborted);
    };
    try {
      requireThat(!controller.signal.aborted);
      const result = await wait(
        Promise.resolve().then(() => {
          requireThat(
            !controller.signal.aborted && performance.now() < deadline,
          );
          return operation(controller.signal, check);
        }),
        controller.signal,
      );
      requireThat(!controller.signal.aborted && performance.now() < deadline);
      return result;
    } finally {
      clearTimeout(timer);
      outer?.removeEventListener("abort", abort);
      controller.abort();
    }
  }
  async function request(
    path: string,
    method: "GET" | "POST",
    params?: URLSearchParams,
    body?: string,
    outer?: AbortSignal,
  ): Promise<unknown> {
    return await bounded(async (signal, check) => {
      const url = new URL(`${base!.href}/${path}`);
      if (params) url.search = params.toString();
      const req = new Request(url, {
        method,
        redirect: "error",
        signal,
        headers: {
          apikey: key!,
          Authorization: `Bearer ${key}`,
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body }),
      });
      const raw = Promise.resolve().then(() => {
        check();
        return transport!(req, { signal, maxResponseBytes: MAX_BYTES });
      }).then((response) => {
        try {
          check();
        } catch {
          discard(response);
          fail();
        }
        return response;
      });
      const response = await wait(raw, signal);
      if (
        !response.ok || response.redirected ||
        response.type === "opaqueredirect" ||
        (response.url && response.url !== req.url) ||
        !/^application\/json(?:;|$)/i.test(
          response.headers.get("content-type") ?? "",
        )
      ) {
        discard(response);
        fail();
      }
      const length = response.headers.get("content-length");
      if (
        length && /^\d+$/.test(length) && BigInt(length) > BigInt(MAX_BYTES)
      ) {
        discard(response);
        fail();
      }
      requireThat(response.body);
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      const cancel = () => {
        void reader.cancel().catch(() => {});
      };
      signal.addEventListener("abort", cancel, { once: true });
      try {
        while (true) {
          const part = await wait(reader.read(), signal);
          check();
          if (part.done) break;
          size += part.value.length;
          if (size > MAX_BYTES) {
            cancel();
            fail();
          }
          chunks.push(part.value);
        }
        check();
        const bytes = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        return lossless(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      } finally {
        signal.removeEventListener("abort", cancel);
        try {
          reader.releaseLock();
        } catch { /* Pending cancellation can still own the reader. */ }
      }
    }, outer);
  }
  async function read(
    table: string,
    select: string,
    filters: Row,
    outer?: AbortSignal,
  ): Promise<Row | null> {
    const params = new URLSearchParams({ select, limit: "2" });
    for (const [name, value] of Object.entries(filters)) {
      requireThat(typeof value === "string" || typeof value === "boolean");
      params.set(
        name,
        typeof value === "boolean" ? `eq.${value}` : quoted(value),
      );
    }
    const result = await request(table, "GET", params, undefined, outer);
    requireThat(Array.isArray(result) && result.length <= 1);
    if (!result.length) return null;
    requireThat(object(result[0]));
    for (const [name, value] of Object.entries(filters)) {
      requireThat(result[0][name] === value);
    }
    return result[0];
  }
  async function owned(
    table: string,
    kind: "job" | "session" | "turn" | "approval",
    owner: string,
    filters: Row,
  ) {
    uuid(owner);
    for (const value of Object.values(filters)) uuid(value);
    const cols = kind === "job"
      ? ["id", "owner_id", "status", "source_fingerprint", "result"]
      : kind === "session"
      ? SESSION
      : kind === "turn"
      ? TURN
      : APPROVAL;
    const cast = kind === "session"
      ? "revision"
      : kind === "turn"
      ? "based_revision"
      : kind === "approval"
      ? "applied_revision"
      : null;
    const row = await read(
      table,
      cols.map((k) => k === cast ? `${k}::text` : k).join(","),
      { owner_id: owner, ...filters },
    );
    if (!row) return null;
    if (kind === "job") {
      requireThat(object(row.result));
      freeze(row.result);
      snapshots.set(row.result, { owner, job: row.id as string });
      return row;
    }
    return projectRow(row, kind);
  }
  async function rpc(
    name: string,
    args: Row,
    signal?: AbortSignal,
  ): Promise<unknown> {
    requireThat(Object.hasOwn(RPC, name) && object(args));
    const allowed = RPC[name];
    requireThat(
      Object.keys(args).length === allowed.length &&
        allowed.every((k) => Object.hasOwn(args, k)),
    );
    for (const [param, value] of Object.entries(args)) {
      if (
        /^p_(owner_id|session_id|job_id|client_request_id|request_id|turn_request_id|fencing_token)$/
          .test(param)
      ) uuid(value);
      if (param.endsWith("_hash")) {
        requireThat(typeof value === "string" && HASH.test(value));
      }
    }
    for (const field of ["p_base_context", "p_next_context", "p_result"]) {
      if (field in args) {
        requireThat(
          object(args[field]) ||
            (name === "approve_recipe_draft_turn" &&
              field === "p_next_context" && args[field] === null),
        );
        plain(args[field]);
      }
    }
    if ("p_enabled" in args) requireThat(args.p_enabled === true);
    if ("p_expected_revision" in args) rev(args.p_expected_revision);
    if (name === "create_recipe_draft_session") {
      requireThat(object(args.p_expected_job_result));
      const source = snapshots.get(args.p_expected_job_result);
      requireThat(
        source && source.owner === args.p_owner_id &&
          source.job === args.p_job_id,
      );
    }
    if (name === "claim_recipe_draft_turn") {
      requireThat(
        typeof args.p_message === "string" &&
          [...args.p_message].length <= 2000,
      );
    }
    if (name === "finish_recipe_draft_turn") {
      requireThat(
        args.p_expected_dispatch_state === "predispatch" ||
          args.p_expected_dispatch_state === "dispatched_unknown",
      );
      requireThat(
        args.p_validated_usage === null ||
          (Number.isSafeInteger(args.p_validated_usage) &&
            (args.p_validated_usage as number) >= 0 &&
            (args.p_validated_usage as number) <= 4096),
      );
    }
    if (name === "approve_recipe_draft_turn") {
      requireThat(
        (args.p_action === "accept" || args.p_action === "reject") &&
          Array.isArray(args.p_selected_paths) &&
          args.p_selected_paths.length <= 20 &&
          args.p_selected_paths.every((v) =>
            typeof v === "string" &&
            /^(title|servings|ingredients\[(?:[0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[(?:[0-9]|[1-9][0-9])\]\.instruction)$/
              .test(v)
          ) &&
          new Set(args.p_selected_paths).size ===
            args.p_selected_paths.length &&
          (args.p_action === "accept"
            ? args.p_selected_paths.length > 0
            : args.p_selected_paths.length === 0),
      );
    }
    const body = JSON.stringify(args);
    requireThat(new TextEncoder().encode(body).length <= MAX_BYTES);
    const result = await request(
      `rpc/${name}`,
      "POST",
      undefined,
      body,
      signal,
    );
    requireThat(object(result));
    if ("code" in result) {
      requireThat(
        typeof result.code === "string" && RPC_CODES.has(result.code),
      );
      return { code: result.code };
    }
    const output: Row = {};
    if ("outcome" in result) {
      requireThat(
        ["created", "accepted", "replay", "dispatched"].includes(
          result.outcome as string,
        ),
      );
      output.outcome = result.outcome;
    }
    if ("session" in result) {
      output.session = projectRow(result.session, "session");
    }
    if ("turn" in result) output.turn = projectRow(result.turn, "turn");
    if ("receipt" in result) {
      plain(result.receipt);
      output.receipt = result.receipt;
    }
    requireThat("session" in output || "turn" in output || "receipt" in output);
    return output;
  }
  const routeLoader: WorkerDependencies["loadRouteConfiguration"] = async (
    signal,
  ) => {
    const route = await read(
      "ai_routes",
      "route_key,primary_model_id,enabled,timeout_ms,max_retries,max_output_tokens,temperature",
      { route_key: "recipe_import_draft_v1", enabled: true },
      signal,
    );
    if (!route || route.enabled !== true) return null;
    uuid(route.primary_model_id);
    const model = await read(
      "ai_models",
      "id,provider_id,upstream_model_id,display_name,enabled,created_at",
      { id: route.primary_model_id, enabled: true },
      signal,
    );
    if (!model || model.enabled !== true) return null;
    uuid(model.provider_id);
    const provider = await read(
      "ai_providers",
      "id,name,base_url,secret_ref,enabled,updated_at",
      { id: model.provider_id, enabled: true },
      signal,
    );
    if (
      !provider || provider.enabled !== true ||
      typeof provider.secret_ref !== "string" ||
      !provider.secret_ref.length || provider.secret_ref.length > 512
    ) return null;
    const normalizedRoute = {
      ...route,
      timeout_ms: number(route.timeout_ms, 1000, 300000),
      max_retries: number(route.max_retries, 0, 3),
      max_output_tokens: number(route.max_output_tokens, 1, 4096),
      temperature: route.temperature === null
        ? null
        : number(route.temperature, 0, 2, false),
    };
    plain(normalizedRoute);
    plain(model);
    plain(provider);
    return { route: normalizedRoute, model, provider } as Awaited<
      ReturnType<WorkerDependencies["loadRouteConfiguration"]>
    >;
  };
  return {
    handlerDependencies: {
      isEnabled: () => enabled,
      verifiedOwner: async (request) => {
        if (!enabled) return null;
        try {
          const result = await bounded(
            () => authenticate!(request),
            request.signal,
          );
          uuid(result.user.id);
          return result.user.is_anonymous === false
            ? { id: result.user.id, isAnonymous: false }
            : null;
        } catch {
          return null;
        }
      },
      loadOwnedJob: (owner, job) =>
        owned("recipe_import_jobs", "job", owner, { id: job }),
      loadOwnedSession: (owner, session) =>
        owned("recipe_draft_sessions", "session", owner, { id: session }),
      loadOwnedSessionByCreationKey: (owner, key) =>
        owned("recipe_draft_sessions", "session", owner, {
          client_request_id: key,
        }),
      loadOwnedTurn: (owner, session, turn) =>
        owned("recipe_draft_turns", "turn", owner, {
          session_id: session,
          request_id: turn,
        }),
      loadOwnedApprovalForTurn: (owner, session, turn) =>
        owned("recipe_draft_approvals", "approval", owner, {
          session_id: session,
          turn_request_id: turn,
        }),
      rpc: (name, args) => rpc(name, args),
    },
    workerDependencies: {
      storage: (name, args, policy) => rpc(name, args, policy.signal),
      loadRouteConfiguration: routeLoader,
      resolveSecret: async (reference, signal) => {
        const config = await routeLoader(signal);
        requireThat(config && config.provider.secret_ref === reference);
        const secret = await read(
          "ai_secrets",
          "secret_ref,ciphertext,nonce,key_version",
          { secret_ref: reference },
          signal,
        );
        requireThat(
          secret && typeof secret.ciphertext === "string" &&
            typeof secret.nonce === "string",
        );
        const version = number(secret.key_version, 2, 2);
        return await bounded(
          () =>
            decrypt!({
              secret_ref: reference,
              ciphertext: secret.ciphertext as string,
              nonce: secret.nonce as string,
              key_version: version,
            }, encryptionKey!),
          signal,
        );
      },
    },
  };
}
