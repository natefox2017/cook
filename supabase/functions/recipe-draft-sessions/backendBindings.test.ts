// Developer: gengyun
// Purpose: Verify actual Auth SDK and AES-GCM library bindings with synthetic local responses.
import { strict as assert } from "node:assert";
import { encryptAISecret } from "../_shared/ai-secret.ts";
import { createRecipeDraftBackendBindings } from "./backendBindings.ts";

const owner = "00000001-0000-0000-0000-000000000000";
const model = "00000002-0000-0000-0000-000000000000";
const provider = "00000003-0000-0000-0000-000000000000";
const key = btoa(String.fromCharCode(...new Uint8Array(32).fill(37)))
  .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const json = (v: unknown) =>
  new Response(JSON.stringify(v), {
    headers: { "content-type": "application/json" },
  });

Deno.test("real requireUser SDK binds original Bearer and rejects anonymous/missing/invalid users without network", async () => {
  const priorFetch = globalThis.fetch;
  const oldURL = Deno.env.get("SUPABASE_URL");
  const oldAnon = Deno.env.get("SUPABASE_ANON_KEY");
  let calls = 0;
  let anonymous = false;
  let invalid = false;
  try {
    Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
    Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon");
    globalThis.fetch = async (input, init) => {
      const request = new Request(input, init);
      assert.equal(request.url, "https://synthetic.invalid/auth/v1/user");
      assert.equal(
        request.headers.get("authorization"),
        "Bearer synthetic-user-token",
      );
      assert.equal(request.headers.get("apikey"), "synthetic-anon");
      calls++;
      return invalid
        ? new Response('{"message":"synthetic invalid token"}', {
          status: 401,
          headers: { "content-type": "application/json" },
        })
        : json({
          id: owner,
          is_anonymous: anonymous,
          aud: "authenticated",
          role: "authenticated",
          email: "synthetic@example.invalid",
          app_metadata: {},
          user_metadata: {},
          created_at: "2026-01-01T00:00:00Z",
        });
    };
    const bound = createRecipeDraftBackendBindings({
      enabled: true,
      supabaseRESTBaseURL: new URL("https://synthetic.invalid/rest/v1"),
      serviceRoleKey: "synthetic-service",
      encodedAISecretKey: key,
      postgrestTransport: async () => {
        throw new Error("Auth must not use service-role REST transport");
      },
    });
    const request = () =>
      new Request("https://synthetic.invalid/recipe-draft-sessions", {
        headers: { authorization: "Bearer synthetic-user-token" },
      });
    assert.deepEqual(await bound.handlerDependencies.verifiedOwner(request()), {
      id: owner,
      isAnonymous: false,
    });
    anonymous = true;
    assert.equal(
      await bound.handlerDependencies.verifiedOwner(request()),
      null,
    );
    anonymous = false;
    invalid = true;
    assert.equal(
      await bound.handlerDependencies.verifiedOwner(request()),
      null,
    );
    assert.equal(
      await bound.handlerDependencies.verifiedOwner(
        new Request("https://synthetic.invalid"),
      ),
      null,
    );
    assert.equal(calls, 3);
  } finally {
    globalThis.fetch = priorFetch;
    oldURL === undefined
      ? Deno.env.delete("SUPABASE_URL")
      : Deno.env.set("SUPABASE_URL", oldURL);
    oldAnon === undefined
      ? Deno.env.delete("SUPABASE_ANON_KEY")
      : Deno.env.set("SUPABASE_ANON_KEY", oldAnon);
  }
});

Deno.test("real v2 AES-GCM resolves only freshly configured references; wrong key, v1, tamper and changed reference reject", async () => {
  const encrypted = await encryptAISecret("synthetic-provider-secret", key);
  let record = { ...encrypted };
  let ref = encrypted.secret_ref;
  let reads = 0;
  const transport = async (req: Request) => {
    reads++;
    const table = new URL(req.url).pathname.split("/").at(-1);
    if (table === "ai_routes") {
      return json([{
        route_key: "recipe_import_draft_v1",
        primary_model_id: model,
        enabled: true,
        timeout_ms: 10000,
        max_retries: 0,
        max_output_tokens: 1000,
        temperature: null,
      }]);
    }
    if (table === "ai_models") {
      return json([{
        id: model,
        provider_id: provider,
        upstream_model_id: "synthetic",
        enabled: true,
      }]);
    }
    if (table === "ai_providers") {
      return json([{
        id: provider,
        base_url: "https://synthetic.invalid/v1",
        secret_ref: ref,
        enabled: true,
      }]);
    }
    assert.equal(table, "ai_secrets");
    return json([record]);
  };
  const options = {
    enabled: true,
    supabaseRESTBaseURL: new URL("https://synthetic.invalid/rest/v1"),
    serviceRoleKey: "synthetic-service",
    encodedAISecretKey: key,
    postgrestTransport: transport,
  };
  const binding = createRecipeDraftBackendBindings(options);
  const signal = new AbortController().signal;
  assert.equal(
    await binding.workerDependencies.resolveSecret(ref, signal),
    "synthetic-provider-secret",
  );
  assert.equal(reads, 4);
  const wrongKey = btoa(String.fromCharCode(...new Uint8Array(32).fill(38)))
    .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  await assert.rejects(
    createRecipeDraftBackendBindings({
      ...options,
      encodedAISecretKey: wrongKey,
    }).workerDependencies.resolveSecret(ref, signal),
  );
  record = { ...encrypted, key_version: 1 };
  await assert.rejects(binding.workerDependencies.resolveSecret(ref, signal));
  record = {
    ...encrypted,
    ciphertext: (encrypted.ciphertext[0] === "A" ? "B" : "A") +
      encrypted.ciphertext.slice(1),
  };
  await assert.rejects(binding.workerDependencies.resolveSecret(ref, signal));
  ref = "different-configured-reference";
  record = { ...encrypted, secret_ref: ref };
  await assert.rejects(binding.workerDependencies.resolveSecret(ref, signal));
  await assert.rejects(
    binding.workerDependencies.resolveSecret(encrypted.secret_ref, signal),
  );
});
