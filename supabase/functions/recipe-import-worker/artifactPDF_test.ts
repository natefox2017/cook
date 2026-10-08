// Developer: gengyun
// Purpose: Confirms selectable PDF text extraction and source-linked page evidence.

import {
  PDFArtifactError,
  extractSelectablePDFArtifact,
  parseSelectablePDFPages,
} from "./artifactPDF.ts";

const ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ARTIFACT = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function expect(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}

Deno.test("page-aware evidence preserves raw quantity and uses the original artifact", () => {
  const result = parseSelectablePDFPages({
    recipeID: ID,
    artifactID: ARTIFACT,
    pages: [
      { pageNumber: 1, text: "Tomato soup\nIngredients\n- Salt to taste" },
      { pageNumber: 2, text: "Steps\n1. Simmer gently" },
    ],
    platformHint: "files",
    originalSourceURL: null,
  });
  expect(result.status === "ready", "Complete selected text should be ready");
  expect(result.source.input_type === "file", "PDF converted to text source");
  expect(result.source.source_artifact_id === ARTIFACT, "Original PDF ID lost");
  expect(result.fields["ingredients[0].amount"].normalized_value === null, "Guessed a quantity");
  expect(result.fields["ingredients[0].raw_text"].raw_value === "- Salt to taste", "Changed amount");
  const stepID = result.fields["steps[0].instruction"].evidence_ids[0];
  expect(result.evidence.some((e) =>
    e.id === stepID && String(e.excerpt).startsWith("Page 2:") &&
    e.source_artifact_id === ARTIFACT
  ), "Step not linked to original PDF page");
});

Deno.test("scanned PDF/no text is reviewable and never called a full recipe", () => {
  let noText = false;
  try {
    parseSelectablePDFPages({
      recipeID: ID, artifactID: ARTIFACT,
      pages: [{ pageNumber: 1, text: "    " }],
      platformHint: null, originalSourceURL: null,
    });
  } catch (error) {
    noText = error instanceof PDFArtifactError &&
      error.code === "PDF_NO_SELECTABLE_TEXT";
  }
  expect(noText, "Scanned page fabricated recipe text");
});

Deno.test("malformed or oversized source is rejected before PDF.js parsing", async () => {
  let invalid = false;
  try {
    await extractSelectablePDFArtifact({
      recipeID: ID, artifactID: ARTIFACT,
      bytes: new Uint8Array([1, 2, 3]),
      expectedBytes: 3, platformHint: null, originalSourceURL: null,
    });
  } catch (error) {
    invalid = error instanceof PDFArtifactError &&
      error.code === "PDF_INVALID_SOURCE";
  }
  expect(invalid, "Non-PDF bytes were parsed");
});

Deno.test("duplicated and out-of-range page numbers are rejected", () => {
  for (const pages of [
    [{ pageNumber: 1, text: "abc" }, { pageNumber: 1, text: "def" }],
    [{ pageNumber: 21, text: "abc" }],
  ]) {
    let invalid = false;
    try {
      parseSelectablePDFPages({
        recipeID: ID, artifactID: ARTIFACT, pages,
        platformHint: null, originalSourceURL: null,
      });
    } catch (error) {
      invalid = error instanceof PDFArtifactError;
    }
    expect(invalid, "Unbounded PDF pages accepted");
  }
});
