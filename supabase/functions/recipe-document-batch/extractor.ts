// Developer: gengyun
// Purpose: Extracts bounded per-page recipe facts from owner-scoped batch artifacts through the approved OCR provider.

import type { OCRPage, OCRProvider } from "../recipe-import-worker/artifactOCR.ts";
import type { CandidateIdentityEvidence } from "../recipe-import-worker/candidateIdentity.ts";
import type {
  DocumentBatchArtifact,
  DocumentBatchPageExtractor,
  DocumentBatchPageUnit,
} from "../recipe-import-worker/documentBatch.ts";
import { parseLocalText } from "../recipe-import-worker/textEvidence.ts";

// A batch source may be larger than the single-source OCR path: the document
// batch contract allows up to 20 MiB per file while the page count stays at 20.
export const DOCUMENT_BATCH_OCR_MAX_BYTES = 20 * 1024 * 1024;
export const DOCUMENT_BATCH_OCR_MAX_PAGES = 20;
export const DOCUMENT_BATCH_OCR_MAX_PIXELS_PER_PAGE = 40_000_000;
export const DOCUMENT_BATCH_OCR_MAX_CHARACTERS = 100_000;
export const DOCUMENT_BATCH_OCR_TIMEOUT_MS = 8_000;

interface ExtractedTextField {
  raw_value: string | null;
}

interface ExtractedTextResult {
  fields: Record<string, ExtractedTextField>;
}

const INGREDIENT_PATH = /^ingredients\[(\d+)\]\.raw_text$/;
const STEP_PATH = /^steps\[(\d+)\]\.instruction$/;

function indexedValues(
  fields: Record<string, ExtractedTextField>,
  pattern: RegExp,
): string[] {
  const values: Array<{ index: number; value: string }> = [];
  for (const [path, field] of Object.entries(fields)) {
    const match = pattern.exec(path);
    if (!match) continue;
    const value = field.raw_value;
    if (typeof value !== "string" || value.trim().length === 0) continue;
    values.push({ index: Number(match[1]), value });
  }
  values.sort((left, right) => left.index - right.index);
  return values.map((entry) => entry.value);
}

// Maps the shared parser output to the stable candidate facts the batch builder
// fingerprints. Empty pages are dropped so a blank or image-only page never
// becomes a phantom dish.
function factsFromParsed(parsed: ExtractedTextResult): CandidateIdentityEvidence | null {
  const title = parsed.fields["title"]?.raw_value ?? null;
  const ingredients = indexedValues(parsed.fields, INGREDIENT_PATH);
  const steps = indexedValues(parsed.fields, STEP_PATH);
  if ((title ?? "").trim().length === 0 && ingredients.length === 0 && steps.length === 0) {
    return null;
  }
  return { title, ingredients, steps };
}

// Runs the approved OCR provider once per artifact and returns page facts keyed
// by 1-based page number. Image artifacts always produce a single page; PDFs
// may produce up to the bounded page limit.
async function factsForArtifact(
  artifact: DocumentBatchArtifact,
  provider: OCRProvider | null,
): Promise<CandidateIdentityEvidence[] | null> {
  const bytes = artifact.bytes;
  if (!bytes || bytes.length < 1 || bytes.length > DOCUMENT_BATCH_OCR_MAX_BYTES) {
    return null;
  }
  if (!provider) {
    // No bounded provider: the local source stays and the page is reported
    // unavailable rather than inventing text.
    return null;
  }
  const maxPages = artifact.inputType === "image" ? 1 : DOCUMENT_BATCH_OCR_MAX_PAGES;
  let pages: OCRPage[];
  try {
    pages = await provider.recognize(bytes, {
      mimeType: artifact.mimeType,
      maxPages,
      maxPixelsPerPage: DOCUMENT_BATCH_OCR_MAX_PIXELS_PER_PAGE,
      timeoutMS: DOCUMENT_BATCH_OCR_TIMEOUT_MS,
    });
  } catch {
    return null;
  }

  const facts: CandidateIdentityEvidence[] = [];
  const seen = new Set<number>();
  let characters = 0;
  const ordered = [...pages]
    .filter((page) =>
      page &&
      Number.isSafeInteger(page.page_number) &&
      page.page_number >= 1 &&
      page.page_number <= maxPages &&
      typeof page.text === "string" &&
      page.text.trim().length > 0
    )
    .sort((left, right) => left.page_number - right.page_number);

  for (const page of ordered) {
    if (seen.has(page.page_number)) continue;
    seen.add(page.page_number);
    characters += page.text.length;
    if (characters > DOCUMENT_BATCH_OCR_MAX_CHARACTERS) break;
    const parsed = parseLocalText({
      id: `document-batch-${artifact.artifactID}-${page.page_number}`,
      source_value: page.text,
    });
    const pageFacts = factsFromParsed(parsed);
    if (pageFacts) facts[page.page_number - 1] = pageFacts;
  }
  return facts;
}

// Builds the concrete extractor that the batch candidate builder consumes. A
// multi-page PDF is OCR'd once and its page facts are cached so duplicate page
// units never trigger a second provider call.
export function createDocumentBatchExtractor(
  artifacts: ReadonlyMap<string, DocumentBatchArtifact>,
  provider: OCRProvider | null,
): DocumentBatchPageExtractor {
  const cache = new Map<string, CandidateIdentityEvidence[] | null>();

  return {
    async extract(page: DocumentBatchPageUnit): Promise<CandidateIdentityEvidence | null> {
      const artifact = artifacts.get(page.artifactID);
      if (!artifact) return null;

      let pageFacts = cache.get(artifact.artifactID);
      if (pageFacts === undefined) {
        pageFacts = await factsForArtifact(artifact, provider);
        cache.set(artifact.artifactID, pageFacts);
      }
      if (!pageFacts) return null;

      const index = artifact.inputType === "image" ? 0 : page.pageNumber - 1;
      return pageFacts[index] ?? null;
    },
  };
}
