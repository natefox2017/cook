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


function syntheticTextPDF(includeText = true): Uint8Array {
  // A valid single-page PDF 1.4 built with byte-accurate xref offsets.
  // Keeps regression fixtures self-contained without binary test artifacts.
  const encoder = new TextEncoder();
  const stream = includeText ? [
    "BT",
    "/F1 12 Tf",
    "50 760 Td",
    "(Tomato soup) Tj",
    "0 -20 Td",
    "(Ingredients) Tj",
    "0 -20 Td",
    "(- Salt to taste) Tj",
    "0 -20 Td",
    "(Steps) Tj",
    "0 -20 Td",
    "(1. Simmer gently) Tj",
    "ET",
  ].join("\n") : "";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${encoder.encode(stream).length} >>\nstream\n${stream}\nendstream`,
  ];
  let content = "%PDF-1.4\n";
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(encoder.encode(content).length);
    content += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xref = encoder.encode(content).length;
  content += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) {
    content += `${String(offset).padStart(10, "0")} 00000 n \n`;
  }
  content += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return encoder.encode(content);
}

Deno.test("bundled serverless PDF.js reads a real selectable-text fixture", async () => {
  const bytes = syntheticTextPDF();
  const result = await extractSelectablePDFArtifact({
    recipeID: ID,
    artifactID: ARTIFACT,
    bytes,
    expectedBytes: bytes.length,
    platformHint: null,
    originalSourceURL: null,
  });
  expect(result.status === "ready", "Complete PDF did not produce a ready recipe");
  expect(result.fields["ingredients[0].amount"].normalized_value === null, "PDF invented a quantity");
  expect(result.recipe_id === ID, "Unstable recipe identifier");
  expect(result.source.source_artifact_id === ARTIFACT, "Private document lost");
  expect(result.evidence.some((item) =>
    String(item.excerpt).includes("Tomato soup")
  ), "Selectable PDF text was not extracted");
});

Deno.test("real PDF without a text layer requests OCR or review without fabricating text", async () => {
  const bytes = syntheticTextPDF(false);
  let noText = false;
  try {
    await extractSelectablePDFArtifact({
      recipeID: ID,
      artifactID: ARTIFACT,
      bytes,
      expectedBytes: bytes.length,
      platformHint: null,
      originalSourceURL: null,
    });
  } catch (error) {
    noText = error instanceof PDFArtifactError &&
      error.code === "PDF_NO_SELECTABLE_TEXT";
  }
  expect(noText, "Blank PDF fabricated selectable text or hid the OCR fallback signal");
});

Deno.test("sequential real PDF parses preserve stable identity and source", async () => {
  for (let count = 0; count < 10; count++) {
    const bytes = syntheticTextPDF();
    const result = await extractSelectablePDFArtifact({
      recipeID: ID,
      artifactID: ARTIFACT,
      bytes,
      expectedBytes: bytes.length,
      platformHint: "files",
      originalSourceURL: "https://example.com/recipe",
    });
    expect(result.status === "ready", "Repeated parsing lost complete recipe fields");
    expect(result.source.original_url === "https://example.com/recipe", "Source URL lost");
    expect(result.source.source_artifact_id === ARTIFACT, "Artifact identity lost");
  }
});
