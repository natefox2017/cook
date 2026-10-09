// Developer: gengyun
// Purpose: Checks public social metadata, origin restrictions, and no inferred recipes.

import { publicSocialMetadata } from "./publicSocialMetadata.ts";
import { extractPublicPageText } from "./pageContent.ts";
import { parseSchemaOrgRecipePage, attachPageTextEvidence } from "./schemaRecipe.ts";

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const html = `<html><head>
  <meta property="og:title" content="Salted tomato toast">
  <meta property="og:description" content="Ingredients: salt to taste. Full steps unavailable.">
  <meta name="twitter:creator" content="@homecook">
</head><body><main><h1>Video post</h1></main></body></html>`;

Deno.test("trusted public social posts preserve platform, author and caption evidence", async () => {
  const url = "https://www.tiktok.com/@homecook/video/1234567890123456789";
  const meta = publicSocialMetadata(html, url);
  expect(meta.platform === "tiktok", "Platform detection failed");
  expect(meta.title === "Salted tomato toast", "Metadata title lost");
  expect(meta.authorName === "@homecook", "Published creator lost");
  const evidence = await extractPublicPageText(html, url);
  const caption = evidence.find((item) => item.sourceType === "caption");
  expect(caption?.excerpt.includes(url) === true, "Caption source not traceable");
  expect(caption?.text.includes("salt to taste") === true, "Caption lost ambiguous amounts");

  const parsed = parseSchemaOrgRecipePage({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    html,
    source: { originalURL: url, canonicalURL: url, platformHint: null },
  });
  const result = attachPageTextEvidence(parsed, evidence);
  expect(result.source.original_url === url, "Submitted URL overwritten");
  expect(result.source.platform === "tiktok", "Result platform missing");
  expect(result.source.author_name === "@homecook", "Result author missing");
  expect(result.source.source_title === "Salted tomato toast", "Source title missing");
  expect(result.status === "needs_review", "Caption was promoted to full recipe");
  expect(result.fields["steps[0].instruction"] === undefined, "Invented cooking steps");
});

Deno.test("YouTube and Instagram only use exact post host and route", () => {
  expect(publicSocialMetadata(html, "https://youtu.be/dQw4w9WgXcQ").platform === "youtube", "Shortlink");
  expect(publicSocialMetadata(html, "https://youtube.com/watch?v=abc").platform === "youtube", "Watch");
  expect(publicSocialMetadata(html, "https://instagram.com/reel/ABC123/").platform === "instagram", "Reel");
  expect(publicSocialMetadata(html, "https://www.youtube.com/").caption === null, "Homepage caption");
  expect(publicSocialMetadata(html, "https://www.tiktok.com/@user").platform === null, "Profile caption");
  expect(publicSocialMetadata(html, "https://notyoutube.com/watch?v=abc").platform === null, "Spoofed host");
  expect(publicSocialMetadata(html, "https://evil.example/instagram.com/reel/abc").platform === null, "Fake path");
  expect(publicSocialMetadata(html, "http://youtube.com/watch?v=abc").platform === null, "Plain HTTP");
});
