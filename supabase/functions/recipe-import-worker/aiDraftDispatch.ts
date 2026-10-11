// Developer: gengyun
// Purpose: Dispatch existing durable draft turns through fenced storage and injected provider transport.

import { createAIDraftTurnService } from "./aiDraftTurn.ts";
import { createOpenAIDraftProvider } from "./aiDraftProvider.ts";

type RPCName =
  | "recover_recipe_draft_turn"
  | "mark_recipe_draft_turn_dispatched"
  | "finish_recipe_draft_turn";
type ProviderOptions = Parameters<typeof createOpenAIDraftProvider>[0];
type RouteConfiguration = Pick<ProviderOptions, "route" | "model" | "provider">;
type GenerationResult =
  | { status: "no_review_needed" }
  | { status: "rejected" | "unavailable"; code: string }
  | {
    status: "proposal";
    origin: "AI_suggested";
    requires_approval: true;
    questions: unknown[];
    suggestions: unknown[];
  };
interface Input {
  ownerID: string;
  sessionID: string;
  requestID: string;
  signal?: AbortSignal;
}
export type AIDraftDispatchResult =
  | { state: "disabled" }
  | {
    state: "pending";
    ownerID: string;
    sessionID: string;
    requestID: string;
    recoveryNeeded: boolean;
    code: "IN_PROGRESS" | "RECOVERY_REQUIRED";
  }
  | {
    state: "terminal";
    ownerID: string;
    sessionID: string;
    requestID: string;
    result: GenerationResult;
  }
  | {
    state: "rejected";
    code:
      | "INVALID_INPUT"
      | "INVALID_CONFIGURATION"
      | "INVALID_STORAGE_RESPONSE"
      | "NOT_FOUND";
  };
interface Options {
  enabled?: boolean;
  storage: (
    name: RPCName,
    args: Record<string, unknown>,
    policy: { signal: AbortSignal },
  ) => Promise<unknown>;
  loadRouteConfiguration: (
    signal: AbortSignal,
  ) => Promise<RouteConfiguration | null>;
  resolveSecret: (reference: string, signal: AbortSignal) => Promise<string>;
  safeTransport: ProviderOptions["transport"];
  outerTimeoutMs?: number;
}
interface Turn extends Record<string, unknown> {
  owner_id: string;
  session_id: string;
  request_id: string;
  fencing_token: string;
  based_revision: string;
  context_hash: string;
  request_hash: string;
  lease_expires_at: string;
  state: "pending" | "terminal";
  dispatch_state: "predispatch" | "dispatched_unknown" | "settled";
  request_body: {
    request_id: string;
    expected_revision: string;
    message: string;
  };
  context_snapshot: Record<string, unknown>;
  result?: unknown;
}
const codes = new Set([
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
]);
const object = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === "object" && !Array.isArray(v);
const uuid = (v: unknown): v is string =>
  typeof v === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
const hash = (v: unknown): v is string =>
  typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const revision = (v: unknown): v is string =>
  typeof v === "string" && /^[1-9][0-9]{0,18}$/.test(v) &&
  BigInt(v) <= 9223372036854775807n;
const keys = (v: Record<string, unknown>, expected: string[]) =>
  Object.keys(v).length === expected.length && expected.every((k) => k in v);
const bounded = (v: unknown, n: number): v is string =>
  typeof v === "string" && [...v].length > 0 && [...v].length <= n;
const path = (v: unknown): v is string =>
  typeof v === "string" &&
  /^(title|servings|ingredients\[(?:[0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[(?:[0-9]|[1-9][0-9])\]\.instruction)$/
    .test(v);

// This validates the persisted wire shape, not evidence grounding; DEV-283 owns that algorithm.
function validResult(v: unknown): v is GenerationResult {
  if (
    !object(v) || new TextEncoder().encode(JSON.stringify(v)).length > 65536
  ) return false;
  if (v.status === "no_review_needed") return keys(v, ["status"]);
  if (v.status === "rejected" || v.status === "unavailable") {
    return keys(v, ["status", "code"]) && typeof v.code === "string" &&
      codes.has(v.code);
  }
  if (
    v.status !== "proposal" ||
    !keys(v, [
      "status",
      "origin",
      "requires_approval",
      "questions",
      "suggestions",
    ]) ||
    v.origin !== "AI_suggested" || v.requires_approval !== true ||
    !Array.isArray(v.questions) || v.questions.length > 3 ||
    !Array.isArray(v.suggestions) || v.suggestions.length > 20
  ) return false;
  for (
    const [items, question] of [[v.questions, true], [
      v.suggestions,
      false,
    ]] as const
  ) {
    const seen = new Set<string>();
    for (const item of items) {
      if (
        !object(item) ||
        !(path(item.path) ||
          (question &&
            ["ingredients", "steps"].includes(item.path as string))) ||
        !Array.isArray(item.evidence_ids) || item.evidence_ids.length < 1 ||
        item.evidence_ids.length > 60 || !item.evidence_ids.every(uuid) ||
        new Set(item.evidence_ids).size !== item.evidence_ids.length ||
        !keys(
          item,
          question
            ? ["path", "question", "evidence_ids"]
            : ["path", "raw_value", "evidence_ids", "reason"],
        ) ||
        (question
          ? !bounded(item.question, 300)
          : !bounded(item.raw_value, 1500) || !bounded(item.reason, 500))
      ) return false;
      const fingerprint = JSON.stringify(item);
      if (seen.has(fingerprint)) return false;
      seen.add(fingerprint);
    }
  }
  return true;
}
function turn(value: unknown, input: Input): Turn | null {
  if (!object(value) || !object(value.turn)) return null;
  const t = value.turn;
  if (
    t.owner_id !== input.ownerID || t.session_id !== input.sessionID ||
    t.request_id !== input.requestID ||
    !uuid(t.fencing_token) || !revision(t.based_revision) ||
    !hash(t.context_hash) || !hash(t.request_hash) ||
    typeof t.lease_expires_at !== "string" ||
    !Number.isFinite(Date.parse(t.lease_expires_at)) ||
    !["pending", "terminal"].includes(t.state as string) ||
    !["predispatch", "dispatched_unknown", "settled"].includes(
      t.dispatch_state as string,
    ) ||
    !object(t.request_body) ||
    !keys(t.request_body, ["request_id", "expected_revision", "message"]) ||
    t.request_body.request_id !== t.request_id ||
    t.request_body.expected_revision !== t.based_revision ||
    typeof t.request_body.message !== "string" ||
    [...t.request_body.message].length > 2000 || !object(t.context_snapshot)
  ) return null;
  if (t.state === "terminal") {
    if (t.dispatch_state !== "settled" || !validResult(t.result)) return null;
  } else if (t.dispatch_state === "settled") return null;
  return structuredClone(t) as Turn;
}
function project(v: Record<string, unknown>): GenerationResult {
  if (v.status === "proposal") {
    const result = {
      status: "proposal",
      origin: v.origin,
      requires_approval: v.requiresApproval,
      questions: v.questions,
      suggestions: v.suggestions,
    };
    return validResult(result)
      ? result
      : { status: "rejected", code: "INVALID_PROVIDER_OUTPUT" };
  }
  if (v.status === "no_review_needed") return { status: "no_review_needed" };
  const status = v.status === "rejected" ? "rejected" : "unavailable";
  return {
    status,
    code: typeof v.code === "string" && codes.has(v.code)
      ? v.code
      : status === "rejected"
      ? "INVALID_INPUT"
      : "PROVIDER_UNAVAILABLE",
  };
}
function aborted(signal: AbortSignal) {
  if (signal.aborted) throw new Error("DISPATCH_ABORTED");
}
function within<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const abort = () => {
      cleanup();
      reject(new Error("DISPATCH_ABORTED"));
    };
    const cleanup = () => signal.removeEventListener("abort", abort);
    signal.addEventListener("abort", abort, { once: true });
    if (signal.aborted) {
      abort();
      return;
    }
    promise.then((value) => {
      cleanup();
      resolve(value);
    }, () => {
      cleanup();
      reject(new Error("DISPATCH_DEPENDENCY"));
    });
  });
}

/** No default network or durable cache. The HTTP caller must already have accepted this turn. */
export function createAIDraftDispatchWorker(options: Options) {
  return {
    async runTurn(input: Input): Promise<AIDraftDispatchResult> {
      if (options?.enabled !== true) return { state: "disabled" };
      if (
        !object(input) || !keys(
          input,
          input.signal === undefined
            ? ["ownerID", "sessionID", "requestID"]
            : ["ownerID", "sessionID", "requestID", "signal"],
        ) ||
        !uuid(input.ownerID) || !uuid(input.sessionID) ||
        !uuid(input.requestID) ||
        (input.signal !== undefined && !(input.signal instanceof AbortSignal))
      ) return { state: "rejected", code: "INVALID_INPUT" };
      const timeout = options.outerTimeoutMs ?? 10000;
      if (
        !Number.isInteger(timeout) || timeout < 1 || timeout > 10000 ||
        [
          options.storage,
          options.loadRouteConfiguration,
          options.resolveSecret,
          options.safeTransport,
        ].some((f) => typeof f !== "function")
      ) return { state: "rejected", code: "INVALID_CONFIGURATION" };
      const ids = {
        ownerID: input.ownerID,
        sessionID: input.sessionID,
        requestID: input.requestID,
      };
      const pending = (recoveryNeeded = true): AIDraftDispatchResult => ({
        state: "pending",
        ...ids,
        recoveryNeeded,
        code: recoveryNeeded ? "RECOVERY_REQUIRED" : "IN_PROGRESS",
      });
      const terminal = (t: Turn): AIDraftDispatchResult => ({
        state: "terminal",
        ...ids,
        result: structuredClone(t.result) as GenerationResult,
      });
      const controller = new AbortController();
      const signal = controller.signal;
      const abort = () => controller.abort();
      input.signal?.addEventListener("abort", abort, { once: true });
      if (input.signal?.aborted) abort();
      const deadline = performance.now() + timeout;
      const timer = setTimeout(abort, timeout);
      let closed = false;
      const check = () => {
        aborted(signal);
        if (closed || performance.now() >= deadline) {
          throw new Error("DISPATCH_CLOSED");
        }
      };
      const rpc = async (name: RPCName, args: Record<string, unknown>) => {
        check();
        const value = await within(
          Promise.resolve().then(() => {
            check();
            return options.storage(name, args, { signal });
          }),
          signal,
        );
        check();
        return value;
      };
      const ownerArgs = {
        p_owner_id: ids.ownerID,
        p_session_id: ids.sessionID,
        p_request_id: ids.requestID,
      };
      try {
        const recovered = await rpc("recover_recipe_draft_turn", {
          ...ownerArgs,
          p_enabled: true,
        });
        if (object(recovered) && "code" in recovered) {
          return {
            state: "rejected",
            code: recovered.code === "NOT_FOUND"
              ? "NOT_FOUND"
              : "INVALID_STORAGE_RESPONSE",
          };
        }
        const initial = turn(recovered, input);
        if (!initial) {
          return { state: "rejected", code: "INVALID_STORAGE_RESPONSE" };
        }
        if (initial.state === "terminal") return terminal(initial);
        if (initial.dispatch_state === "dispatched_unknown") {
          return pending(false);
        }
        const fenceArgs = {
          ...ownerArgs,
          p_fencing_token: initial.fencing_token,
        };
        let markerRequested = false;
        let markerWon = false;
        let markerTerminal: Turn | null = null;
        let invalidMarker = false;
        let capturedUsage: number | null = null;
        let sent = false;
        // A new service per durable attempt prevents its process Map from crossing sessions.
        const service = createAIDraftTurnService({
          enabled: true,
          timeoutMs: timeout,
          provider: async (providerInput) => {
            check();
            const loadedConfig = await within(
              Promise.resolve().then(() => {
                check();
                return options.loadRouteConfiguration(signal);
              }),
              signal,
            );
            check();
            // Freeze caller-owned route rows before the secret await; credentials cannot follow cache mutation.
            const config = loadedConfig ? structuredClone(loadedConfig) : null;
            if (
              !config || config.route.route_key !== "recipe_import_draft_v1" ||
              config.route.enabled !== true ||
              config.model.enabled !== true ||
              config.provider.enabled !== true ||
              config.route.primary_model_id !== config.model.id ||
              config.model.provider_id !== config.provider.id ||
              !config.provider.secret_ref
            ) throw new Error("DISPATCH_CONFIG");
            const secret = await within(
              Promise.resolve().then(() => {
                check();
                return options.resolveSecret(
                  config.provider.secret_ref!,
                  signal,
                );
              }),
              signal,
            );
            check();
            const adapter = createOpenAIDraftProvider({
              ...config,
              enabled: true,
              resolveSecret: async () => secret,
              transport: async (request, policy) => {
                check();
                aborted(policy.signal);
                if (markerRequested) throw new Error("DISPATCH_SINGLE_ATTEMPT");
                markerRequested = true;
                const marked = await rpc("mark_recipe_draft_turn_dispatched", {
                  ...fenceArgs,
                  p_enabled: true,
                });
                check();
                aborted(policy.signal);
                const row = turn(marked, input);
                if (
                  row?.state === "terminal" &&
                  row.fencing_token === initial.fencing_token &&
                  row.context_hash === initial.context_hash &&
                  row.request_hash === initial.request_hash &&
                  row.based_revision === initial.based_revision
                ) {
                  markerTerminal = row;
                  throw new Error("DISPATCH_TERMINAL");
                }
                if (
                  object(marked) && marked.code === "CLAIM_EXPIRED"
                ) throw new Error("DISPATCH_LOST");
                if (
                  !object(marked) || marked.outcome !== "dispatched" || !row ||
                  row.state !== "pending" ||
                  row.dispatch_state !== "dispatched_unknown" ||
                  row.fencing_token !== initial.fencing_token ||
                  row.context_hash !== initial.context_hash ||
                  row.request_hash !== initial.request_hash ||
                  row.based_revision !== initial.based_revision ||
                  Date.parse(row.lease_expires_at) <= Date.now()
                ) {
                  invalidMarker = true;
                  throw new Error("DISPATCH_INVALID_MARKER");
                }
                markerWon = true;
                check();
                aborted(policy.signal);
                sent = true;
                return await within(
                  Promise.resolve().then(() => {
                    check();
                    aborted(policy.signal);
                    const transportSignal = AbortSignal.any([
                      signal,
                      policy.signal,
                    ]);
                    return options.safeTransport(request, {
                      ...policy,
                      signal: transportSignal,
                    }).then((response) => {
                      if (closed || transportSignal.aborted) {
                        // The wrapper already rejected on abort; the adapter cannot see this late body.
                        try {
                          void response.body?.cancel().catch(() => {});
                        } catch { /* Best-effort, never await cleanup. */ }
                        throw new Error("DISPATCH_LATE_RESPONSE");
                      }
                      return response;
                    });
                  }),
                  signal,
                );
              },
            });
            const output = await within(
              adapter({
                ...providerInput,
                signal: AbortSignal.any([signal, providerInput.signal]),
              }),
              signal,
            );
            check();
            aborted(providerInput.signal);
            if (
              sent && markerWon && object(output) && object(output.usage) &&
              Number.isSafeInteger(output.usage.totalTokens) &&
              (output.usage.totalTokens as number) >= 0 &&
              (output.usage.totalTokens as number) <= 4096
            ) capturedUsage = output.usage.totalTokens as number;
            return output;
          },
        });
        const c = initial.context_snapshot;
        const context = {
          ownerID: ids.ownerID,
          currentRevision: initial.based_revision,
          status: c.status,
          fields: c.fields,
          evidence: c.evidence,
          reviewFields: c.review_fields,
        };
        const result = await within(
          service.generateTurn({
            ownerID: ids.ownerID,
            expectedRevision: initial.based_revision,
            requestID: ids.requestID,
            message: initial.request_body.message,
          }, context as Parameters<typeof service.generateTurn>[1]),
          signal,
        );
        check();
        if (markerTerminal) return terminal(markerTerminal);
        if (invalidMarker) {
          return { state: "rejected", code: "INVALID_STORAGE_RESPONSE" };
        }
        // A mark loser must not finish a winner sharing the same fencing token.
        if (markerRequested && !markerWon) return pending();
        const wire = project(result as Record<string, unknown>);
        const finished = await rpc("finish_recipe_draft_turn", {
          ...fenceArgs,
          p_result: wire,
          p_validated_usage: markerWon ? capturedUsage : null,
          p_expected_dispatch_state: markerWon
            ? "dispatched_unknown"
            : "predispatch",
        });
        if (object(finished) && finished.code === "CLAIM_EXPIRED") {
          return pending();
        }
        const settled = turn(finished, input);
        if (
          !settled || settled.fencing_token !== initial.fencing_token ||
          settled.context_hash !== initial.context_hash ||
          settled.request_hash !== initial.request_hash ||
          settled.based_revision !== initial.based_revision ||
          settled.state !== "terminal"
        ) return { state: "rejected", code: "INVALID_STORAGE_RESPONSE" };
        return terminal(settled);
      } catch {
        return pending();
      } finally {
        closed = true;
        clearTimeout(timer);
        input.signal?.removeEventListener("abort", abort);
        controller.abort();
      }
    },
  };
}
