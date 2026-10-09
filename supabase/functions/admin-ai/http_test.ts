// Developer: gengyun
// Purpose: Verify admin authorization and safe handling of provider key writes.

import { assertEquals } from "jsr:@std/assert@1.0.14";
import { AppError } from "../_shared/errors.ts";
import { handleRequest } from "./handler.ts";

const roles = ["owner", "admin", "operator", "readonly"] as const;

function dependencies(
  serviceClient: () => unknown = mockClient,
) {
  let serviceClientCalls = 0;
  let probeCalls = 0;
  return {
    requireAdminSession: async (request: Request) => {
      const role = request.headers.get("authorization")?.replace(
        /^Bearer\s+/i,
        "",
      );
      if (!role || !roles.includes(role as typeof roles[number])) {
        throw new AppError("unauthorized", "Invalid admin session", 401);
      }
      return {
        adminId: "admin-1",
        username: "fixture",
        role,
        sessionId: "session-1",
        token: role,
      };
    },
    createServiceClient: () => {
      serviceClientCalls += 1;
      return serviceClient() as never;
    },
    testProvider: async () => {
      probeCalls += 1;
      return true;
    },
    serviceClientCalls: () => serviceClientCalls,
    probeCalls: () => probeCalls,
  };
}

function mockClient() {
  const query = {
    select: () => query,
    order: () => query,
    then: (
      resolve: (value: { data: unknown[]; error: null }) => unknown,
      reject?: (reason: unknown) => unknown,
    ) => Promise.resolve({ data: [], error: null }).then(resolve, reject),
  };
  return { from: () => query };
}

Deno.test("AI endpoints require owner or admin before service access", async () => {
  const fixture = dependencies();
  const base = "http://127.0.0.1/functions/v1/admin-ai";

  const missing = await handleRequest(
    new Request(`${base}/providers`),
    fixture,
  );
  assertEquals(missing.status, 401);
  for (const role of roles) {
    const before = fixture.serviceClientCalls();
    const response = await handleRequest(
      new Request(`${base}/providers`, {
        headers: { Authorization: `Bearer ${role}` },
      }),
      fixture,
    );
    assertEquals(
      response.status,
      role === "owner" || role === "admin" ? 200 : 403,
    );
    assertEquals(
      fixture.serviceClientCalls() - before,
      role === "owner" || role === "admin" ? 1 : 0,
    );
  }
});

Deno.test("provider create fails closed when the v2 key is unconfigured", async () => {
  const fixture = dependencies();
  const response = await handleRequest(
    new Request(
      "http://127.0.0.1/functions/v1/admin-ai/providers",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer owner",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "Example",
          baseUrl: "https://example.com/v1",
          model: "model-x",
          apiKey: "do-not-persist-this",
          active: true,
        }),
      },
    ),
    fixture,
  );

  const body = await response.text();
  assertEquals(response.status, 503);
  assertEquals(body.includes("do-not-persist-this"), false);
  assertEquals(fixture.serviceClientCalls(), 0);
});

Deno.test("provider test never persists or echoes the one-time key", async () => {
  const fixture = dependencies();
  const response = await handleRequest(
    new Request(
      "http://127.0.0.1/functions/v1/admin-ai/providers/test",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer admin",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "Example",
          baseUrl: "https://example.com/v1",
          model: "model-x",
          apiKey: "one-time-secret",
        }),
      },
    ),
    fixture,
  );

  const body = await response.text();
  assertEquals(response.status, 200);
  assertEquals(body.includes("one-time-secret"), false);
  assertEquals(fixture.probeCalls(), 1);
  assertEquals(fixture.serviceClientCalls(), 0);
});

const id = "11111111-1111-4111-8111-111111111111";
Deno.test("provider deletion maps transaction reference rejection to 409", async () => {
  const fixture = dependencies(() => ({
    rpc: async () => ({
      data: null,
      error: { code: "PT409", message: "sensitive internal detail" },
    }),
  }));
  const response = await handleRequest(
    new Request(`http://localhost/admin-ai/providers/${id}`, {
      method: "DELETE",
      headers: { Authorization: "Bearer owner" },
    }),
    fixture,
  );
  assertEquals(response.status, 409);
  assertEquals(
    (await response.text()).includes("sensitive internal detail"),
    false,
  );
});
Deno.test("blank-key edits send no secret envelope to the atomic RPC", async () => {
  let parameters: Record<string, unknown> = {};
  const fixture = dependencies(() => ({
    rpc: async (_name: string, args: Record<string, unknown>) => {
      parameters = args;
      return { data: { active: false, apiKeyConfigured: true }, error: null };
    },
  }));
  const response = await handleRequest(
    new Request(`http://localhost/admin-ai/providers/${id}`, {
      method: "PUT",
      headers: { Authorization: "Bearer owner" },
      body: JSON.stringify({
        name: "Example",
        baseUrl: "https://example.com/v1",
        model: "model-x",
        apiKey: "",
        active: false,
      }),
    }),
    fixture,
  );
  assertEquals(response.status, 200);
  assertEquals(parameters.p_secret, null);
  assertEquals(parameters.p_active, false);
});
Deno.test("saved-key probes ignore caller endpoint, model, and key overrides", async () => {
  const { encryptAISecret } = await import("../_shared/ai-secret.ts");
  const key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
  const oldKey = Deno.env.get("COOKAPP_AI_SECRET_KEY_V2");
  Deno.env.set("COOKAPP_AI_SECRET_KEY_V2", key);
  try {
    const secret = await encryptAISecret("saved-synthetic-key", key);
    const fixture = dependencies(() => ({
      from(table: string) {
        const query = {
          select: () => query,
          eq: () => query,
          order: () => query,
          maybeSingle: async () => ({
            data: table === "ai_secrets" ? secret : {
              id,
              base_url: "https://example.com/v1",
              secret_ref: secret.secret_ref,
            },
            error: null,
          }),
          then: (resolve: (value: unknown) => unknown) =>
            Promise.resolve({
              data: [{
                id,
                provider_id: id,
                upstream_model_id: "saved-model",
                enabled: true,
                created_at: "2026-01-01",
              }],
              error: null,
            }).then(resolve),
        };
        return query;
      },
    }));
    let observed: unknown[] = [];
    fixture.testProvider = async (...args: unknown[]) => {
      observed = args;
      return true;
    };
    const response = await handleRequest(
      new Request("http://localhost/admin-ai/providers/test", {
        method: "POST",
        headers: { Authorization: "Bearer owner" },
        body: JSON.stringify({
          providerId: id,
          baseUrl: "https://attacker.example",
          model: "attacker-model",
          apiKey: "caller-key",
        }),
      }),
      fixture,
    );
    assertEquals(response.status, 200);
    assertEquals(String(observed[0]), "https://example.com/v1");
    assertEquals(observed.slice(1), ["saved-synthetic-key", "saved-model"]);
    assertEquals(
      (await response.text()).includes("saved-synthetic-key"),
      false,
    );
  } finally {
    if (oldKey === undefined) Deno.env.delete("COOKAPP_AI_SECRET_KEY_V2");
    else Deno.env.set("COOKAPP_AI_SECRET_KEY_V2", oldKey);
  }
});
