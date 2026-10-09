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
    limit: () => query,
    insert: () => query,
    update: () => query,
    delete: () => query,
    single: async () => ({ data: { id: "plan-1" }, error: null }),
    maybeSingle: async () => ({ data: { id: "plan-1" }, error: null }),
    then: (
      resolve: (
        value: { data: unknown[]; count: number; error: null },
      ) => unknown,
      reject?: (reason: unknown) => unknown,
    ) =>
      Promise.resolve({ data: [], count: 1, error: null }).then(
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

async function startLocalServer() {
  const fixture = dependencies();
  const server = Deno.serve(
    { hostname: "127.0.0.1", port: 0, onListen() {} },
    (request) => handleRequest(request, fixture),
  );
  const address = server.addr;
  if (address.transport !== "tcp") {
    throw new Error("Expected a local TCP server");
  }
  return {
    server,
    fixture,
    baseURL:
      `http://127.0.0.1:${address.port}/functions/v1/admin-subscriptions`,
  };
}

Deno.test("local HTTP subscription role matrix", async () => {
  const { server, fixture, baseURL } = await startLocalServer();
  try {
    const unauthenticated = await fetch(`${baseURL}/plans`);
    assertEquals(unauthenticated.status, 401);

    for (const role of roles) {
      const response = await fetch(`${baseURL}/plans`, {
        headers: { Authorization: `Bearer ${role}` },
      });
      assertEquals(
        response.status,
        200,
        `${role} should read the plan catalog`,
      );
    }

    for (const role of roles) {
      for (const method of ["POST", "PUT", "DELETE"] as const) {
        const previousServiceClientCalls = fixture.serviceClientCalls();
        const planPath = method === "POST" ? "/plans" : "/plans/plan-1";
        const response = await fetch(`${baseURL}${planPath}`, {
          method,
          headers: {
            Authorization: `Bearer ${role}`,
            "Content-Type": "application/json",
          },
          body: method === "DELETE" ? undefined : JSON.stringify({
            planKey: "monthly",
            displayName: "Monthly",
            platform: "app_store",
            productId: "recipe.pro.monthly",
            billingPeriod: "monthly",
            price: 4.99,
          }),
        });
        assertEquals(
          response.status,
          role === "owner" || role === "admin"
            ? (method === "POST" ? 201 : 200)
            : 403,
          `${role} ${method} plan authorization`,
        );
        if (role === "operator" || role === "readonly") {
          assertEquals(
            fixture.serviceClientCalls(),
            previousServiceClientCalls,
            `${role} ${method} must be rejected before service access`,
          );
        }
      }
    }

    for (const resource of ["records", "revenue"]) {
      for (const role of roles) {
        const previousServiceClientCalls = fixture.serviceClientCalls();
        const response = await fetch(`${baseURL}/${resource}`, {
          headers: { Authorization: `Bearer ${role}` },
        });
        assertEquals(
          response.status,
          role === "owner" || role === "admin" ? 200 : 403,
          `${role} GET ${resource} authorization`,
        );
        if (role === "operator" || role === "readonly") {
          assertEquals(
            fixture.serviceClientCalls(),
            previousServiceClientCalls,
            `${role} GET ${resource} must be rejected before service access`,
          );
        }
      }
    }
  } finally {
    await server.shutdown();
  }
});
