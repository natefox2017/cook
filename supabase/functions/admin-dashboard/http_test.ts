import { assertEquals } from "jsr:@std/assert@1.0.14";
import { AppError } from "../_shared/errors.ts";
import { handleRequest } from "./handler.ts";

const roles = ["owner", "admin", "operator", "readonly"] as const;

function mockClient() {
  const query = {
    select: () => query,
    order: () => query,
    eq: () => query,
    in: () => query,
    neq: () => query,
    gte: () => query,
    limit: () => query,
    then: (
      resolve: (
        value: { data: unknown[]; count: number; error: null },
      ) => unknown,
      reject?: (reason: unknown) => unknown,
    ) =>
      Promise.resolve({ data: [], count: 0, error: null }).then(
        resolve,
        reject,
      ),
  };

  return { from: () => query } as never;
}

function dependencies() {
  let serviceClientCalls = 0;
  return {
    requireAdminSession: async (request: Request) => {
      const token = request.headers.get("authorization")?.replace(
        /^Bearer\s+/i,
        "",
      );
      if (!token) {
        throw new AppError("unauthorized", "Invalid admin session", 401);
      }
      if (!roles.includes(token as typeof roles[number])) {
        throw new AppError("unauthorized", "Invalid admin session", 401);
      }
      return {
        adminId: "admin-1",
        username: "fixture",
        role: token,
        sessionId: "session-1",
        token,
      };
    },
    createServiceClient: () => {
      serviceClientCalls += 1;
      return mockClient();
    },
    serviceClientCalls: () => serviceClientCalls,
  };
}

Deno.test("local HTTP dashboard role matrix", async () => {
  const fixture = dependencies();
  const server = Deno.serve(
    { hostname: "127.0.0.1", port: 0, onListen() {} },
    (request) => handleRequest(request, fixture),
  );
  const address = server.addr;
  if (address.transport !== "tcp") {
    throw new Error("Expected a local TCP server");
  }
  const url = `http://127.0.0.1:${address.port}/functions/v1/admin-dashboard`;

  try {
    const unauthenticated = await fetch(url);
    assertEquals(unauthenticated.status, 401);

    for (const role of roles) {
      const previousServiceClientCalls = fixture.serviceClientCalls();
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${role}` },
      });
      assertEquals(
        response.status,
        role === "owner" ? 200 : 403,
        `${role} dashboard access`,
      );
      if (role !== "owner") {
        assertEquals(
          fixture.serviceClientCalls(),
          previousServiceClientCalls,
          `${role} must be rejected before service access`,
        );
      }
    }
  } finally {
    await server.shutdown();
  }
});
