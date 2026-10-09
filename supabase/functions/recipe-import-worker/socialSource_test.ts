// Developer: gengyun
// Purpose: Verifies publicly readable metadata and safe social URL identifiers.

import { publicSocialSourceIdentity } from "./socialSource.ts";
import { attachPageTextEvidence, incompleteWebRecipe, parseSchemaOrgRecipePage } from "./schemaRecipe.ts";

import { extractPublicPageText } from "./pageContent.ts";

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
    "https://youtube.com/watch/other?v=AbC_123-xYz",
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

Deno.test("social identity and existing public caption evidence survive together", async () => {
  const originalURL = "https://youtu.be/AbC_123-xYz";
  const canonicalURL = "https://www.youtube.com/watch?v=AbC_123-xYz";
  const html = `<html><head>
    <meta name="twitter:title" content="Public soup clip">
    <meta name="twitter:creator" content="@visiblechef">
    <meta property="og:description" content="Salt to taste. Steps unavailable.">
    </head><body></body></html>`;
  const parsed = parseSchemaOrgRecipePage({
    id: crypto.randomUUID(), html,
    source: { originalURL, canonicalURL, platformHint: "shared" },
  });
  const result = attachPageTextEvidence(parsed, await extractPublicPageText(html, canonicalURL));
  check(result.source.external_content_id === "AbC_123-xYz");
  check(result.source.original_url === originalURL && result.source.canonical_url === canonicalURL);
  check(result.source.platform === "youtube");
  check(result.source.author_name === "@visiblechef");
  check(result.source.source_title === "Public soup clip");
  check(result.evidence.some((item) => item.source_type === "caption" &&
    String(item.excerpt).includes(canonicalURL) && String(item.excerpt).includes("Salt to taste")));
  check(result.status === "needs_review" && Object.keys(result.fields).length === 0);
});

Deno.test("structured recipe author wins without losing social identity or raw quantity", () => {
  const url = "https://instagram.com/reel/Cr8_XyZ90";
  const parsed = parseSchemaOrgRecipePage({
    id: crypto.randomUUID(),
    html: `<meta name="author" content="Page creator">
      <meta name="twitter:creator" content="@socialcreator">
      <script type="application/ld+json">${JSON.stringify({
        "@type": "Recipe", name: "Soup", author: { name: "Recipe author" },
        recipeIngredient: ["Salt to taste"], recipeInstructions: ["Simmer gently"],
      })}</script>`,
    source: { originalURL: url, canonicalURL: url, platformHint: null },
  });
  check(parsed.source.author_name === "Recipe author");
  check(parsed.source.external_content_id === "Cr8_XyZ90");
  check(parsed.status === "ready");
  check(parsed.fields["ingredients[0].amount"].raw_value === "Salt to taste");
  check(parsed.fields["ingredients[0].amount"].normalized_value === null);
});

Deno.test("redirect identity follows fetched canonical host and spoofed pages gain no social caption", async () => {
  const originalURL = "https://youtube.com/watch?v=AbC_123-xYz";
  const canonicalURL = "https://youtube.com.evil.invalid/watch?v=AbC_123-xYz";
  const html = '<meta property="og:description" content="No trusted caption">';
  const parsed = parseSchemaOrgRecipePage({
    id: crypto.randomUUID(), html,
    source: { originalURL, canonicalURL, platformHint: null },
  });
  const result = attachPageTextEvidence(parsed, await extractPublicPageText(html, canonicalURL));
  check(result.source.external_content_id === null && result.source.platform === null);
  check(result.status === "needs_review");
  check(!result.evidence.some((item) => item.source_type === "caption"));
});
