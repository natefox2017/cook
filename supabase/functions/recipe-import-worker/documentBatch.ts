// Developer: gengyun
// Purpose: Bounded batch document scanning for multiple screenshots or one limited-page PDF.

import {
  stableCandidateIDs,
  type CandidateIdentityEvidence,
} from "./candidateIdentity.ts";

export const DOCUMENT_BATCH_MAX_IMAGES = 10;
export const DOCUMENT_BATCH_MAX_PDF_PAGES = 20;
export const DOCUMENT_BATCH_MAX_FILE_BYTES = 20 * 1024 * 1024;
export const DOCUMENT_BATCH_MAX_TOTAL_BYTES = 40 * 1024 * 1024;
export const DOCUMENT_BATCH_MAX_CANDIDATES = 8;
export const DOCUMENT_BATCH_DEADLINE_MS = 180_000;

export const DOCUMENT_IMAGE_TYPES: Readonly<Record<string, true>> = {
  "image/jpeg": true,
  "image/png": true,
  "image/heic": true,
  "image/heif": true,
};

export interface DocumentBatchArtifact {
  artifactID: string;
  inputType: "image" | "file";
  mimeType: string;
  sizeBytes: number;
  // Present when server-side inspection is required (PDF page count and
  // encryption). The real worker supplies downloaded bytes after verifying
  // the owner-scoped artifact; callers that only validate metadata may omit it.
  bytes?: Uint8Array;
}

export type DocumentBatchKind = "images" | "pdf";

export interface DocumentBatchSpec {
  kind: DocumentBatchKind;
  artifacts: DocumentBatchArtifact[];
  pageCount: number;
  totalBytes: number;
}

export type DocumentBatchErrorCode =
  | "DOCUMENT_BATCH_EMPTY"
  | "DOCUMENT_BATCH_MIXED_TYPES"
  | "DOCUMENT_BATCH_UNSUPPORTED_TYPE"
  | "DOCUMENT_BATCH_TOO_MANY_IMAGES"
  | "DOCUMENT_BATCH_TOO_MANY_PDFS"
  | "DOCUMENT_BATCH_FILE_TOO_LARGE"
  | "DOCUMENT_BATCH_TOTAL_TOO_LARGE"
  | "DOCUMENT_BATCH_PDF_INVALID"
  | "DOCUMENT_BATCH_PDF_ENCRYPTED"
  | "DOCUMENT_BATCH_PDF_TOO_MANY_PAGES";

export class DocumentBatchError extends Error {
  constructor(readonly code: DocumentBatchErrorCode, message: string) {
    super(message);
    this.name = "DocumentBatchError";
  }
}

export type DocumentBatchPageStatus =
  | "pending"
  | "processing"
  | "completed"
  | "failed"
  | "skipped";

export interface DocumentBatchPageUnit {
  index: number;
  // 1-based page number within the owning document; always 1 for a standalone
  // screenshot so every page unit has a stable, order-independent label.
  pageNumber: number;
  artifactID: string;
  status: DocumentBatchPageStatus;
}

export interface DocumentBatchCandidate {
  candidate_id: string;
  title: string | null;
  ingredients: string[];
  steps: string[];
  // Provenance of the page units that collapsed into this candidate, kept so
  // evidence can reference the original pages without inventing a new model.
  page_numbers: number[];
  artifact_ids: string[];
}

export interface DocumentBatchPageState {
  index: number;
  status: DocumentBatchPageStatus;
  candidateID: string | null;
}

export interface DocumentBatchProgress {
  batchID: string;
  totalPages: number;
  pages: DocumentBatchPageState[];
}

export interface DocumentBatchPageExtractor {
  extract(
    page: DocumentBatchPageUnit,
  ): Promise<CandidateIdentityEvidence | null>;
}

function hasPDFHeader(bytes: Uint8Array): boolean {
  return bytes.length >= 5 &&
    new TextDecoder("latin1").decode(bytes.slice(0, 5)) === "%PDF-";
}

// Detects the PDF trailer encryption dictionary marker. This is intentionally
// conservative: any `/Encrypt` token marks the document as password-protected
// and rejects it rather than attempting to bypass the password.
export function isEncryptedPDF(bytes: Uint8Array): boolean {
  const head = new TextDecoder("latin1").decode(bytes.slice(0, 16 * 1024));
  return /\/Encrypt\b/.test(head);
}

// Counts leaf page objects (`/Type /Page`) without rendering the document.
// Page-tree nodes (`/Type /Pages`) are excluded by the negative lookahead.
// Compressed object streams are uncommon for page objects; a document whose
// page objects are not reachable in the first 8 MiB reports zero and is
// rejected rather than silently mis-sized.
export function countPDFPages(bytes: Uint8Array): number {
  if (!hasPDFHeader(bytes)) return 0;
  const window = new TextDecoder("latin1").decode(bytes.slice(0, 8 * 1024 * 1024));
  const matches = window.match(/\/Type\s*\/Page\b(?!s)/g);
  return matches ? matches.length : 0;
}

// Validates a batch and derives its bounded spec. Every rejection preserves the
// original source bytes; no page is ever silently dropped here.
export function validateDocumentBatch(
  artifacts: readonly DocumentBatchArtifact[],
): DocumentBatchSpec {
  if (artifacts.length === 0) {
    throw new DocumentBatchError("DOCUMENT_BATCH_EMPTY", "No documents were selected.");
  }

  const images = artifacts.filter((artifact) =>
    artifact.inputType === "image" &&
    DOCUMENT_IMAGE_TYPES[artifact.mimeType] === true
  );
  const pdfs = artifacts.filter((artifact) =>
    artifact.inputType === "file" && artifact.mimeType === "application/pdf"
  );
  if (images.length + pdfs.length !== artifacts.length) {
    throw new DocumentBatchError(
      "DOCUMENT_BATCH_UNSUPPORTED_TYPE",
      "Only JPEG, PNG, HEIC screenshots or a single PDF are supported.",
    );
  }
  if (images.length > 0 && pdfs.length > 0) {
    throw new DocumentBatchError(
      "DOCUMENT_BATCH_MIXED_TYPES",
      "Screenshots and PDFs cannot be mixed in one batch.",
    );
  }
  if (pdfs.length > 1) {
    throw new DocumentBatchError(
      "DOCUMENT_BATCH_TOO_MANY_PDFS",
      "Only one PDF may be scanned per batch.",
    );
  }
  if (pdfs.length === 0 && images.length > DOCUMENT_BATCH_MAX_IMAGES) {
    throw new DocumentBatchError(
      "DOCUMENT_BATCH_TOO_MANY_IMAGES",
      `Select at most ${DOCUMENT_BATCH_MAX_IMAGES} screenshots.`,
    );
  }

  let totalBytes = 0;
  for (const artifact of artifacts) {
    if (artifact.sizeBytes < 1 || artifact.sizeBytes > DOCUMENT_BATCH_MAX_FILE_BYTES) {
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_FILE_TOO_LARGE",
        "A selected file exceeds the per-file size limit.",
      );
    }
    totalBytes += artifact.sizeBytes;
  }
  if (totalBytes > DOCUMENT_BATCH_MAX_TOTAL_BYTES) {
    throw new DocumentBatchError(
      "DOCUMENT_BATCH_TOTAL_TOO_LARGE",
      "The batch exceeds the total size limit.",
    );
  }

  let pageCount = images.length;
  if (pdfs.length === 1) {
    const pdf = pdfs[0];
    const bytes = pdf.bytes;
    if (!bytes) {
      // Metadata-only validation cannot verify the page count; the wiring
      // layer must supply bytes before enqueueing so no over-limit PDF runs.
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_PDF_INVALID",
        "PDF bytes are required to verify page count.",
      );
    }
    if (!hasPDFHeader(bytes)) {
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_PDF_INVALID",
        "The selected file is not a readable PDF.",
      );
    }
    if (isEncryptedPDF(bytes)) {
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_PDF_ENCRYPTED",
        "Encrypted PDFs are not supported; keep the original source.",
      );
    }
    const pages = countPDFPages(bytes);
    if (pages < 1) {
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_PDF_INVALID",
        "The PDF has no readable pages.",
      );
    }
    if (pages > DOCUMENT_BATCH_MAX_PDF_PAGES) {
      throw new DocumentBatchError(
        "DOCUMENT_BATCH_PDF_TOO_MANY_PAGES",
        `The PDF exceeds the ${DOCUMENT_BATCH_MAX_PDF_PAGES}-page limit.`,
      );
    }
    pageCount = pages;
  }

  return {
    kind: pdfs.length === 1 ? "pdf" : "images",
    artifacts: [...artifacts],
    pageCount,
    totalBytes,
  };
}

// Expands a validated spec into stable, ordered page units. Images contribute
// exactly one unit each; a PDF contributes one unit per detected page.
export function buildDocumentBatchPageUnits(
  spec: DocumentBatchSpec,
): DocumentBatchPageUnit[] {
  const units: DocumentBatchPageUnit[] = [];
  let index = 0;
  for (const artifact of spec.artifacts) {
    if (artifact.inputType === "file" && artifact.mimeType === "application/pdf") {
      for (let page = 1; page <= spec.pageCount; page++) {
        units.push({
          index: index++,
          pageNumber: page,
          artifactID: artifact.artifactID,
          status: "pending",
        });
      }
    } else {
      units.push({
        index: index++,
        pageNumber: 1,
        artifactID: artifact.artifactID,
        status: "pending",
      });
    }
  }
  return units;
}

// Builds bounded, deduplicated candidates from page units. Exact duplicate
// content collapses to one stable candidate while provenance (page numbers and
// artifact IDs) is merged, so repeated screenshots never become two dishes.
export async function buildDocumentBatchCandidates(
  pageUnits: readonly DocumentBatchPageUnit[],
  extractor: DocumentBatchPageExtractor,
): Promise<{
  candidates: DocumentBatchCandidate[];
  hasMore: boolean;
  unprocessed: number;
}> {
  const unique: Array<{
    facts: CandidateIdentityEvidence;
    pageNumbers: number[];
    artifactIDs: string[];
  }> = [];

  const byKey = new Map<string, number>();
  for (const unit of pageUnits) {
    const facts = await extractor.extract(unit);
    if (!facts) continue;
    const key = JSON.stringify([facts.title, facts.ingredients, facts.steps])
      .normalize("NFC");
    const existing = byKey.get(key);
    if (existing !== undefined) {
      const slot = unique[existing];
      slot.pageNumbers.push(unit.pageNumber);
      if (!slot.artifactIDs.includes(unit.artifactID)) {
        slot.artifactIDs.push(unit.artifactID);
      }
      continue;
    }
    byKey.set(key, unique.length);
    unique.push({
      facts,
      pageNumbers: [unit.pageNumber],
      artifactIDs: [unit.artifactID],
    });
  }

  const hasMore = unique.length > DOCUMENT_BATCH_MAX_CANDIDATES;
  const selected = unique.slice(0, DOCUMENT_BATCH_MAX_CANDIDATES);
  const identities = stableCandidateIDs(selected.map((entry) => entry.facts));
  const candidates = selected.map((entry, index) => ({
    candidate_id: identities[index],
    title: entry.facts.title,
    ingredients: [...entry.facts.ingredients],
    steps: [...entry.facts.steps],
    page_numbers: entry.pageNumbers,
    artifact_ids: entry.artifactIDs,
  }));

  return {
    candidates,
    hasMore,
    unprocessed: hasMore ? unique.length - DOCUMENT_BATCH_MAX_CANDIDATES : 0,
  };
}

export function initialDocumentBatchProgress(
  batchID: string,
  pageUnits: readonly DocumentBatchPageUnit[],
): DocumentBatchProgress {
  return {
    batchID,
    totalPages: pageUnits.length,
    pages: pageUnits.map((unit) => ({
      index: unit.index,
      status: "pending",
      candidateID: null,
    })),
  };
}

function withPage(
  progress: DocumentBatchProgress,
  index: number,
  update: (state: DocumentBatchPageState) => DocumentBatchPageState,
): DocumentBatchProgress {
  return {
    ...progress,
    pages: progress.pages.map((state) =>
      state.index === index ? update(state) : state
    ),
  };
}

export function markPageCompleted(
  progress: DocumentBatchProgress,
  index: number,
  candidateID: string | null,
): DocumentBatchProgress {
  return withPage(progress, index, (state) => ({
    ...state,
    status: "completed",
    candidateID,
  }));
}

export function markPageFailed(
  progress: DocumentBatchProgress,
  index: number,
): DocumentBatchProgress {
  return withPage(progress, index, (state) => ({
    ...state,
    status: "failed",
    candidateID: null,
  }));
}

export function markPageSkipped(
  progress: DocumentBatchProgress,
  index: number,
): DocumentBatchProgress {
  return withPage(progress, index, (state) => ({
    ...state,
    status: "skipped",
    candidateID: null,
  }));
}

// Recovers which pages still need work after a deadline or crash. Completed
// pages are never re-run; failed pages are retryable while skipped pages stay
// out of the resumable set.
export function resumablePages(progress: DocumentBatchProgress): {
  pending: number[];
  completed: number[];
} {
  const pending: number[] = [];
  const completed: number[] = [];
  for (const page of progress.pages) {
    if (page.status === "completed") completed.push(page.index);
    if (page.status === "pending" || page.status === "failed") {
      pending.push(page.index);
    }
  }
  return { pending, completed };
}

export function deadlineExceeded(
  startedAt: number,
  now: number = Date.now(),
): boolean {
  return now - startedAt >= DOCUMENT_BATCH_DEADLINE_MS;
}
