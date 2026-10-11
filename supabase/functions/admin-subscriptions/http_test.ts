import { assertEquals } from "jsr:@std/assert@1.0.14";
import { AppError } from "../_shared/errors.ts";
import { handleRequest } from "./handler.ts";

const roles = ["owner", "admin", "operator", "readonly"] as const;

function mockClient() {
  let deleting = false;
  const query = {
    select: () => query,
    order: () => query,
    eq: () => query,
    in: () => query,
    neq: () => query,
    limit: () => query,
    insert: () => query,
    update: () => query,
    delete: () => {
      deleting = true;
      return query;
    },
    single: async () => ({ data: { id: "plan-1" }, error: null }),
    maybeSingle: async () => ({ data: { id: "plan-1" }, error: null }),
    then: (
      resolve: (
        value: { data: unknown[]; count: number; error: null },
      ) => unknown,
      reject?: (reason: unknown) => unknown,
    ) =>
      Promise.resolve({ data: [], count: deleting ? 1 : 0, error: null }).then(
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
    await unauthenticated.body?.cancel();

    for (const role of roles) {
      const response = await fetch(`${baseURL}/plans`, {
        headers: { Authorization: `Bearer ${role}` },
      });
      assertEquals(
        response.status,
        200,
        `${role} should read the plan catalog`,
      );
      await response.body?.cancel();
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
            currency: "USD",
            active: true,
          }),
        });
        assertEquals(
          response.status,
          role === "owner" || role === "admin"
            ? (method === "POST" ? 201 : 200)
            : 403,
          `${role} ${method} plan authorization`,
        );
        await response.body?.cancel();
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
        if (resource === "revenue" && response.status === 200) {
          const report = await response.json();
          assertEquals(report.stats.mrr, null);
        } else {
          await response.body?.cancel();
        }
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

// Exercise the real report handler with synthetic PostgREST row/count responses.
function reportFixture(
  table: string,
  result: Record<string, unknown>,
  subscriptionRows?: Record<string, unknown>[],
) {
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
            name === table
              ? result
              : name === "subscriptions" && subscriptionRows
              ? {
                data: subscriptionRows,
                count: subscriptionRows.length,
                error: null,
              }
              : { data: [], count: 0, error: null },
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

Deno.test("admin-subscriptions refuses unverified purchase report completeness", async () => {
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
        "https://example.test/functions/v1/admin-subscriptions/revenue",
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

Deno.test("admin-subscriptions preserves complete purchase reports and query failures", async () => {
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
        "https://example.test/functions/v1/admin-subscriptions/revenue",
        { headers: { Authorization: "Bearer owner" } },
      ),
      fixture.dependencies,
    );
    assertEquals(response.status, status);
    if (status === 200) {
      const body = await response.json();
      assertEquals(body.stats.mrr, null);
    }
  }
});

Deno.test("subscription records detect a lower server row limit", async () => {
  const fixture = reportFixture("subscriptions", {
    data: Array.from({ length: 100 }, () => ({ user_id: "fixture-user" })),
    count: 600,
    error: null,
  });
  const response = await handleRequest(
    new Request(
      "https://example.test/functions/v1/admin-subscriptions/records",
      { headers: { Authorization: "Bearer owner" } },
    ),
    fixture.dependencies,
  );
  assertEquals(response.status, 503);
  assertEquals(
    fixture.selections.find((item) => item.table === "subscriptions")?.options
      ?.count,
    "exact",
  );
});

Deno.test("subscription purchase enrichment detects a lower server row limit", async () => {
  const fixture = reportFixture("purchase_events", {
    data: purchaseRows.slice(0, 100),
    count: 2100,
    error: null,
  }, [{ user_id: "fixture-user", product_id: "monthly" }]);
  const response = await handleRequest(
    new Request(
      "https://example.test/functions/v1/admin-subscriptions/records",
      { headers: { Authorization: "Bearer owner" } },
    ),
    fixture.dependencies,
  );
  assertEquals(response.status, 503);
  assertEquals(
    fixture.selections.find((item) => item.table === "purchase_events")?.options
      ?.count,
    "exact",
  );
});

Deno.test("admin-subscriptions complete mixed-currency history retains year buckets", async () => {
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
      "https://example.test/functions/v1/admin-subscriptions/revenue",
      { headers: { Authorization: "Bearer owner" } },
    ),
    fixture.dependencies,
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.stats.currency, null);
  assertEquals(body.series.map((row: { month: string }) => row.month), [
    "2025-01",
    "2026-01",
  ]);
});

Deno.test("subscription records and enrichment validate counts and query errors", async () => {
  const rows = [purchaseRows[0]];
  const results = [
    { result: { data: rows, count: 1, error: null }, status: 200 },
    { result: { data: rows, error: null }, status: 503 },
    { result: { data: rows, count: null, error: null }, status: 503 },
    { result: { data: rows, count: -1, error: null }, status: 503 },
    { result: { data: rows, count: "1", error: null }, status: 503 },
    { result: { data: rows, count: 0.5, error: null }, status: 503 },
    {
      result: { data: rows, count: Number.MAX_SAFE_INTEGER + 1, error: null },
      status: 503,
    },
    { result: { data: rows, count: 0, error: null }, status: 503 },
    { result: { data: null, count: 0, error: null }, status: 503 },
    { result: { data: {}, count: 0, error: null }, status: 503 },
    {
      result: {
        data: null,
        count: null,
        error: { message: "synthetic failure" },
      },
      status: 500,
    },
  ];
  for (const table of ["subscriptions", "purchase_events"]) {
    for (const { result, status } of results) {
      const fixture = reportFixture(
        table,
        result,
        table === "purchase_events" ? rows : undefined,
      );
      const response = await handleRequest(
        new Request(
          "https://example.test/functions/v1/admin-subscriptions/records",
          { headers: { Authorization: "Bearer owner" } },
        ),
        fixture.dependencies,
      );
      assertEquals(
        response.status,
        status,
        `${table} ${JSON.stringify(result.count)}`,
      );
      assertEquals(
        fixture.selections.find((item) => item.table === table)?.options?.count,
        "exact",
      );
      if (status === 200) {
        const records = await response.json();
        assertEquals(records.length, 1);
        assertEquals(records[0].user.id, "fixture-user");
      }
    }
  }
});

Deno.test("invalid and oversized plan bodies never reach a database mutation", async () => {
  for (const [body, expected] of [["[]", 400], ["{}", 400], ["x".repeat(16 * 1024 + 1), 413]] as const) {
    let writes = 0;
    const fixture = dependencies();
    const response = await handleRequest(new Request("https://example.test/functions/v1/admin-subscriptions/plans", {
      method:"POST", headers:{Authorization:"Bearer owner"}, body,
    }), {...fixture, createServiceClient: () => ({from(){writes++;throw new Error("unexpected write");}}) as never});
    assertEquals(response.status, expected);
    assertEquals(writes, 0);
    await response.body?.cancel();
  }
});
