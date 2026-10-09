// Developer: gengyun
// Purpose: Covers private text source verification, extraction and safe fallback.

import {
  ArtifactTextError,
  decodePlainTextArtifact,
  isOwnerScopedAvailableArtifact,
  parsePlainTextArtifact,
  type PrivateArtifactRow,
} from "./artifactText.ts";

const ownerID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const artifactID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const jobID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

function expect(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

const artifact: PrivateArtifactRow = {
  id: artifactID,
  owner_id: ownerID,
  input_type: "file",
  storage_bucket: "recipe-import-artifacts",
  storage_path: `${ownerID}/${artifactID}`,
  mime_type: "text/plain",
  size_bytes: 128,
  state: "available",
  expires_at: "2099-12-31T00:00:00Z",
};

Deno.test("private file path, UUID, owner and expiry must all match", () => {
  const requested = { ownerID, artifactID, inputType: "file" as const };
  expect(isOwnerScopedAvailableArtifact(artifact, requested), "Valid owner row rejected");
  expect(
    !isOwnerScopedAvailableArtifact(artifact, { ...requested, ownerID: crypto.randomUUID() }),
    "Other owner was able to read artifact",
  );
  expect(
    !isOwnerScopedAvailableArtifact(artifact, { ...requested, artifactID: crypto.randomUUID() }),
    "Wrong artifact UUID accepted",
  );
  expect(
    !isOwnerScopedAvailableArtifact({ ...artifact, storage_path: "other/path" }, requested),
    "Cross-owner Storage path accepted",
  );
  expect(
    !isOwnerScopedAvailableArtifact({ ...artifact, state: "expired" }, requested),
    "Deleted attachment was accepted",
  );
  expect(
    !isOwnerScopedAvailableArtifact({ ...artifact, expires_at: "2026-01-01" }, requested),
    "Expired attachment accepted",
  );
  expect(
    !isOwnerScopedAvailableArtifact({ ...artifact, size_bytes: 11 * 1024 * 1024 }, requested),
    "Oversized attachment accepted",
  );
});

Deno.test("text/plain artifact produces traceable recipe fields", async () => {
  const raw = "Tomato salad\r\nIngredients\r\n- Salt to taste\r\n- About 2 tomatoes\r\nSteps\r\n1. Mix until combined";
  const bytes = new TextEncoder().encode(raw);
  const text = await decodePlainTextArtifact(new Blob([bytes]), bytes.length);
  const result = parsePlainTextArtifact({
    id: jobID,
    text,
    artifactID,
    platformHint: "files",
  });
  expect(result.recipe_id === jobID && result.status === "ready", "Ready text misparsed");
  expect(result.source.input_type === "file", "File source became bare text");
  expect(result.source.source_artifact_id === artifactID, "Source artifact ID lost");
  expect(result.fields["ingredients[0].raw_text"].raw_value === "- Salt to taste", "Invented quantity");
  expect(result.fields["ingredients[0].amount"].normalized_value === null, "Guessed amount");
  expect(result.fields["steps[0].instruction"].raw_value === "Mix until combined", "Step changed");
  expect(
    result.evidence.some((ev) =>
      ev.source_artifact_id === artifactID &&
      result.fields["ingredients[0].amount"].evidence_ids.includes(String(ev.id))
    ),
    "Field evidence does not point to the private source",
  );
  const repeated = parsePlainTextArtifact({
    id: jobID,
    text,
    artifactID,
    platformHint: "files",
  });
  expect(repeated.recipe_id === result.recipe_id, "Retry generated new recipe ID");
});

Deno.test("unstructured text remains needs_review without invented steps", () => {
  const result = parsePlainTextArtifact({
    id: jobID,
    text: "Just a cooking photograph caption.",
    artifactID,
    platformHint: null,
  });
  expect(result.status === "needs_review", "Unstructured text must require review");
  expect(result.review_fields.includes("steps"), "Missing steps not flagged");
  expect(result.fields["steps[0].instruction"] === undefined, "Invented steps");
  expect(result.evidence[0].source_artifact_id === artifactID, "Lost original source");
});

Deno.test("malformed, truncated, empty and oversized text never become evidence", async () => {
  const bad = [
    { blob: new Blob([new Uint8Array([0xff])]), bytes: 1 },
    { blob: new Blob(["\0bad"]), bytes: 4 },
    { blob: new Blob(["   "]), bytes: 3 },
    { blob: new Blob(["abc"]), bytes: 4 },
    { blob: new Blob(["a".repeat(100_001)]), bytes: 100_001 },
  ];
  for (const { blob, bytes } of bad) {
    let failed = false;
    try {
      await decodePlainTextArtifact(blob, bytes);
    } catch (error) {
      failed = error instanceof ArtifactTextError;
    }
    expect(failed, "Invalid attachment was treated as readable text");
  }
});
