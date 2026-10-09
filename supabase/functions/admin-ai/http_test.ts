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

Deno.test("provider create refuses to persist plaintext or unknown-format keys", async () => {
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

Deno.test("provider deletion preserves usage-event attribution", async () => {
  let deleteCalled = false;
  const serviceClient = () => ({
    from(table: string) {
      const query = {
        select: () => query,
        eq: () => query,
        maybeSingle: async () => ({
          data: { id: "provider-1", secret_ref: null },
          error: null,
        }),
        delete: () => {
          deleteCalled = true;
          return query;
        },
        then: (
          resolve: (value: { count: number; error: null }) => unknown,
          reject?: (reason: unknown) => unknown,
        ) =>
          Promise.resolve({
            count: table === "ai_usage_events" ? 1 : 0,
            error: null,
          }).then(resolve, reject),
      };
      return query;
    },
  });
  const fixture = dependencies(serviceClient);
  const response = await handleRequest(
    new Request(
      "http://127.0.0.1/functions/v1/admin-ai/providers/provider-1",
      { method: "DELETE", headers: { Authorization: "Bearer owner" } },
    ),
    fixture,
  );

  assertEquals(response.status, 409);
  assertEquals(deleteCalled, false);
});
