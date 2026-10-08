// Developer: gengyun
// Purpose: Reads selectable text from private PDFs with bounded PDF.js processing and per-page evidence.

import { getDocumentProxy } from "npm:unpdf@1.8.1";
import { parseLocalText } from "./textEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

const MAX_PDF_BYTES = 10 * 1024 * 1024;
const MAX_PAGES = 20;
const MAX_PDF_CHARACTERS = 100_000;
const MAX_IMAGE_PIXELS = 16_777_216;
const PARSE_DEADLINE_MS = 8_000;

export class PDFArtifactError extends Error {
  constructor(
    readonly code:
      | "PDF_INVALID_SOURCE"
      | "PDF_TOO_LARGE"
      | "PDF_TOO_MANY_PAGES"
      | "PDF_NO_SELECTABLE_TEXT"
      | "PDF_PARSE_FAILED",
    message: string,
  ) {
    super(message);
    this.name = "PDFArtifactError";
  }
}

export interface SelectablePDFPage {
  pageNumber: number;
  text: string;
}

export function parseSelectablePDFPages(input: {
  recipeID: string;
  artifactID: string;
  pages: SelectablePDFPage[];
  platformHint: string | null;
  originalSourceURL: string | null;
}): ParsedWebRecipe {
  if (input.pages.length < 1 || input.pages.length > MAX_PAGES) {
    throw new PDFArtifactError("PDF_TOO_MANY_PAGES", "The shared PDF has an unsupported page count.");
  }
  const seen = new Set<number>();
  const pages: SelectablePDFPage[] = [];
  let total = 0;
  for (const page of input.pages) {
    if (
      !Number.isSafeInteger(page.pageNumber) ||
      page.pageNumber < 1 || page.pageNumber > MAX_PAGES ||
      seen.has(page.pageNumber) || typeof page.text !== "string"
    ) {
      throw new PDFArtifactError("PDF_INVALID_SOURCE", "The PDF page index is invalid.");
    }
    seen.add(page.pageNumber);
    total += page.text.length;
    if (total > MAX_PDF_CHARACTERS) {
      throw new PDFArtifactError("PDF_TOO_LARGE", "The extracted PDF text is too long.");
    }
    if (page.text.trim()) pages.push(page);
  }
  if (pages.length === 0) {
    throw new PDFArtifactError("PDF_NO_SELECTABLE_TEXT", "The PDF has no selectable text.");
  }
  pages.sort((a, b) => a.pageNumber - b.pageNumber);
  const parsed = parseLocalText({
    id: input.recipeID,
    source_value: pages.map((page) => page.text).join("\n"),
    original_source_url: input.originalSourceURL,
    platform_hint: input.platformHint,
  });

  const capturedAt = new Date().toISOString();
  const pageEvidence = pages.map((page) => ({
    page,
    id: crypto.randomUUID(),
  }));
  const evidence = pageEvidence.map(({ page, id }) => ({
    id,
    source_type: "user",
    origin: "extracted",
    source_artifact_id: input.artifactID,
    excerpt: `Page ${page.pageNumber}: ${page.text.slice(0, 9_950)}`,
    confidence: 1,
    captured_at: capturedAt,
  }));
  const fields: ParsedWebRecipe["fields"] = {};
  const review = new Set(parsed.review_fields);
  for (const [path, field] of Object.entries(parsed.fields)) {
    const raw = field.raw_value?.trim();
    if (!raw) continue;
    const sources = pageEvidence.filter(({ page }) => page.text.includes(raw));
    if (sources.length === 0) {
      review.add("pdf_evidence");
      continue;
    }
    fields[path] = {
      ...field,
      evidence_ids: sources.map(({ id }) => id),
      confidence: 0.98,
    };
  }

  if (!fields.title) review.add("title");
  if (!Object.keys(fields).some((key) => key.startsWith("ingredients["))) {
    review.add("ingredients");
  }
  if (!Object.keys(fields).some((key) => key.startsWith("steps["))) {
    review.add("steps");
  }

  return {
    recipe_id: input.recipeID,
    status: review.size ? "needs_review" : "ready",
    source: {
      input_type: "file",
      original_url: input.originalSourceURL,
      canonical_url: null,
      source_artifact_id: input.artifactID,
      platform: input.platformHint,
      author_name: null,
      source_title: null,
    },
    fields,
    evidence,
    review_fields: [...review],
  };
}

export async function extractSelectablePDFArtifact(input: {
  recipeID: string;
  artifactID: string;
  bytes: Uint8Array;
  expectedBytes: number;
  platformHint: string | null;
  originalSourceURL: string | null;
}): Promise<ParsedWebRecipe> {
  if (
    input.bytes.length < 5 ||
    input.bytes.length !== input.expectedBytes ||
    input.bytes.length > MAX_PDF_BYTES ||
    new TextDecoder().decode(input.bytes.subarray(0, 5)) !== "%PDF-"
  ) {
    throw new PDFArtifactError("PDF_INVALID_SOURCE", "Invalid or oversized PDF source.");
  }

  const deadline = Date.now() + PARSE_DEADLINE_MS;
  let pdf: Awaited<ReturnType<typeof getDocumentProxy>> | null = null;
  try {
    // unpdf's bundled serverless PDF.js runs without a browser worker;
    // bound image decoding and walk pages sequentially (no fan-out).
    pdf = await getDocumentProxy(input.bytes, {
      maxImageSize: MAX_IMAGE_PIXELS,
      // Bundled PDF.js removed its eval path and the isEvalSupported option.
      disableFontFace: true,
    });
    if (pdf.numPages < 1 || pdf.numPages > MAX_PAGES) {
      throw new PDFArtifactError("PDF_TOO_MANY_PAGES", "The shared PDF exceeds 20 pages.");
    }
    const pages: SelectablePDFPage[] = [];
    let totalCharacters = 0;
    for (let number = 1; number <= pdf.numPages; number++) {
      if (Date.now() > deadline) {
        throw new PDFArtifactError("PDF_PARSE_FAILED", "PDF extraction took too long.");
      }
      const page = await pdf.getPage(number);
      const content = await page.getTextContent();
      const fragments: string[] = [];
      for (const item of content.items) {
        if (!("str" in item) || !item.str) continue;
        fragments.push(item.str);
        fragments.push(item.hasEOL ? "\n" : " ");
      }
      page.cleanup();
      const text = fragments.join("").replace(/[\t\r ]+/g, " ").trim();
      totalCharacters += text.length;
      if (totalCharacters > MAX_PDF_CHARACTERS) {
        throw new PDFArtifactError("PDF_TOO_LARGE", "The extracted PDF text is too long.");
      }
      pages.push({ pageNumber: number, text });
    }
    return parseSelectablePDFPages({
      recipeID: input.recipeID,
      artifactID: input.artifactID,
      pages,
      platformHint: input.platformHint,
      originalSourceURL: input.originalSourceURL,
    });
  } catch (error) {
    if (error instanceof PDFArtifactError) throw error;
    throw new PDFArtifactError("PDF_PARSE_FAILED", "The shared PDF could not be read safely.");
  } finally {
    // A cleanup failure must not mask an actionable parse/no-text error.
    try {
      await pdf?.loadingTask.destroy();
    } catch {
      // The parser has no persistent state; Edge runtime releases the isolate.
    }
  }
}
