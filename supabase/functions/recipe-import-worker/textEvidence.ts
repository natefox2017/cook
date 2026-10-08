// Developer: gengyun
// Purpose: Extracts only directly evidenced recipe fields from user-provided text.

interface EvidenceField {
  raw_value: string | null;
  normalized_value: string | null;
  evidence_ids: string[];
  confidence: number | null;
  user_confirmed: false;
  origin: "extracted";
  updated_at: string;
}

export function parseLocalText(job: { id: string; source_value: string }): {
  recipe_id: string;
  status: "ready" | "needs_review";
  source: { input_type: "text" };
  fields: Record<string, EvidenceField>;
  evidence: Array<Record<string, unknown>>;
  review_fields: string[];
} {
  // Do not invent ingredients, measurements or cooking durations. Only
  // labelled sections with explicit source lines become recipe fields.
  const lines = job.source_value.split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const evidenceID = crypto.randomUUID();
  const fields: Record<string, EvidenceField> = {};
  const sourceDate = now();
  const evidence = [{
    id: evidenceID,
    source_type: "user",
    origin: "user",
    excerpt: job.source_value.slice(0, 10_000),
    confidence: 1,
    captured_at: sourceDate,
  }];

  const makeField = (raw: string, confidence: number): EvidenceField => ({
    raw_value: raw,
    normalized_value: null,
    evidence_ids: [evidenceID],
    confidence,
    user_confirmed: false,
    origin: "extracted",
    updated_at: sourceDate,
  });

  const ingredientHeading = /^(ingredients?|食材|材料|原料|材料一覧)\s*[:：]?$/i;
  const stepHeading = /^(steps?|instructions?|directions?|method|做法|步骤|步骤说明|作り方|手順)\s*[:：]?$/i;
  let section: "none" | "ingredients" | "steps" = "none";
  let ingredientCount = 0;
  let stepCount = 0;
  let title = "";

  for (const line of lines.slice(0, 350)) {
    if (ingredientHeading.test(line)) {
      section = "ingredients";
      continue;
    }
    if (stepHeading.test(line)) {
      section = "steps";
      continue;
    }

    if (section === "none" && !title && line.length <= 150) {
      title = line;
      continue;
    }

    const raw = line.replace(/^(?:[-*•]\s*|\d+[).、]\s*)/, "");
    if (section === "ingredients" && ingredientCount < 100) {
      // Preserve the entire amount phrase. A low-confidence exact quantity
      // may not be inferred from "to taste", "少许" or "适量".
      fields[`ingredients[${ingredientCount}].raw_text`] =
        makeField(line, 0.95);
      fields[`ingredients[${ingredientCount}].amount`] =
        makeField(line, 0.95);
      ingredientCount++;
    } else if (section === "steps" && stepCount < 80) {
      fields[`steps[${stepCount}].instruction`] =
        makeField(raw, 0.95);
      stepCount++;
    }
  }

  if (title) fields.title = makeField(title, 0.85);
  const review = [
    ...(!title ? ["title"] : []),
    ...(ingredientCount === 0 ? ["ingredients"] : []),
    ...(stepCount === 0 ? ["steps"] : []),
  ];

  return {
    recipe_id: job.id, // A stable result ID across worker retries.
    status: review.length ? "needs_review" : "ready",
    source: { input_type: "text" },
    fields,
    evidence,
    review_fields: review,
  };
}

