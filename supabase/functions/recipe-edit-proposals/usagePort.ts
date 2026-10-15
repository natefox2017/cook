// Developer: gengyun
// Purpose: Typed commercial usage port matching the frozen DEV-425/427 settlement contract.
// The real ledger is wired by DEV-427's owner; until handoff the default port fails closed.

export type UsageCapability = "ai_edit";

export interface UsageReserveInput {
  operationId: string;
  capability: UsageCapability;
  inputHash: string;
  estimatedUnits: number;
  source: Record<string, unknown>;
}

export interface UsageReleaseInput {
  operationId: string;
  capability: UsageCapability;
  inputHash: string;
}

export interface UsageFinalizeInput {
  operationId: string;
  capability: UsageCapability;
  inputHash: string;
  committedUnits: number;
  stableRecipeId: string;
  payloadHash: string;
}

export interface UsagePort {
  reserve(input: UsageReserveInput): Promise<void>;
  release(input: UsageReleaseInput): Promise<void>;
  finalize(input: UsageFinalizeInput): Promise<void>;
}

export class UsageUnavailableError extends Error {
  constructor(message = "The commercial usage ledger is not wired yet.") {
    super(message);
    this.name = "UsageUnavailableError";
  }
}

/**
 * Fail-closed placeholder until DEV-427 hands off the real reservation ledger.
 * The handler maps this to a 503 so a missing ledger can never fake a settle.
 */
export function createUnavailableUsagePort(): UsagePort {
  const unavailable = (): Promise<never> =>
    Promise.reject(new UsageUnavailableError());
  return {
    reserve: unavailable,
    release: unavailable,
    finalize: unavailable,
  };
}
