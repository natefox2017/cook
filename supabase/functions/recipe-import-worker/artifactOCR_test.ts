// Developer: gengyun
// Purpose: Verifies bounded OCR provenance and explicit backend-provider opt-in.

import {
  OCRArtifactError,
  parsePrivateOCRArtifact,
  type OCRProvider,
} from "./artifactOCR.ts";
import { configuredOCRProvider } from "./approvedOCRProvider.ts";

const ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ARTIFACT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function expect(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}

function mockProvider(
  pages: Array<{ page_number: number; text: string; confidence: number; pixel_count: number }>,
): OCRProvider {
  return { async recognize(_bytes, controls) {
    expect(controls.maxPages > 0 && controls.maxPixelsPerPage <= 40_000_000, "Unsafe OCR controls");
    return pages;
  } };
}

function input(provider: OCRProvider, overrides: Record<string, unknown> = {}) {
  return {
    recipeID: ID,
    artifactID: ARTIFACT,
    inputType: "image" as const,
    mimeType: "image/png",
    bytes: new Uint8Array([1, 2, 3, 4]),
    platformHint: null,
    originalSourceURL: null,
    provider,
    ...overrides,
  };
}

Deno.test("approved mock OCR preserves original image and page-aware fields", async () => {
  const result = await parsePrivateOCRArtifact(input(mockProvider([{
    page_number: 1,
    text: "Tomato soup\nIngredients\n- Salt to taste\nSteps\n1. Simmer until fragrant",
    confidence: 0.98,
    pixel_count: 1_500_000,
  }])));
  expect(result.status === "ready", "Explicit high-confidence text should be ready");
  expect(result.source.source_artifact_id === ARTIFACT, "Original source lost");
  expect(result.source.input_type === "image", "OCR source became text");
  expect(result.fields["ingredients[0].amount"].normalized_value === null, "Invented exact amount");
  expect(result.fields["ingredients[0].raw_text"].raw_value === "- Salt to taste", "Changed original");
  const evidenceID = result.fields["ingredients[0].raw_text"].evidence_ids[0];
  expect(result.evidence.some((ev) =>
    ev.id === evidenceID && ev.source_type === "ocr" &&
    ev.source_artifact_id === ARTIFACT && String(ev.excerpt).startsWith("Page 1:")
  ), "Missing page evidence");
});

Deno.test("low-confidence scanned PDF retains review and two page references", async () => {
  const result = await parsePrivateOCRArtifact({
    ...input(mockProvider([
      { page_number: 1, text: "Tomato stew\nIngredients\nSalt to taste", confidence: 0.95, pixel_count: 2_000_000 },
      { page_number: 2, text: "Steps\n1. Simmer gently", confidence: 0.6, pixel_count: 2_000_000 },
    ])),
    inputType: "file",
    mimeType: "application/pdf",
  });
  expect(result.status === "needs_review", "Low confidence must need review");
  expect(result.review_fields.includes("ocr_confidence"), "Missing low-confidence flag");
  expect(result.fields["steps[0].instruction"].confidence === 0.6, "Wrong page confidence");
  expect(result.evidence.length === 2, "Lost PDF page attribution");
});

Deno.test("empty, oversized and invalid provider pages never become a ready recipe", async () => {
  const examples = [
    [{ page_number: 1, text: " ", confidence: 0.9, pixel_count: 100 }],
    [{ page_number: 1, text: "Hello", confidence: 1.2, pixel_count: 100 }],
    [{ page_number: 1, text: "Hello", confidence: 0.9, pixel_count: 50_000_000 }],
    [
      { page_number: 1, text: "A", confidence: 0.9, pixel_count: 100 },
      { page_number: 1, text: "B", confidence: 0.9, pixel_count: 100 },
    ],
  ];
  for (const pages of examples) {
    let rejected = false;
    try { await parsePrivateOCRArtifact(input(mockProvider(pages))); }
    catch (error) { rejected = error instanceof OCRArtifactError; }
    expect(rejected, "Invalid OCR output accepted");
  }
});

Deno.test("OCR egress is disabled without explicit approval and exact trusted host", () => {
  const values: Record<string, string> = {
    RECIPE_IMPORT_OCR_PROVIDER_URL: "https://ocr.example.net/recognize",
    RECIPE_IMPORT_OCR_APPROVED_HOST: "ocr.example.net",
    RECIPE_IMPORT_OCR_API_KEY: "test-secret-not-used",
  };
  const env = (name: string) => values[name];
  expect(configuredOCRProvider(env) === null, "OCR enabled without opt-in");
  values.RECIPE_IMPORT_OCR_APPROVED = "true";
  expect(configuredOCRProvider(env) !== null, "Valid explicit approval ignored");
  values.RECIPE_IMPORT_OCR_APPROVED_HOST = "other.example.net";
  expect(configuredOCRProvider(env) === null, "Endpoint escaped host allowlist");
  values.RECIPE_IMPORT_OCR_APPROVED_HOST = "ocr.example.net";
  values.RECIPE_IMPORT_OCR_PROVIDER_URL = "http://ocr.example.net/recognize";
  expect(configuredOCRProvider(env) === null, "Insecure HTTP OCR accepted");
});
