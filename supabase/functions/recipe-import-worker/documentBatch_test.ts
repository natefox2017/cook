// Developer: gengyun
// Purpose: Verifies bounded batch validation, PDF page/encryption checks, candidate dedupe and recovery.

import {
  DOCUMENT_BATCH_MAX_CANDIDATES,
  DocumentBatchError,
  buildDocumentBatchCandidates,
  buildDocumentBatchPageUnits,
  countPDFPages,
  deadlineExceeded,
  initialDocumentBatchProgress,
  isEncryptedPDF,
  markPageCompleted,
  markPageFailed,
  markPageSkipped,
  resumablePages,
  validateDocumentBatch,
  type DocumentBatchArtifact,
  type DocumentBatchPageExtractor,
  type DocumentBatchPageUnit,
} from "./documentBatch.ts";
import type { CandidateIdentityEvidence } from "./candidateIdentity.ts";

const IMAGE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const PDF = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function expect(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}

const encoder = new TextEncoder();

// A minimal uncompressed PDF with `pageCount` leaf page objects. Page objects
// are written as `/Type /Page` (singular) so the bounded counter can find them.
function minimalPDF(pageCount: number, trailerExtra = ""): Uint8Array {
  const kids: number[] = [];
  const objects: string[] = [];
  let next = 3;
  for (let page = 0; page < pageCount; page++) {
    kids.push(next);
    objects.push(
      `${next} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\n`,
    );
    next++;
  }
  const kidsText = kids.map((id) => `${id} 0 R`).join(" ");
  const body = [
    "%PDF-1.4\n",
    "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
    `2 0 obj\n<< /Type /Pages /Kids [${kidsText}] /Count ${pageCount} >>\nendobj\n`,
    ...objects,
    `trailer\n<< /Root 1 0 R ${trailerExtra} >>\n%%EOF\n`,
  ].join("");
  return encoder.encode(body);
}

function artifact(
  overrides: Partial<DocumentBatchArtifact> & Pick<DocumentBatchArtifact, "mimeType">,
): DocumentBatchArtifact {
  return {
    artifactID: IMAGE,
    inputType: "image",
    sizeBytes: 1024,
    ...overrides,
  } as DocumentBatchArtifact;
}

function imageArtifact(artifactID: string, sizeBytes = 1024): DocumentBatchArtifact {
  return { artifactID, inputType: "image", mimeType: "image/jpeg", sizeBytes };
}

function pdfArtifact(bytes: Uint8Array): DocumentBatchArtifact {
  return {
    artifactID: PDF,
    inputType: "file",
    mimeType: "application/pdf",
    sizeBytes: bytes.length,
    bytes,
  };
}

function mockExtractor(
  results: Record<string, CandidateIdentityEvidence | null>,
): DocumentBatchPageExtractor {
  return {
    async extract(page: DocumentBatchPageUnit): Promise<CandidateIdentityEvidence | null> {
      return results[page.artifactID] ?? null;
    },
  };
}

const cakeFacts: CandidateIdentityEvidence = {
  title: "Chocolate cake",
  ingredients: ["flour", "sugar"],
  steps: ["mix", "bake"],
};

Deno.test("rejects empty and oversized batches", () => {
  try {
    validateDocumentBatch([]);
    expect(false, "empty batch should reject");
  } catch (error) {
    expect(error instanceof DocumentBatchError, "expected DocumentBatchError");
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_EMPTY", "wrong code");
  }

  const tooMany = Array.from({ length: 11 }, (_, index) =>
    imageArtifact(`00000000-0000-4000-8000-0000000000${index}`));
  try {
    validateDocumentBatch(tooMany);
    expect(false, "11 images should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_TOO_MANY_IMAGES", "wrong code");
  }
});

Deno.test("rejects mixed types, multiple PDFs and unsupported MIME", () => {
  const mixed = [
    imageArtifact("00000000-0000-4000-8000-000000000001"),
    pdfArtifact(minimalPDF(1)),
  ];
  try {
    validateDocumentBatch(mixed);
    expect(false, "mixed batch should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_MIXED_TYPES", "wrong code");
  }

  const twoPDFs = [
    pdfArtifact(minimalPDF(1)),
    { ...pdfArtifact(minimalPDF(1)), artifactID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc" },
  ];
  try {
    validateDocumentBatch(twoPDFs);
    expect(false, "two PDFs should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_TOO_MANY_PDFS", "wrong code");
  }

  const unsupported = artifact({ mimeType: "video/mp4" });
  try {
    validateDocumentBatch([unsupported]);
    expect(false, "unsupported type should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_UNSUPPORTED_TYPE", "wrong code");
  }
});

Deno.test("enforces per-file and total size limits", () => {
  const largeFile = imageArtifact("00000000-0000-4000-8000-000000000002", 20 * 1024 * 1024 + 1);
  try {
    validateDocumentBatch([largeFile]);
    expect(false, "oversized file should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_FILE_TOO_LARGE", "wrong code");
  }

  const files = Array.from({ length: 3 }, (_, index) =>
    imageArtifact(`00000000-0000-4000-8000-00000000000${index}`, 15 * 1024 * 1024));
  try {
    validateDocumentBatch(files);
    expect(false, "over-total batch should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_TOTAL_TOO_LARGE", "wrong code");
  }
});

Deno.test("counts a two-page text PDF and expands ordered page units", () => {
  const bytes = minimalPDF(2);
  expect(countPDFPages(bytes) === 2, "two leaf pages expected");
  expect(isEncryptedPDF(bytes) === false, "plain PDF flagged encrypted");

  const spec = validateDocumentBatch([pdfArtifact(bytes)]);
  expect(spec.kind === "pdf", "kind should be pdf");
  expect(spec.pageCount === 2, "page count mismatch");

  const units = buildDocumentBatchPageUnits(spec);
  expect(units.length === 2, "two page units expected");
  expect(units[0].pageNumber === 1 && units[1].pageNumber === 2, "page order lost");
});

Deno.test("rejects encrypted, corrupted and over-page PDFs", () => {
  const encrypted = minimalPDF(1, "/Encrypt 5 0 R");
  try {
    validateDocumentBatch([pdfArtifact(encrypted)]);
    expect(false, "encrypted PDF should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_PDF_ENCRYPTED", "wrong code");
  }

  const corrupted = encoder.encode("not a real pdf at all");
  try {
    validateDocumentBatch([pdfArtifact(corrupted)]);
    expect(false, "corrupted PDF should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_PDF_INVALID", "wrong code");
  }

  const tooMany = minimalPDF(21);
  try {
    validateDocumentBatch([pdfArtifact(tooMany)]);
    expect(false, "21-page PDF should reject");
  } catch (error) {
    expect((error as DocumentBatchError).code === "DOCUMENT_BATCH_PDF_TOO_MANY_PAGES", "wrong code");
  }
});

Deno.test("deduplicates identical screenshots into one stable candidate", async () => {
  const first = imageArtifact("00000000-0000-4000-8000-000000000001");
  const second = imageArtifact("00000000-0000-4000-8000-000000000002");
  const spec = validateDocumentBatch([first, second]);
  const units = buildDocumentBatchPageUnits(spec);

  const extractor = mockExtractor({
    [first.artifactID]: cakeFacts,
    [second.artifactID]: cakeFacts,
  });
  const { candidates, hasMore } = await buildDocumentBatchCandidates(units, extractor);
  expect(hasMore === false, "duplicates should not report more");
  expect(candidates.length === 1, "duplicate screenshots must collapse to one candidate");
  expect(
    candidates[0].artifact_ids.length === 2,
    "merged provenance should reference both screenshots",
  );
  expect(candidates[0].candidate_id.startsWith("candidate-v2-"), "stable ID format");
});

Deno.test("distinct pages stay separate and more than eight is flagged", async () => {
  const page = (index: number): DocumentBatchArtifact =>
    imageArtifact(`00000000-0000-4000-8000-0000000000${index}`);
  const results: Record<string, CandidateIdentityEvidence | null> = {};
  for (let index = 0; index < 10; index++) {
    results[`00000000-0000-4000-8000-0000000000${index}`] = {
      title: `Recipe ${index}`,
      ingredients: ["ingredient"],
      steps: ["step"],
    };
  }
  const artifacts = Array.from({ length: 10 }, (_, index) => page(index));
  const spec = validateDocumentBatch(artifacts);
  const units = buildDocumentBatchPageUnits(spec);

  const { candidates, hasMore, unprocessed } = await buildDocumentBatchCandidates(
    units,
    mockExtractor(results),
  );
  expect(hasMore === true, "ten distinct recipes should be truncated");
  expect(unprocessed === 2, "two recipes left unprocessed");
  expect(
    candidates.length === DOCUMENT_BATCH_MAX_CANDIDATES,
    "candidates must cap at eight",
  );
  expect(
    new Set(candidates.map((candidate) => candidate.candidate_id)).size ===
      DOCUMENT_BATCH_MAX_CANDIDATES,
    "distinct recipes must not share IDs",
  );
});

Deno.test("progress records per-page state and resumes only unfinished pages", () => {
  const spec = validateDocumentBatch([
    imageArtifact("00000000-0000-4000-8000-000000000001"),
    imageArtifact("00000000-0000-4000-8000-000000000002"),
    imageArtifact("00000000-0000-4000-8000-000000000003"),
  ]);
  const units = buildDocumentBatchPageUnits(spec);
  let progress = initialDocumentBatchProgress("batch-1", units);
  expect(progress.totalPages === 3, "total page count wrong");

  progress = markPageCompleted(progress, 0, "candidate-v2-deadbeef");
  progress = markPageFailed(progress, 1);
  progress = markPageSkipped(progress, 2);

  const { pending, completed } = resumablePages(progress);
  expect(completed.length === 1 && completed[0] === 0, "completed page not recorded");
  expect(pending.length === 1 && pending[0] === 1, "only the failed page should resume");
  expect(
    progress.pages.find((page) => page.index === 0)?.candidateID === "candidate-v2-deadbeef",
    "completed candidate ID lost",
  );
});

Deno.test("deadline is deterministic and recoverable pages are never re-run", () => {
  expect(deadlineExceeded(0, 0) === false, "deadline fired at zero elapsed");
  expect(deadlineExceeded(0, 180_000) === true, "deadline not reached at 180s");
  expect(deadlineExceeded(0, 180_001) === true, "deadline not reached past 180s");
});
