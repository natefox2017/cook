// Developer: gengyun
// Purpose: Converts approved private image/PDF OCR output into bounded, source-linked recipe evidence.

import { parseLocalText } from "./textEvidence.ts";
import type { ParsedWebRecipe } from "./schemaRecipe.ts";

export const OCR_MAX_BYTES = 10 * 1024 * 1024;
export const OCR_MAX_PAGES = 20;
export const OCR_MAX_PIXELS_PER_PAGE = 40_000_000;
export const OCR_MAX_CHARACTERS = 100_000;

export interface OCRPage {
  page_number: number;
  text: string;
  confidence: number;
  pixel_count: number;
}

export interface OCRProvider {
  recognize(
    bytes: Uint8Array,
    controls: {
      mimeType: string;
      maxPages: number;
      maxPixelsPerPage: number;
      timeoutMS: number;
    },
  ): Promise<OCRPage[]>;
}

export class OCRArtifactError extends Error {
  constructor(
    readonly code:
      | "OCR_UNAVAILABLE"
      | "OCR_INVALID_SOURCE"
      | "OCR_INVALID_RESULT"
      | "OCR_NO_TEXT",
    message: string,
  ) {
    super(message);
    this.name = "OCRArtifactError";
  }
}

export async function parsePrivateOCRArtifact(input: {
  recipeID: string;
  artifactID: string;
  inputType: "image" | "file";
  mimeType: string;
  bytes: Uint8Array;
  platformHint: string | null;
  originalSourceURL: string | null;
  provider: OCRProvider;
}): Promise<ParsedWebRecipe> {
  const image = input.inputType === "image" &&
    ["image/jpeg", "image/png", "image/heic", "image/heif"].includes(input.mimeType);
  const pdf = input.inputType === "file" && input.mimeType === "application/pdf";
  if (!image && !pdf) {
    throw new OCRArtifactError("OCR_INVALID_SOURCE", "Unsupported OCR artifact type.");
  }
  if (input.bytes.length < 1 || input.bytes.length > OCR_MAX_BYTES) {
    throw new OCRArtifactError("OCR_INVALID_SOURCE", "The OCR artifact exceeds its size limit.");
  }

  const maxPages = image ? 1 : OCR_MAX_PAGES;
  let supplied: OCRPage[];
  try {
    supplied = await input.provider.recognize(input.bytes, {
      mimeType: input.mimeType,
      maxPages,
      maxPixelsPerPage: OCR_MAX_PIXELS_PER_PAGE,
      timeoutMS: 8_000,
    });
  } catch (error) {
    if (error instanceof OCRArtifactError) throw error;
    throw new OCRArtifactError("OCR_UNAVAILABLE", "The approved OCR provider is unavailable.");
  }
  if (!Array.isArray(supplied) || supplied.length > maxPages) {
    throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR returned too many pages.");
  }
  const seen = new Set<number>();
  const pages: OCRPage[] = [];
  let characters = 0;
  for (const page of supplied) {
    if (
      !page || !Number.isSafeInteger(page.page_number) ||
      page.page_number < 1 || page.page_number > maxPages ||
      seen.has(page.page_number) ||
      typeof page.text !== "string" ||
      !Number.isFinite(page.confidence) ||
      page.confidence < 0 || page.confidence > 1 ||
      !Number.isSafeInteger(page.pixel_count) ||
      page.pixel_count < 1 || page.pixel_count > OCR_MAX_PIXELS_PER_PAGE
    ) {
      throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR page metadata is invalid.");
    }
    seen.add(page.page_number);
    characters += page.text.length;
    if (characters > OCR_MAX_CHARACTERS) {
      throw new OCRArtifactError("OCR_INVALID_RESULT", "OCR text exceeds its character limit.");
    }
    if (page.text.trim()) pages.push(page);
  }
  if (pages.length === 0) {
    throw new OCRArtifactError("OCR_NO_TEXT", "The source has no readable OCR text.");
  }
  pages.sort((lhs, rhs) => lhs.page_number - rhs.page_number);

  const combinedText = pages.map((page) => page.text).join("\n");
  const parsed = parseLocalText({
    id: input.recipeID,
    source_value: combinedText,
    original_source_url: input.originalSourceURL,
    platform_hint: input.platformHint,
  });
  const capturedAt = new Date().toISOString();
  const evidencePages = pages.map((page) => ({
    page,
    id: crypto.randomUUID(),
  }));
  const evidence = evidencePages.map(({ page, id }) => ({
    id,
    source_type: "ocr",
    origin: "extracted",
    source_artifact_id: input.artifactID,
    excerpt: `Page ${page.page_number}: ${page.text.slice(0, 9_950)}`,
    confidence: page.confidence,
    captured_at: capturedAt,
  }));
  const review = new Set(parsed.review_fields);
  const fields: ParsedWebRecipe["fields"] = {};

  for (const [path, field] of Object.entries(parsed.fields)) {
    const text = field.raw_value?.trim();
    if (!text) continue;
    const sourcePages = evidencePages.filter(({ page }) =>
      page.text.includes(text)
    );
    // A field without a matching OCR page is not source-grounded.
    if (sourcePages.length === 0) {
      review.add("ocr_evidence");
      continue;
    }
    const confidence = Math.min(...sourcePages.map(({ page }) => page.confidence));
    fields[path] = {
      ...field,
      evidence_ids: sourcePages.map(({ id }) => id),
      confidence,
      origin: "extracted",
    };
    if (confidence < 0.85) review.add("ocr_confidence");
  }

  if (!Object.keys(fields).some((key) => key === "title")) review.add("title");
  if (!Object.keys(fields).some((key) => key.startsWith("ingredients["))) review.add("ingredients");
  if (!Object.keys(fields).some((key) => key.startsWith("steps["))) review.add("steps");

  return {
    recipe_id: input.recipeID,
    status: review.size ? "needs_review" : "ready",
    source: {
      input_type: input.inputType,
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
