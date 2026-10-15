// Developer: gengyun
// Purpose: Bind the fixed owner-scoped recipe edit proposal RPCs to a service-role PostgREST client.

import {
  type ApproveProposalInput,
  type ApproveProposalResult,
  type CreateProposalInput,
  type CreateProposalResult,
  Failure,
  type ProposalBackend,
  type ProposalRow,
} from "./handler.ts";
import { validEditChanges } from "./editSchema.ts";

type Row = Record<string, unknown>;
const MAX_BYTES = 4194304;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const COLUMNS = [
  "id",
  "owner_id",
  "operation_id",
  "intent",
  "recipe_id",
  "source_revision",
  "snapshot_hash",
  "input_hash",
  "status",
  "changes",
  "reasons",
  "warnings",
  "needs_manual_edit",
  "payload_hash",
  "approved_payload",
  "created_at",
  "updated_at",
];
const RPC: Record<string, string[]> = {
  create_recipe_edit_proposal: [
    "p_owner_id",
    "p_operation_id",
    "p_intent",
    "p_recipe_id",
    "p_source_revision",
    "p_snapshot_hash",
    "p_input_hash",
    "p_changes",
    "p_reasons",
    "p_warnings",
    "p_needs_manual_edit",
  ],
  approve_recipe_edit_proposal: [
    "p_owner_id",
    "p_proposal_id",
    "p_changes",
    "p_expected_snapshot_hash",
    "p_payload_hash",
  ],
};
const RPC_CODES = new Set([
  "INVALID_INPUT",
  "NOT_FOUND",
  "IDEMPOTENCY_CONFLICT",
  "STALE_REVISION",
  "ALREADY_REJECTED",
  "NEEDS_MANUAL_EDIT",
]);

export interface BackendAdapterOptions {
  enabled?: boolean;
  supabaseRESTBaseURL: URL;
  serviceRoleKey: string;
  postgrestTransport: (
    request: Request,
    policy: { signal: AbortSignal; maxResponseBytes: number },
  ) => Promise<Response>;
  requestTimeoutMs?: number;
}

function object(value: unknown): value is Row {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireThat(condition: unknown, code: string): asserts condition {
  if (!condition) throw new Failure(code);
}

function quoted(value: string): string {
  return `eq."${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function wait<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(new Failure("INTERNAL_ERROR"));
  const { promise: result, resolve, reject } = Promise.withResolvers<T>();
  const onAbort = () => reject(new Failure("INTERNAL_ERROR"));
  signal.addEventListener("abort", onAbort, { once: true });
  promise.then(
    (value) => {
      signal.removeEventListener("abort", onAbort);
      resolve(value);
    },
    () => {
      signal.removeEventListener("abort", onAbort);
      reject(new Failure("INTERNAL_ERROR"));
    },
  );
  return result;
}

function discard(response: Response) {
  void response.body?.cancel().catch(() => {});
}

function projectProposal(value: unknown): ProposalRow {
  requireThat(object(value), "INTERNAL_ERROR");
  const row = Object.fromEntries(
    COLUMNS.filter((key) => key in value).map((key) => [key, value[key]]),
  ) as unknown as ProposalRow;
  requireThat(UUID.test(row.id), "INTERNAL_ERROR");
  requireThat(UUID.test(row.owner_id), "INTERNAL_ERROR");
  requireThat(UUID.test(row.operation_id), "INTERNAL_ERROR");
  requireThat(UUID.test(row.recipe_id), "INTERNAL_ERROR");
  requireThat(
    row.intent === "substitute" || row.intent === "simplify" ||
      row.intent === "dietary",
    "INTERNAL_ERROR",
  );
  requireThat(
    row.status === "generated" || row.status === "approved" ||
      row.status === "rejected",
    "INTERNAL_ERROR",
  );
  requireThat(
    typeof row.source_revision === "string" && row.source_revision.length > 0,
    "INTERNAL_ERROR",
  );
  requireThat(HASH.test(row.snapshot_hash), "INTERNAL_ERROR");
  requireThat(HASH.test(row.input_hash), "INTERNAL_ERROR");
  requireThat(Array.isArray(row.changes), "INTERNAL_ERROR");
  requireThat(Array.isArray(row.reasons), "INTERNAL_ERROR");
  requireThat(Array.isArray(row.warnings), "INTERNAL_ERROR");
  requireThat(typeof row.needs_manual_edit === "boolean", "INTERNAL_ERROR");
  if (row.payload_hash !== null && row.payload_hash !== undefined) {
    requireThat(HASH.test(row.payload_hash), "INTERNAL_ERROR");
  }
  if (row.approved_payload !== null && row.approved_payload !== undefined) {
    requireThat(Array.isArray(row.approved_payload), "INTERNAL_ERROR");
  }
  return row;
}

/**
 * Construction is closed by default. Every backend request requires an explicit trusted transport.
 */
export function createRecipeEditBackendAdapter(
  options: Partial<BackendAdapterOptions> = {},
): ProposalBackend {
  const timeout = options.requestTimeoutMs ?? 5000;
  let base: URL | null = null;
  let key = "";
  let enabled = false;
  let transport = options.postgrestTransport;
  try {
    if (options.enabled === true && options.supabaseRESTBaseURL) {
      const u = new URL(options.supabaseRESTBaseURL.href);
      requireThat(
        u.protocol === "https:" && u.hostname && !u.username && !u.password &&
          !u.search && !u.hash && u.pathname === "/rest/v1",
        "INTERNAL_ERROR",
      );
      requireThat(
        typeof options.serviceRoleKey === "string" &&
          options.serviceRoleKey.length > 0 &&
          !/[\r\n]/.test(options.serviceRoleKey),
        "INTERNAL_ERROR",
      );
      requireThat(typeof transport === "function", "INTERNAL_ERROR");
      base = u;
      key = options.serviceRoleKey;
      enabled = true;
    }
  } catch {
    // Misconfiguration leaves the adapter closed; every call then fails as unavailable.
  }

  async function bounded<T>(
    operation: (signal: AbortSignal) => Promise<T>,
  ): Promise<T> {
    requireThat(enabled, "USAGE_UNAVAILABLE");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const result = await wait(
        operation(controller.signal),
        controller.signal,
      );
      return result;
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }

  async function request(
    path: string,
    method: "GET" | "POST",
    params?: URLSearchParams,
    body?: string,
  ): Promise<unknown> {
    return await bounded(async (signal) => {
      const url = new URL(`${base!.href}/${path}`);
      if (params) url.search = params.toString();
      const req = new Request(url, {
        method,
        redirect: "error",
        signal,
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body }),
      });
      const response = await wait(
        transport!(req, { signal, maxResponseBytes: MAX_BYTES }),
        signal,
      );
      if (
        !response.ok || response.redirected ||
        response.type === "opaqueredirect" ||
        !/^application\/json(?:;|$)/i.test(
          response.headers.get("content-type") ?? "",
        )
      ) {
        discard(response);
        throw new Failure("INTERNAL_ERROR");
      }
      if (!response.body) {
        discard(response);
        throw new Failure("INTERNAL_ERROR");
      }
      const reader = response.body.getReader();
      const cancel = () => void reader.cancel().catch(() => {});
      signal.addEventListener("abort", cancel, { once: true });
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        for (;;) {
          const part = await wait(reader.read(), signal);
          if (part.done) break;
          size += part.value.length;
          if (size > MAX_BYTES) {
            cancel();
            throw new Failure("INTERNAL_ERROR");
          }
          chunks.push(part.value);
        }
        const bytes = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        return JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      } finally {
        signal.removeEventListener("abort", cancel);
        try {
          reader.releaseLock();
        } catch {
          // Pending cancellation can still own the reader.
        }
      }
    });
  }

  async function rpc(name: string, args: Row): Promise<Row> {
    requireThat(Object.hasOwn(RPC, name) && object(args), "INTERNAL_ERROR");
    const allowed = RPC[name];
    requireThat(
      Object.keys(args).length === allowed.length &&
        allowed.every((k) => Object.hasOwn(args, k)),
      "INTERNAL_ERROR",
    );
    for (const [param, value] of Object.entries(args)) {
      if (param.endsWith("_id") || param.endsWith("_owner_id")) {
        requireThat(
          typeof value === "string" && UUID.test(value),
          "INTERNAL_ERROR",
        );
      }
      if (param.endsWith("_hash")) {
        requireThat(
          typeof value === "string" && HASH.test(value),
          "INTERNAL_ERROR",
        );
      }
      if (
        param === "p_changes" || param === "p_reasons" || param === "p_warnings"
      ) {
        requireThat(Array.isArray(value), "INTERNAL_ERROR");
      }
    }
    const result = await request(
      `rpc/${name}`,
      "POST",
      undefined,
      JSON.stringify(args),
    );
    requireThat(object(result), "INTERNAL_ERROR");
    if ("code" in result) {
      requireThat(
        typeof result.code === "string" && RPC_CODES.has(result.code),
        "INTERNAL_ERROR",
      );
      throw new Failure(result.code);
    }
    requireThat(object(result.proposal), "INTERNAL_ERROR");
    return {
      outcome: result.outcome as string,
      proposal: projectProposal(result.proposal),
    };
  }

  async function readProposal(
    filters: Record<string, string>,
  ): Promise<ProposalRow | null> {
    const params = new URLSearchParams({
      select: COLUMNS.join(","),
      limit: "2",
    });
    for (const [name, value] of Object.entries(filters)) {
      requireThat(UUID.test(value), "INTERNAL_ERROR");
      params.set(name, quoted(value));
    }
    const result = await request("recipe_edit_proposals", "GET", params);
    requireThat(Array.isArray(result) && result.length <= 1, "INTERNAL_ERROR");
    if (result.length === 0) return null;
    const row = projectProposal(result[0]);
    for (const [name, value] of Object.entries(filters)) {
      requireThat(
        (row as unknown as Record<string, unknown>)[name] === value,
        "INTERNAL_ERROR",
      );
    }
    return row;
  }

  async function getProposal(
    ownerId: string,
    id: string,
  ): Promise<ProposalRow | null> {
    return readProposal({ owner_id: ownerId, id });
  }

  async function getProposalByOperation(
    ownerId: string,
    operationId: string,
  ): Promise<ProposalRow | null> {
    return readProposal({ owner_id: ownerId, operation_id: operationId });
  }

  return {
    async createProposal(
      input: CreateProposalInput,
    ): Promise<CreateProposalResult> {
      const result = await rpc("create_recipe_edit_proposal", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
        p_intent: input.intent,
        p_recipe_id: input.recipeId,
        p_source_revision: input.sourceRevision,
        p_snapshot_hash: input.snapshotHash,
        p_input_hash: input.inputHash,
        p_changes: input.changes,
        p_reasons: input.reasons,
        p_warnings: input.warnings,
        p_needs_manual_edit: input.needsManualEdit,
      });
      requireThat(
        result.outcome === "created" || result.outcome === "replay",
        "INTERNAL_ERROR",
      );
      return {
        outcome: result.outcome,
        proposal: result.proposal as ProposalRow,
      };
    },
    getProposal,
    getProposalByOperation,
    async approveProposal(
      input: ApproveProposalInput,
    ): Promise<ApproveProposalResult> {
      requireThat(validEditChanges(input.changes), "INVALID_INPUT");
      const result = await rpc("approve_recipe_edit_proposal", {
        p_owner_id: input.ownerId,
        p_proposal_id: input.proposalId,
        p_changes: input.changes,
        p_expected_snapshot_hash: input.expectedSnapshotHash,
        p_payload_hash: input.payloadHash,
      });
      requireThat(
        result.outcome === "approved" || result.outcome === "replay",
        "INTERNAL_ERROR",
      );
      return {
        outcome: result.outcome,
        proposal: result.proposal as ProposalRow,
      };
    },
  };
}
