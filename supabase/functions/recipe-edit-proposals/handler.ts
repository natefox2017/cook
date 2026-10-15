// Developer: gengyun
// Purpose: Map verified owner requests to bounded AI recipe edit proposal RPCs without provider
// dispatch by default. Generation and usage settlement are injected ports.

import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";
import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";
import {
  type EditChange,
  type EditIntent,
  isEditIntent,
  validEditChanges,
} from "./editSchema.ts";
import type { EditProposalResult, EditRecipeSnapshot } from "./provider.ts";
import type { UsagePort } from "./usagePort.ts";

type Row = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
const MAX_BODY_BYTES = 1048576;
const MAX_INGREDIENTS = 200;
const MAX_STEPS = 200;
const NAME_AMOUNT_MAX = 240;
const INSTRUCTION_MAX = 8000;
const REVISION_MAX = 64;
const SUPPLEMENT_MAX = 500;

const statuses: Record<string, number> = {
  INVALID_INPUT: 400,
  UNAUTHORIZED: 401,
  NOT_FOUND: 404,
  IDEMPOTENCY_CONFLICT: 409,
  STALE_REVISION: 409,
  ALREADY_REJECTED: 409,
  NEEDS_MANUAL_EDIT: 422,
  EDIT_DISABLED: 503,
  PROVIDER_UNAVAILABLE: 503,
  USAGE_UNAVAILABLE: 503,
  INTERNAL_ERROR: 500,
};

class Failure extends Error {
  constructor(
    public readonly code: string,
    message = code,
  ) {
    super(message);
    this.name = "Failure";
  }
}

export { Failure };

function object(value: unknown): value is Row {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireThat(condition: unknown, code: string): asserts condition {
  if (!condition) throw new Failure(code);
}

function uuid(value: unknown, code = "INVALID_INPUT"): string {
  requireThat(typeof value === "string" && UUID.test(value), code);
  return value;
}

function hash(value: unknown, code = "INVALID_INPUT"): string {
  requireThat(typeof value === "string" && HASH.test(value), code);
  return value;
}

function boundedText(
  value: unknown,
  maximum: number,
  code = "INVALID_INPUT",
): string {
  requireThat(
    typeof value === "string" && value.trim().length > 0 &&
      value.length <= maximum && !/[\u0000-\u001f\u007f]/.test(value),
    code,
  );
  return value;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...publicCorsHeaders, "Content-Type": "application/json" },
  });
}

/** Bounded streaming request read: enforces the cap even for chunked/dishonest bodies. */
async function readJSONBody(request: Request, maxBytes: number): Promise<Row> {
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new Failure("INVALID_INPUT");
  }
  if (!request.body) throw new Failure("INVALID_INPUT");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new Failure("INVALID_INPUT");
      }
      chunks.push(next.value);
    }
    const buffer = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) {
      buffer.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const decoded = new TextDecoder("utf-8", { fatal: true }).decode(buffer);
    const parsed: unknown = JSON.parse(decoded);
    requireThat(object(parsed), "INVALID_INPUT");
    return parsed;
  } catch (error) {
    if (error instanceof Failure) throw error;
    throw new Failure("INVALID_INPUT");
  } finally {
    reader.releaseLock();
  }
}

export interface ProposalBackend {
  createProposal(input: CreateProposalInput): Promise<CreateProposalResult>;
  getProposal(ownerId: string, id: string): Promise<ProposalRow | null>;
  getProposalByOperation(
    ownerId: string,
    operationId: string,
  ): Promise<ProposalRow | null>;
  approveProposal(input: ApproveProposalInput): Promise<ApproveProposalResult>;
}

export interface ProposalRow {
  id: string;
  owner_id: string;
  operation_id: string;
  intent: EditIntent;
  recipe_id: string;
  source_revision: string;
  snapshot_hash: string;
  input_hash: string;
  status: "generated" | "approved" | "rejected";
  changes: EditChange[];
  reasons: string[];
  warnings: string[];
  needs_manual_edit: boolean;
  payload_hash: string | null;
  approved_payload: EditChange[] | null;
  created_at: string;
  updated_at: string;
}

export interface CreateProposalInput {
  ownerId: string;
  operationId: string;
  intent: EditIntent;
  recipeId: string;
  sourceRevision: string;
  snapshotHash: string;
  inputHash: string;
  changes: EditChange[];
  reasons: string[];
  warnings: string[];
  needsManualEdit: boolean;
}

export interface CreateProposalResult {
  outcome: "created" | "replay";
  proposal: ProposalRow;
}

export interface ApproveProposalInput {
  ownerId: string;
  proposalId: string;
  changes: EditChange[];
  expectedSnapshotHash: string;
  payloadHash: string;
}

export interface ApproveProposalResult {
  outcome: "approved" | "replay";
  proposal: ProposalRow;
}

export interface EditProviderPort {
  generate(input: {
    intent: EditIntent;
    recipe: EditRecipeSnapshot;
    supplement: string | null;
    signal: AbortSignal;
  }): Promise<EditProposalResult>;
}

export interface Dependencies {
  enabled: boolean;
  authenticate(request: Request): Promise<{ id: string }>;
  backend: ProposalBackend;
  provider: EditProviderPort;
  usage: UsagePort;
  providerTimeoutMs?: number;
}

interface ParsedCreateBody {
  operationId: string;
  intent: EditIntent;
  recipe: EditRecipeSnapshot & { snapshotHash: string; sourceRevision: string };
  supplement: string | null;
}

function parseCreateBody(body: Row): ParsedCreateBody {
  const operationId = uuid(body.operation_id);
  requireThat(isEditIntent(body.intent), "INVALID_INPUT");
  const intent = body.intent as EditIntent;
  requireThat(object(body.recipe), "INVALID_INPUT");
  const recipe = body.recipe;
  const id = uuid(recipe.id);
  const sourceRevision = boundedText(recipe.updated_at, REVISION_MAX);
  const snapshotHash = hash(recipe.snapshot_hash);
  requireThat(Array.isArray(recipe.ingredients), "INVALID_INPUT");
  requireThat(Array.isArray(recipe.steps), "INVALID_INPUT");
  requireThat(recipe.ingredients.length <= MAX_INGREDIENTS, "INVALID_INPUT");
  requireThat(recipe.steps.length <= MAX_STEPS, "INVALID_INPUT");
  const ingredients = recipe.ingredients.map((value: unknown) => {
    requireThat(object(value), "INVALID_INPUT");
    return {
      id: uuid(value.id),
      name: boundedText(value.name, NAME_AMOUNT_MAX),
      amount: boundedText(value.amount, NAME_AMOUNT_MAX),
    };
  });
  const steps = recipe.steps.map((value: unknown) => {
    requireThat(object(value), "INVALID_INPUT");
    return {
      id: uuid(value.id),
      instruction: boundedText(value.instruction, INSTRUCTION_MAX),
    };
  });
  let supplement: string | null = null;
  if (body.supplement !== undefined && body.supplement !== null) {
    supplement = boundedText(body.supplement, SUPPLEMENT_MAX);
  }
  return {
    operationId,
    intent,
    recipe: {
      id,
      sourceRevision,
      snapshotHash,
      ingredients,
      steps,
    },
    supplement,
  };
}

async function computeInputHash(
  intent: EditIntent,
  recipeId: string,
  snapshotHash: string,
  sourceRevision: string,
): Promise<string> {
  return canonicalHash({
    capability: "ai_edit",
    source: {
      recipe_id: recipeId,
      snapshot_hash: snapshotHash,
      source_revision: sourceRevision,
      intent,
    },
  });
}

function wireProposal(row: ProposalRow): Row {
  return {
    proposal_id: row.id,
    status: row.status,
    generated: true,
    intent: row.intent,
    source: {
      recipe_id: row.recipe_id,
      source_revision: row.source_revision,
      snapshot_hash: row.snapshot_hash,
    },
    changes: row.changes,
    reasons: row.reasons,
    warnings: row.warnings,
    input_hash: row.input_hash,
    needs_manual_edit: row.needs_manual_edit,
  };
}

function parseApproveBody(
  body: Row,
): { changes: EditChange[]; expectedSnapshotHash: string } {
  requireThat(Array.isArray(body.changes), "INVALID_INPUT");
  requireThat(validEditChanges(body.changes), "INVALID_INPUT");
  return {
    changes: body.changes as EditChange[],
    expectedSnapshotHash: hash(body.expected_snapshot_hash),
  };
}

export async function handleRequest(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  const cors = handleCors(request);
  if (cors) return cors;
  const url = new URL(request.url);
  const path = url.pathname;
  try {
    const method = request.method;
    const prefix = "/recipe-edit-proposals";
    if (path === prefix && method === "POST") {
      return await createProposal(request, deps);
    }
    const getMatch = path.match(new RegExp(`^${prefix}/([0-9a-f-]{36})$`));
    if (getMatch && method === "GET") {
      return await getProposal(getMatch[1], request, deps);
    }
    const approveMatch = path.match(
      new RegExp(`^${prefix}/([0-9a-f-]{36})/approve$`),
    );
    if (approveMatch && method === "POST") {
      return await approveProposal(approveMatch[1], request, deps);
    }
    return json({ error: { code: "NOT_FOUND", message: "Not found" } }, 404);
  } catch (error) {
    if (error instanceof Failure) {
      return json(
        { error: { code: error.code, message: error.message, details: null } },
        statuses[error.code] ?? 400,
      );
    }
    console.error("unhandled_error");
    return json(
      {
        error: {
          code: "INTERNAL_ERROR",
          message: "An unexpected error occurred",
          details: null,
        },
      },
      500,
    );
  }
}

async function createProposal(
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  requireThat(deps.enabled, "EDIT_DISABLED");
  const owner = await deps.authenticate(request);
  const body = parseCreateBody(await readJSONBody(request, MAX_BODY_BYTES));
  const inputHash = await computeInputHash(
    body.intent,
    body.recipe.id,
    body.recipe.snapshotHash,
    body.recipe.sourceRevision,
  );
  // Idempotent replay short-circuits before any reserve/generation so retries stay cheap.
  const existing = await deps.backend.getProposalByOperation(
    owner.id,
    body.operationId,
  );
  if (existing) {
    if (existing.input_hash !== inputHash) {
      throw new Failure("IDEMPOTENCY_CONFLICT");
    }
    return json(wireProposal(existing), 200);
  }
  const source = {
    recipe_id: body.recipe.id,
    snapshot_hash: body.recipe.snapshotHash,
    source_revision: body.recipe.sourceRevision,
    intent: body.intent,
  };
  try {
    const reserveStatus = await deps.usage.reserve({
      ownerId: owner.id,
      operationId: body.operationId,
      capability: "ai_edit",
      inputHash,
      estimatedUnits: 1,
      source,
    });
    if (reserveStatus === "replay") {
      // A prior attempt fenced this operation but never persisted a proposal; do not re-dispatch.
      throw new Failure("USAGE_UNAVAILABLE");
    }
    await deps.usage.markDispatched({
      ownerId: owner.id,
      operationId: body.operationId,
      capability: "ai_edit",
      inputHash,
    });
  } catch (error) {
    if (error instanceof Failure) throw error;
    console.error("usage_reserve_failed");
    throw new Failure("USAGE_UNAVAILABLE");
  }
  const signal = AbortSignal.timeout(deps.providerTimeoutMs ?? 30000);
  let generated: EditProposalResult;
  try {
    generated = await deps.provider.generate({
      intent: body.intent,
      recipe: {
        id: body.recipe.id,
        ingredients: body.recipe.ingredients,
        steps: body.recipe.steps,
      },
      supplement: body.supplement,
      signal,
    });
  } catch (error) {
    // Timeout/security rejection preserves the original recipe and releases the reservation.
    await deps.usage.release({
      ownerId: owner.id,
      operationId: body.operationId,
      capability: "ai_edit",
      inputHash,
    }).catch(() => {});
    throw new Failure("PROVIDER_UNAVAILABLE");
  }
  let result: CreateProposalResult;
  try {
    result = await deps.backend.createProposal({
      ownerId: owner.id,
      operationId: body.operationId,
      intent: body.intent,
      recipeId: body.recipe.id,
      sourceRevision: body.recipe.sourceRevision,
      snapshotHash: body.recipe.snapshotHash,
      inputHash,
      changes: generated.changes,
      reasons: generated.reasons,
      warnings: generated.warnings,
      needsManualEdit: generated.needsManualEdit,
    });
  } catch (error) {
    // The proposal was not persisted (stale/conflict); release the uncommitted reservation.
    await deps.usage.release({
      ownerId: owner.id,
      operationId: body.operationId,
      capability: "ai_edit",
      inputHash,
    }).catch(() => {});
    throw error;
  }
  if (result.outcome === "replay") {
    return json(wireProposal(result.proposal), 200);
  }
  // Known persisted generated result: switch the ledger hold to the 24h generated window.
  await deps.usage.markGenerated({
    ownerId: owner.id,
    operationId: body.operationId,
    capability: "ai_edit",
    inputHash,
  }).catch(() => {});
  return json(wireProposal(result.proposal), 201);
}

async function getProposal(
  id: string,
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  requireThat(deps.enabled, "EDIT_DISABLED");
  const owner = await deps.authenticate(request);
  // Ownership is enforced by the backend read (owner-scoped query); a cross-owner read yields null.
  const row = await deps.backend.getProposal(owner.id, id);
  if (!row) {
    return json({ error: { code: "NOT_FOUND", message: "Not found" } }, 404);
  }
  return json(wireProposal(row), 200);
}

async function approveProposal(
  id: string,
  request: Request,
  deps: Dependencies,
): Promise<Response> {
  requireThat(deps.enabled, "EDIT_DISABLED");
  const owner = await deps.authenticate(request);
  const body = parseApproveBody(await readJSONBody(request, MAX_BODY_BYTES));
  const payloadHash = await canonicalHash({ changes: body.changes });
  const result = await deps.backend.approveProposal({
    ownerId: owner.id,
    proposalId: id,
    changes: body.changes,
    expectedSnapshotHash: body.expectedSnapshotHash,
    payloadHash,
  });
  if (result.outcome === "approved" || result.outcome === "replay") {
    try {
      await deps.usage.finalize({
        ownerId: owner.id,
        operationId: result.proposal.operation_id,
        capability: "ai_edit",
        inputHash: result.proposal.input_hash,
        source: {
          recipe_id: result.proposal.recipe_id,
          snapshot_hash: result.proposal.snapshot_hash,
          source_revision: result.proposal.source_revision,
          intent: result.proposal.intent,
        },
        payloadHash: result.proposal.payload_hash ?? payloadHash,
        payload: { changes: body.changes },
      });
    } catch (error) {
      console.error("usage_finalize_failed");
      throw new Failure("USAGE_UNAVAILABLE");
    }
  }
  return json({
    proposal_id: result.proposal.id,
    status: result.proposal.status,
    operation_id: result.proposal.operation_id,
    recipe_id: result.proposal.recipe_id,
    payload_hash: result.proposal.payload_hash,
  }, 200);
}
