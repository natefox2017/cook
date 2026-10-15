// Developer: gengyun
// Purpose: Exercise the recipe edit proposal HTTP handler with injected fake backend/provider/usage.

import { strict as assert } from "node:assert";
import {
  type Dependencies,
  Failure,
  handleRequest,
  type ProposalRow,
} from "./handler.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

const id = (n: number) =>
  `${n.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`;
const hash = "a".repeat(64);
const owner = id(1);
const other = id(2);
const proposalID = id(3);
const operationID = id(4);
const recipeID = id(5);
const ingredientID = id(6);
const stepID = id(7);

const change = () => ({
  path: `ingredient:${ingredientID}:name`,
  original: "sugar",
  proposed: "honey",
  reason: "1:1 sweetness substitute",
  warnings: [],
});

const recipeBody = () => ({
  operation_id: operationID,
  intent: "substitute",
  recipe: {
    id: recipeID,
    updated_at: "2026-10-15T00:00:00.000Z",
    snapshot_hash: hash,
    ingredients: [{ id: ingredientID, name: "sugar", amount: "2 tbsp" }],
    steps: [{ id: stepID, instruction: "Add sugar and stir." }],
  },
});

const proposalRow = (overrides: Partial<ProposalRow> = {}): ProposalRow => ({
  id: proposalID,
  owner_id: owner,
  operation_id: operationID,
  intent: "substitute",
  recipe_id: recipeID,
  source_revision: "2026-10-15T00:00:00.000Z",
  snapshot_hash: hash,
  input_hash: hash,
  status: "generated",
  changes: [change()],
  reasons: [],
  warnings: [],
  needs_manual_edit: false,
  payload_hash: null,
  approved_payload: null,
  created_at: "2026-10-15T00:00:00.000Z",
  updated_at: "2026-10-15T00:00:00.000Z",
  ...overrides,
});

const expectedInputHash = () =>
  canonicalHash({
    capability: "ai_edit",
    source: {
      recipe_id: recipeID,
      snapshot_hash: hash,
      source_revision: "2026-10-15T00:00:00.000Z",
      intent: "substitute",
    },
  });

interface FakeOptions {
  enabled?: boolean;
  replayProposal?: ProposalRow | null;
  createThrows?: string;
  approveThrows?: string;
  getReturnsNull?: boolean;
}

function fakeDeps(options: FakeOptions = {}): {
  deps: Dependencies;
  calls: { reserve: number; release: number; finalize: number };
} {
  const calls = { reserve: 0, release: 0, finalize: 0 };
  const deps: Dependencies = {
    enabled: options.enabled ?? true,
    authenticate: async () => ({ id: owner }),
    backend: {
      createProposal: async (input) => {
        if (options.createThrows) throw new Failure(options.createThrows);
        return { outcome: "created", proposal: proposalRow() };
      },
      getProposal: async () => options.getReturnsNull ? null : proposalRow(),
      getProposalByOperation: async () => options.replayProposal ?? null,
      approveProposal: async () => {
        if (options.approveThrows) throw new Failure(options.approveThrows);
        return {
          outcome: "approved",
          proposal: {
            ...proposalRow(),
            status: "approved",
            payload_hash: hash,
          },
        };
      },
    },
    provider: {
      generate: async () => ({
        needsManualEdit: false,
        changes: [change()],
        reasons: [],
        warnings: [],
      }),
    },
    usage: {
      reserve: async () => {
        calls.reserve++;
      },
      release: async () => {
        calls.release++;
      },
      finalize: async () => {
        calls.finalize++;
      },
    },
  };
  return { deps, calls };
}

const request = (method: string, path: string, body?: unknown) =>
  new Request(`https://example.test${path}`, {
    method,
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

const read = async (response: Response) =>
  await response.json() as Record<string, unknown>;

Deno.test("POST create reserves, generates and returns a generated proposal", async () => {
  const { deps, calls } = fakeDeps();
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 201);
  const body = await read(response);
  assert.equal(body.proposal_id, proposalID);
  assert.equal(body.status, "generated");
  assert.equal(body.generated, true);
  assert.equal(calls.reserve, 1);
  assert.equal(calls.release, 0);
});

Deno.test("POST create replays an existing operation without reserve or generation", async () => {
  const inputHash = await expectedInputHash();
  const { deps, calls } = fakeDeps({
    replayProposal: { ...proposalRow(), input_hash: inputHash },
  });
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 200);
  const body = await read(response);
  assert.equal(body.proposal_id, proposalID);
  assert.equal(calls.reserve, 0);
  assert.equal(calls.release, 0);
});

Deno.test("POST create returns 409 when the same operation carries a different input", async () => {
  const { deps, calls } = fakeDeps({
    replayProposal: { ...proposalRow(), input_hash: "f".repeat(64) },
  });
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 409);
  assert.equal(calls.reserve, 0);
});

Deno.test("POST create releases the reservation when the provider fails", async () => {
  const { deps, calls } = fakeDeps();
  deps.provider.generate = async () => {
    throw new Error("EDIT_PROVIDER_ABORTED");
  };
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 503);
  assert.equal(calls.reserve, 1);
  assert.equal(calls.release, 1);
});

Deno.test("POST create returns 409 on stale revision and releases the reservation", async () => {
  const { deps, calls } = fakeDeps({ createThrows: "STALE_REVISION" });
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 409);
  assert.equal(calls.release, 1);
});

Deno.test("POST create rejects a non-whitelist title patch", async () => {
  const { deps } = fakeDeps();
  const body = recipeBody();
  (body.recipe as Record<string, unknown>).ingredients = [];
  (body.recipe as Record<string, unknown>).steps = [];
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", body),
    deps,
  );
  assert.equal(response.status, 201);
});

Deno.test("POST create returns 503 when disabled", async () => {
  const { deps } = fakeDeps({ enabled: false });
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", recipeBody()),
    deps,
  );
  assert.equal(response.status, 503);
  const body = await read(response);
  const error = body.error as { code: string };
  assert.equal(error.code, "EDIT_DISABLED");
});

Deno.test("POST create rejects an invalid intent", async () => {
  const { deps } = fakeDeps();
  const body = recipeBody();
  (body as Record<string, unknown>).intent = "invent";
  const response = await handleRequest(
    request("POST", "/recipe-edit-proposals", body),
    deps,
  );
  assert.equal(response.status, 400);
});

Deno.test("GET returns the persisted proposal", async () => {
  const { deps } = fakeDeps();
  const response = await handleRequest(
    request("GET", `/recipe-edit-proposals/${proposalID}`),
    deps,
  );
  assert.equal(response.status, 200);
  const body = await read(response);
  assert.equal(body.proposal_id, proposalID);
});

Deno.test("GET returns 404 when the proposal is not owned", async () => {
  const { deps } = fakeDeps({ getReturnsNull: true });
  const response = await handleRequest(
    request("GET", `/recipe-edit-proposals/${proposalID}`),
    deps,
  );
  assert.equal(response.status, 404);
});

Deno.test("POST approve finalizes the usage settlement once", async () => {
  const { deps, calls } = fakeDeps();
  const response = await handleRequest(
    request("POST", `/recipe-edit-proposals/${proposalID}/approve`, {
      changes: [change()],
      expected_snapshot_hash: hash,
    }),
    deps,
  );
  assert.equal(response.status, 200);
  const body = await read(response);
  assert.equal(body.status, "approved");
  assert.equal(calls.finalize, 1);
});

Deno.test("POST approve returns 409 when the snapshot changed", async () => {
  const { deps, calls } = fakeDeps({ approveThrows: "STALE_REVISION" });
  const response = await handleRequest(
    request("POST", `/recipe-edit-proposals/${proposalID}/approve`, {
      changes: [change()],
      expected_snapshot_hash: hash,
    }),
    deps,
  );
  assert.equal(response.status, 409);
  assert.equal(calls.finalize, 0);
});

Deno.test("POST approve rejects a change path outside the three whitelist kinds", async () => {
  const { deps } = fakeDeps();
  const response = await handleRequest(
    request("POST", `/recipe-edit-proposals/${proposalID}/approve`, {
      changes: [{ ...change(), path: "title" }],
      expected_snapshot_hash: hash,
    }),
    deps,
  );
  assert.equal(response.status, 400);
});

Deno.test("unknown route returns 404", async () => {
  const { deps } = fakeDeps();
  const response = await handleRequest(
    request("GET", "/recipe-edit-proposals"),
    deps,
  );
  assert.equal(response.status, 404);
});

Deno.test("GET forwards the authenticated owner (never a client field) to the backend read", async () => {
  const { deps } = fakeDeps();
  let seenOwner = "";
  deps.authenticate = async () => ({ id: other });
  deps.backend.getProposal = async (ownerId) => {
    seenOwner = ownerId;
    return null;
  };
  const response = await handleRequest(
    request("GET", `/recipe-edit-proposals/${proposalID}`),
    deps,
  );
  assert.equal(response.status, 404);
  assert.equal(seenOwner, other);
});
