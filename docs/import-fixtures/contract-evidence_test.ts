// Purpose: Regress evidence links and review semantics in the frozen import contract fixture.

type Evidence = {
  id: string;
  origin: string;
  excerpt?: string | null;
  source_type: string;
};

type RecipeField = {
  confidence?: number | null;
  evidence_ids: string[];
  normalized_value?: unknown;
  origin: string;
  raw_value: string | null;
  user_confirmed: boolean;
};

Deno.test("completed import preserves original source, linked evidence, review gaps and user edit", () => {
  const fixtures = JSON.parse(
    Deno.readTextFileSync(new URL("./contract-examples.json", import.meta.url)),
  ) as { cases: Array<Record<string, unknown>> };
  const fixture = fixtures.cases.find(
    (candidate) =>
      candidate.name ===
        "completed result keeps source, evidence, review gaps and user edit distinct",
  );
  if (!fixture) throw new Error("Evidence regression fixture is missing");

  const submittedInput = fixture.submitted_input as {
    input_type: string;
    url: string;
  };
  const response = fixture.data as {
    result: {
      fields: Record<string, RecipeField>;
      review_fields: string[];
      source: { original_url: string; canonical_url: string };
      evidence: Evidence[];
    };
  };
  const result = response.result;
  const evidenceById = new Map(result.evidence.map((item) => [item.id, item]));

  if (evidenceById.size !== result.evidence.length) {
    throw new Error("Evidence IDs must be unique within one recipe result");
  }
  if (
    submittedInput.input_type !== "url" ||
    result.source.original_url !== submittedInput.url ||
    result.source.canonical_url === submittedInput.url
  ) {
    throw new Error(
      "Raw submitted URL and resolved canonical URL must stay distinct",
    );
  }

  for (const [path, field] of Object.entries(result.fields)) {
    for (const evidenceId of field.evidence_ids) {
      if (!evidenceById.has(evidenceId)) {
        throw new Error(`${path} refers to missing evidence ${evidenceId}`);
      }
    }
  }

  const amount = result.fields["ingredients[0].amount"];
  const amountEvidence = evidenceById.get(amount.evidence_ids[0]);
  if (
    amount.raw_value !== "盐适量" || amount.normalized_value !== null ||
    amount.confidence !== 0.42 ||
    amountEvidence?.excerpt !== amount.raw_value ||
    !result.review_fields.includes("ingredients[0].amount")
  ) {
    throw new Error(
      "Vague, low-confidence amount must remain raw and reviewable",
    );
  }

  const missingStepPath = "steps[1].instruction";
  if (
    Object.hasOwn(result.fields, missingStepPath) ||
    !result.review_fields.includes(missingStepPath)
  ) {
    throw new Error(
      "A missing step must remain absent and appear in review_fields",
    );
  }

  const editedStep = result.fields["steps[0].instruction"];
  const [sourceEvidenceId, userEvidenceId] = editedStep.evidence_ids;
  const sourceEvidence = evidenceById.get(sourceEvidenceId);
  const userEvidence = evidenceById.get(userEvidenceId);
  if (
    editedStep.raw_value !== sourceEvidence?.excerpt ||
    editedStep.normalized_value !== userEvidence?.excerpt ||
    editedStep.origin !== "user" || !editedStep.user_confirmed ||
    userEvidence?.source_type !== "user" || userEvidence.origin !== "user"
  ) {
    throw new Error(
      "User edit must be separately traceable from the extracted source value",
    );
  }
});
