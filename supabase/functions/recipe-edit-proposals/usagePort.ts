// Developer: gengyun
// Purpose: Typed commercial usage port matching the frozen DEV-425/427 settlement contract. The real
// ledger-backed port calls the service-role reservation RPCs; a fail-closed port remains for tests.

export type UsageCapability = "ai_edit";

export interface UsageReserveInput {
  ownerId: string;
  operationId: string;
  capability: UsageCapability;
  inputHash: string;
  estimatedUnits: number;
  source: Record<string, unknown>;
}

export interface UsageOperationInput {
  ownerId: string;
  operationId: string;
  capability: UsageCapability;
  inputHash: string;
}

export interface UsageFinalizeInput extends UsageOperationInput {
  source: Record<string, unknown>;
  payloadHash: string;
  payload: Record<string, unknown>;
}

export interface UsagePort {
  /** Reserve one unit. "replay" means the operation was already reserved (never re-dispatch). */
  reserve(input: UsageReserveInput): Promise<"reserved" | "replay">;
  /** Durable dispatch fence before the provider side effect. */
  markDispatched(input: UsageOperationInput): Promise<void>;
  /** Mark a known persisted generated result (switches the hold to the 24h generated window). */
  markGenerated(input: UsageOperationInput): Promise<void>;
  release(input: UsageOperationInput): Promise<void>;
  finalize(input: UsageFinalizeInput): Promise<void>;
  /** Confirm the client durably persisted the finalized save; requires a committed reservation. */
  ack(input: UsageOperationInput): Promise<void>;
}

export type UsageRPC = (
  name: string,
  args: Record<string, unknown>,
) => Promise<Record<string, unknown>>;

export class UsageUnavailableError extends Error {
  constructor(message = "The commercial usage ledger is not wired yet.") {
    super(message);
    this.name = "UsageUnavailableError";
  }
}

function rpcRow(value: Record<string, unknown>): Record<string, unknown> {
  return value ?? {};
}

function fail(code: string | undefined): never {
  if (code === "QUOTA_EXCEEDED") throw new UsageUnavailableError("Usage quota reached.");
  if (code === "UPGRADE_REQUIRED") throw new UsageUnavailableError("Premium is required.");
  if (code === "NOT_FOUND") throw new UsageUnavailableError("Operation not found.");
  if (code === "IDEMPOTENCY_CONFLICT") throw new UsageUnavailableError("Input hash conflict.");
  throw new UsageUnavailableError("The usage ledger rejected the operation.");
}

/**
 * Real UsagePort backed by the service-role DEV-427 ledger RPCs. reserve fences through
 * recipe_usage_mark_dispatched before the provider, markGenerated records the durable proposal, and
 * finalize settles once via recipe_usage_finalize.
 */
export function createLedgerUsagePort(rpc: UsageRPC): UsagePort {
  return {
    async reserve(input) {
      const row = rpcRow(await rpc("recipe_usage_reserve", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
        p_capability: input.capability,
        p_input_hash: input.inputHash,
        p_source: input.source,
      }));
      if (row.code === "RESERVED") return "reserved";
      if (row.code === "REPLAY") return "replay";
      fail(row.code as string | undefined);
    },

    async markDispatched(input) {
      const row = rpcRow(await rpc("recipe_usage_mark_dispatched", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
      }));
      if (row.code !== "DISPATCHED" && row.code !== "RESERVATION_EXPIRED") {
        fail(row.code as string | undefined);
      }
    },

    async markGenerated(input) {
      const row = rpcRow(await rpc("recipe_usage_mark_generated", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
      }));
      if (row.code !== "GENERATED" && row.code !== "RESERVATION_EXPIRED") {
        fail(row.code as string | undefined);
      }
    },

    async release(input) {
      await rpc("recipe_usage_release", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
      }).catch(() => null);
    },

    async finalize(input) {
      const row = rpcRow(await rpc("recipe_usage_finalize", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
        p_capability: input.capability,
        p_input_hash: input.inputHash,
        p_source: input.source,
        p_payload_hash: input.payloadHash,
        p_payload: input.payload,
      }));
      if (row.code !== "FINALIZED") {
        fail(row.code as string | undefined);
      }
    },

    async ack(input) {
      const row = rpcRow(await rpc("recipe_usage_ack", {
        p_owner_id: input.ownerId,
        p_operation_id: input.operationId,
      }));
      if (row.code !== "ACKED") {
        fail(row.code as string | undefined);
      }
    },
  };
}

/**
 * Fail-closed placeholder used by tests and as a default when no ledger is wired. The handler maps
 * UsageUnavailableError to a 503 so a missing ledger can never fake a settle.
 */
export function createUnavailableUsagePort(): UsagePort {
  const unavailable = (): Promise<never> =>
    Promise.reject(new UsageUnavailableError());
  return {
    reserve: unavailable,
    markDispatched: unavailable,
    markGenerated: unavailable,
    release: unavailable,
    finalize: unavailable,
    ack: unavailable,
  };
}
