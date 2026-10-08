// Developer: gengyun
// Purpose: Extracts publicly exposed social post metadata without fetching media.

import { load } from "cheerio";

export interface PublicSocialMetadata {
  platform: "tiktok" | "instagram" | "youtube" | null;
  title: string | null;
  authorName: string | null;
  caption: string | null;
}

function clean(value: string | undefined, max: number): string | null {
  if (!value) return null;
  const normalized = value.replace(/[\s\u00a0]+/g, " ").trim();
  return normalized ? normalized.slice(0, max) : null;
}

function hostMatches(host: string, suffix: string): boolean {
  return host === suffix || host.endsWith(`.${suffix}`);
}

function postPlatform(url: URL): PublicSocialMetadata["platform"] {
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  const path = url.pathname;
  if (hostMatches(host, "tiktok.com")) {
    return /^\/@[^/]+\/video\/\d+(?:\/|$)/.test(path) ? "tiktok" : null;
  }
  if (hostMatches(host, "instagram.com")) {
    return /^\/(?:p|reel|tv)\/[^/]+(?:\/|$)/.test(path) ? "instagram" : null;
  }
  if (hostMatches(host, "youtu.be")) {
    return /^\/[^/]+(?:\/|$)/.test(path) ? "youtube" : null;
  }
  if (hostMatches(host, "youtube.com")) {
    return (path === "/watch" && Boolean(url.searchParams.get("v"))) ||
        /^\/(?:shorts|live)\/[^/]+(?:\/|$)/.test(path)
      ? "youtube"
      : null;
  }
  return null;
}

export function publicSocialMetadata(
  html: string,
  canonicalURL: string,
): PublicSocialMetadata {
  const empty: PublicSocialMetadata = {
    platform: null,
    title: null,
    authorName: null,
    caption: null,
  };
  let url: URL;
  try {
    url = new URL(canonicalURL);
  } catch {
    return empty;
  }
  // This module only annotates already-fetched public HTTPS documents.
  if (url.protocol !== "https:") return empty;
  const platform = postPlatform(url);
  if (!platform) return empty;

  const $ = load(html, { scriptingEnabled: false });
  const meta = (selector: string): string | undefined =>
    $(selector).first().attr("content") ?? undefined;

  const title = clean(
    meta('meta[property="og:title"]') ??
      meta('meta[name="twitter:title"]') ??
      $("title").first().text(),
    200,
  );
  const authorName = clean(
    meta('meta[name="author"]') ??
      meta('meta[property="article:author"]') ??
      meta('meta[name="twitter:creator"]'),
    120,
  );
  const caption = clean(
    meta('meta[property="og:description"]') ??
      meta('meta[name="twitter:description"]') ??
      meta('meta[name="description"]'),
    3_000,
  );
  return { platform, title, authorName, caption };
}
