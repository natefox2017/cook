// Developer: gengyun
// Purpose: Verifies publicly readable metadata and safe social URL identifiers.

import { publicSocialSourceIdentity } from "./socialSource.ts";
import { incompleteWebRecipe, parseSchemaOrgRecipePage } from "./schemaRecipe.ts";

function check(value: unknown): asserts value {
  if (!value) throw Error("Public source regression");
}

Deno.test("public identifiers are scoped to verified platform URLs", () => {
  const known = [
    ["https://youtube.com/watch?v=AbC_123-xYz", "youtube", "AbC_123-xYz"],
    ["https://youtu.be/AbC_123-xYz", "youtube", "AbC_123-xYz"],
    ["https://instagram.com/reel/Cr8_XyZ90/", "instagram", "Cr8_XyZ90"],
    ["https://tiktok.com/@chef.abc/video/7234567890123456789", "tiktok", "7234567890123456789"],
  ];
  for (const [url, platform, id] of known) {
    const identity = publicSocialSourceIdentity(url);
    check(identity?.platform === platform && identity.id === id);
    const parsed = incompleteWebRecipe({
      id: crypto.randomUUID(), originalURL: url, platformHint: null,
    });
    check(parsed.source.external_content_id === id);
    check(parsed.source.canonical_url === null);
    check(parsed.source.author_name === null);
    check(parsed.status === "needs_review");
    check(Object.keys(parsed.fields).length === 0 && parsed.evidence.length === 0);
  }
});

Deno.test("spoofing, non-HTTPS, opaque and invalid URLs never gain an ID", () => {
  for (const url of [
    "https://youtube.com.evil.invalid/watch?v=AbC_123-xYz",
    "http://youtube.com/watch?v=AbC_123-xYz",
    "https://user:password@youtube.com/watch?v=AbC_123-xYz",
    "https://youtu.be/invalid",
    "https://instagram.com.evil.invalid/reel/Cr8_XyZ90",
    "https://vm.tiktok.com/unknown",
    "https://example.org/cooking",
  ]) check(publicSocialSourceIdentity(url) === null);
});

Deno.test("HTML author and title are retained, not invented recipe fields", () => {
  const url = "https://instagram.com/reel/Cr8_XyZ90";
  const parsed = parseSchemaOrgRecipePage({
    id: crypto.randomUUID(),
    html: `<html><head><meta property="og:title" content="Soup">
      <meta name="author" content="Public creator"></head>
      <body><p>Photo of soup</p></body></html>`,
    source: { originalURL: url, canonicalURL: url, platformHint: null },
  });
  check(parsed.source.source_title === "Soup");
  check(parsed.source.author_name === "Public creator");
  check(parsed.source.platform === "instagram");
  check(parsed.source.external_content_id === "Cr8_XyZ90");
  check(parsed.status === "needs_review");
  check(Object.keys(parsed.fields).length === 0);
});
