// Developer: gengyun
// Purpose: Extracts public article and caption text as source-linked evidence.

import { load } from "cheerio";
import { fetchPublicVTT } from "./safeURLFetch.ts";
import { publicSocialMetadata } from "./publicSocialMetadata.ts";

export type PageTextSourceType = "article_body" | "caption" | "subtitle";

export interface PageTextEvidence {
  id: string;
  sourceType: PageTextSourceType;
  text: string;
  excerpt: string;
  capturedAt: string;
  title?: string;
}

const MAX_EVIDENCE_CHARS = 10_000;
const MAX_TRACKS = 3;
const MAX_INLINE_TRANSCRIPTS = 3;
const TRACKS_TOTAL_TIMEOUT_MS = 3_500;

export async function extractPublicPageText(
  html: string,
  canonicalURL: string,
): Promise<PageTextEvidence[]> {
  const $ = load(html, { scriptingEnabled: false });
  const evidence: PageTextEvidence[] = [];
  const seen = new Set<string>();

  // Public post metadata can preserve a caption without media downloads.
  // It is only evidence, never a fabricated transcript or recipe step.
  const social = publicSocialMetadata(html, canonicalURL);
  if (social.caption) {
    appendEvidence(evidence, seen, "caption", social.caption, canonicalURL);
  }

  const article = visibleArticleContent($);
  if (article.text) {
    appendEvidence(
      evidence,
      seen,
      "article_body",
      article.text,
      canonicalURL,
      article.title,
    );
  }

  const inlineSelector =
    "[itemprop='transcript'], [data-transcript], [data-caption], script[type='text/vtt']";
  let inlineCount = 0;
  $(inlineSelector).each((_index, element) => {
    if (inlineCount >= MAX_INLINE_TRANSCRIPTS) return false;
    const item = $(element);
    if (item.closest("[hidden], [aria-hidden='true']").length > 0) return;

    const isVTT = element.tagName.toLowerCase() === "script";
    const inlineText = item.text();
    const explicitText = item.attr("data-transcript")
      ?? item.attr("data-caption");
    const candidateText = explicitText && !isWebURL(explicitText)
      ? explicitText
      : inlineText;
    const text = isVTT
      ? vttText(inlineText)
      : normalizedText(candidateText);
    if (!text) return;
    inlineCount++;
    appendEvidence(
      evidence,
      seen,
      isVTT || item.attr("data-transcript") || item.attr("itemprop") === "transcript"
        ? "subtitle"
        : "caption",
      text,
      canonicalURL,
      undefined,
      isVTT ? inlineText : text,
    );
  });

  const trackURLs = new Set<string>();
  $("track").each((_index, element) => {
    const kind = ($(element).attr("kind") ?? "").toLowerCase();
    if (kind !== "captions" && kind !== "subtitles") return;
    const source = $(element).attr("src");
    if (!source) return;
    try {
      const url = new URL(source, canonicalURL);
      if (/\.(?:vtt|webvtt)$/i.test(url.pathname)) {
        trackURLs.add(url.toString());
      }
    } catch {
      // Invalid track URLs are ignored; the original page remains available.
    }
  });

  const tracksDeadline = Date.now() + TRACKS_TOTAL_TIMEOUT_MS;
  for (const trackURL of [...trackURLs].slice(0, MAX_TRACKS)) {
    const remainingMS = tracksDeadline - Date.now();
    if (remainingMS <= 0) break;
    try {
      const track = await fetchPublicVTT(trackURL, remainingMS);
      const text = vttText(track.text);
      if (!text) continue;
      appendEvidence(
        evidence,
        seen,
        "subtitle",
        text,
        track.canonicalURL,
        undefined,
        track.text,
      );
    } catch {
      // An unavailable track cannot invalidate public page text or JSON-LD.
    }
  }

  return evidence;
}

function visibleArticleContent(
  $: ReturnType<typeof load>,
): { text: string; title?: string } {
  const articles = $("article").toArray();
  const candidates = articles.length ? articles : $("main").toArray();
  const roots = candidates.length ? candidates : $("body").toArray();
  let longest: { text: string; title?: string } = { text: "" };

  for (const root of roots) {
    if ($(root).closest("[hidden], [aria-hidden='true']").length > 0) continue;
    const content = $(root).clone();
    content.find(
      "script, style, noscript, template, nav, header, footer, aside, form, button, svg, canvas, iframe, object, embed, video, audio, [hidden], [aria-hidden='true']",
    ).remove();
    content.find("[style]").each((_index, element) => {
      const style = ($(element).attr("style") ?? "").toLowerCase()
        .replace(/\s+/g, "");
      if (style.includes("display:none") || style.includes("visibility:hidden")) {
        $(element).remove();
      }
    });
    const title = normalizedText(content.find("h1").first().text())
      .slice(0, 150) || undefined;
    content.find("br").replaceWith("\n");
    content.find("h1, h2, h3, h4, h5, h6, p, li, dt, dd, blockquote, section, div")
      .each((_index, element) => {
        $(element).prepend("\n").append("\n");
      });

    const text = normalizedText(content.text());
    if (text.length > longest.text.length) longest = { text, title };
  }

  return {
    text: longest.text.slice(0, MAX_EVIDENCE_CHARS),
    title: longest.title,
  };
}

function normalizedText(value: string): string {
  return value.split(/\r?\n/)
    .map((line) => line.replace(/[\t\f\v ]+/g, " ").trim())
    .filter(Boolean)
    .join("\n");
}

function isWebURL(value: string): boolean {
  return /^(?:https?:)?\/\//i.test(value.trim());
}

function vttText(value: string): string {
  const lines = value.replace(/^\uFEFF/, "").split(/\r?\n/);
  const transcript: string[] = [];
  let skippingBlock = false;

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();
    if (!line) {
      skippingBlock = false;
      continue;
    }
    if (/^WEBVTT(?:[ \t].*)?$/i.test(line)) {
      skippingBlock = false;
      continue;
    }
    if (/^(?:NOTE(?:[ \t].*)?|STYLE|REGION)$/i.test(line)) {
      skippingBlock = true;
      continue;
    }
    if (skippingBlock || /\d{2}:\d{2}(?::\d{2})?\.\d{3}\s+-->/.test(line)) {
      continue;
    }
    if (
      !line.includes("-->") &&
      /\d{2}:\d{2}(?::\d{2})?\.\d{3}\s+-->/.test(lines[index + 1] ?? "")
    ) {
      continue;
    }

    const cue = decodeEntities(line.replace(/<[^>]*>/g, "")).trim();
    if (cue && transcript.at(-1) !== cue) transcript.push(cue);
  }

  return normalizedText(transcript.join("\n")).slice(0, MAX_EVIDENCE_CHARS);
}

function decodeEntities(value: string): string {
  return value.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (entity, name: string) => {
    const lower = name.toLowerCase();
    if (lower === "amp") return "&";
    if (lower === "lt") return "<";
    if (lower === "gt") return ">";
    if (lower === "quot") return '"';
    if (lower === "apos") return "'";
    if (lower === "nbsp") return " ";
    const codePoint = lower.startsWith("#x")
      ? Number.parseInt(lower.slice(2), 16)
      : Number.parseInt(lower.slice(1), 10);
    return Number.isFinite(codePoint) && codePoint <= 0x10ffff
      ? String.fromCodePoint(codePoint)
      : entity;
  });
}

function appendEvidence(
  evidence: PageTextEvidence[],
  seen: Set<string>,
  sourceType: PageTextSourceType,
  sourceText: string,
  sourceURL: string,
  title?: string,
  excerptText = sourceText,
): void {
  const text = normalizedText(sourceText).slice(0, MAX_EVIDENCE_CHARS);
  if (!text) return;
  const key = `${sourceType}\n${text}`;
  if (seen.has(key)) return;
  seen.add(key);

  const attribution = `Source: ${sourceURL}\n`;
  const excerptBody = normalizedText(excerptText).slice(
    0,
    MAX_EVIDENCE_CHARS - attribution.length,
  );
  evidence.push({
    id: crypto.randomUUID(),
    sourceType,
    text,
    excerpt: attribution + excerptBody,
    capturedAt: new Date().toISOString(),
    title,
  });
}
