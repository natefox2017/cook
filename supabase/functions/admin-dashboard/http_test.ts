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
      if (role === "owner") {
        const dashboard = await response.json();
        assertEquals(dashboard.stats.revenueMrr, null);
      }
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

// Exercise the real report handler with synthetic PostgREST row/count responses.
function reportFixture(table: string, result: Record<string, unknown>) {
  const selections: { table: string; options?: { count?: string } }[] = [];
  const client = {
    from(name: string) {
      const query = {
        select: (_columns: string, options?: { count?: string }) => {
          selections.push({ table: name, options });
          return query;
        },
        order: () => query,
        eq: () => query,
        in: () => query,
        neq: () => query,
        gte: () => query,
        limit: () => query,
        then: (
          resolve: (value: unknown) => unknown,
          reject?: (reason: unknown) => unknown,
        ) =>
          Promise.resolve(
            name === table ? result : { data: [], count: 0, error: null },
          )
            .then(resolve, reject),
      };
      return query;
    },
  };
  return {
    selections,
    dependencies: {
      ...dependencies(),
      createServiceClient: () => client as never,
    },
  };
}

const purchaseRows = Array.from({ length: 1000 }, () => ({
  user_id: "fixture-user",
  product_id: "monthly",
  store: "app_store",
  event_type: "INITIAL_PURCHASE",
  created_at: "2026-01-01T00:00:00Z",
  raw_event: { price: 1, currency: "USD" },
}));

Deno.test("admin-dashboard refuses unverified purchase report completeness", async () => {
  for (
    const result of [
      { data: purchaseRows, count: 6000, error: null },
      { data: [], count: null, error: null },
      { data: [], error: null },
      { data: {}, count: 0, error: null },
      { data: [], count: -1, error: null },
      { data: [], count: 0.5, error: null },
      { data: [], count: Number.MAX_SAFE_INTEGER + 1, error: null },
      { data: purchaseRows, count: 0, error: null },
      { data: null, count: 0, error: null },
    ]
  ) {
    const fixture = reportFixture("purchase_events", result);
    const response = await handleRequest(
      new Request(
        "https://example.test/functions/v1/admin-dashboard",
        { headers: { Authorization: "Bearer owner" } },
      ),
      fixture.dependencies,
    );
    assertEquals(response.status, 503, JSON.stringify(result.count));
    assertEquals(
      fixture.selections.find((item) => item.table === "purchase_events")
        ?.options?.count,
      "exact",
    );
  }
});

Deno.test("admin-dashboard preserves complete purchase reports and query failures", async () => {
  for (
    const [result, status] of [
      [{ data: [], count: 0, error: null }, 200],
      [{ data: purchaseRows, count: 1000, error: null }, 200],
      [
        { data: null, count: null, error: { message: "synthetic failure" } },
        500,
      ],
    ] as const
  ) {
    const fixture = reportFixture("purchase_events", result);
    const response = await handleRequest(
      new Request(
        "https://example.test/functions/v1/admin-dashboard",
        { headers: { Authorization: "Bearer owner" } },
      ),
      fixture.dependencies,
    );
    assertEquals(response.status, status);
    if (status === 200) {
      const body = await response.json();
      assertEquals(body.stats.revenueMrr, null);
    }
  }
});

Deno.test("admin-dashboard complete mixed-currency history retains year buckets", async () => {
  const data = [
    { ...purchaseRows[0], created_at: "2025-01-01T00:00:00Z" },
    {
      ...purchaseRows[0],
      created_at: "2026-01-01T00:00:00Z",
      raw_event: {
        price: 8,
        price_in_purchased_currency: 1200,
        currency: "JPY",
      },
    },
  ];
  const fixture = reportFixture("purchase_events", {
    data,
    count: 2,
    error: null,
  });
  const response = await handleRequest(
    new Request(
      "https://example.test/functions/v1/admin-dashboard",
      { headers: { Authorization: "Bearer owner" } },
    ),
    fixture.dependencies,
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.stats.revenueCurrency, null);
  assertEquals(body.series.map((row: { month: string }) => row.month), [
    "2025-01",
    "2026-01",
  ]);
});
