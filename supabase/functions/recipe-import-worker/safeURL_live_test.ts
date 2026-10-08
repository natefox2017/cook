// Developer: gengyun
// Purpose: Verify one real public recipe page through DNS-pinned HTTPS and JSON-LD parsing.

import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { parseSchemaOrgRecipePage } from "./schemaRecipe.ts";
import { fetchPublicHTML } from "./safeURLFetch.ts";

const liveTestEnabled = Deno.env.get("RECIPE_IMPORT_LIVE_TEST") === "1";
const publicRecipeURL =
  "https://www.bbcgoodfood.com/recipes/easy-chocolate-cake";

async function resolvePublicIPv4WithDoH(
  host: string,
  signal: AbortSignal,
): Promise<string[]> {
  const endpoint = new URL("https://cloudflare-dns.com/dns-query");
  endpoint.searchParams.set("name", host);
  endpoint.searchParams.set("type", "A");
  const response = await fetch(endpoint, {
    headers: { Accept: "application/dns-json" },
    signal,
  });
  if (!response.ok) throw new Error(`DoH resolver returned ${response.status}`);
  const result = await response.json() as {
    Answer?: Array<{ type?: number; data?: string }>;
  };
  return (result.Answer ?? []).filter((answer) => answer.type === 1)
    .map((answer) => answer.data ?? "");
}

Deno.test({
  name: "live public page uses DNS-pinned HTTPS and extracts recipe evidence",
  ignore: !liveTestEnabled,
  fn: async () => {
    const page = await fetchPublicHTML(publicRecipeURL, {
      // This test-only DoH resolver bypasses the workstation's synthetic DNS
      // response. Production still uses Deno.resolveDns and fails closed.
      resolveIPv4: resolvePublicIPv4WithDoH,
    });
    const recipe = parseSchemaOrgRecipePage({
      id: "123e4567-e89b-12d3-a456-426614174010",
      html: page.html,
      source: {
        originalURL: publicRecipeURL,
        canonicalURL: page.canonicalURL,
        platformHint: null,
      },
    });

    assertEquals(recipe.status, "ready");
    assertEquals(recipe.fields.title.raw_value, "Easy chocolate cake");
    assert(
      Object.keys(recipe.fields).some((key) => key.startsWith("ingredients[")),
    );
    assert(Object.keys(recipe.fields).some((key) => key.startsWith("steps[")));
    assertEquals(recipe.source.original_url, publicRecipeURL);
    assertEquals(recipe.source.canonical_url, page.canonicalURL);
    assert(recipe.evidence.length > 0);
  },
});
