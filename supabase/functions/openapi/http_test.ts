// Developer: gengyun
// Purpose: Verify the bundled OpenAPI document through local HTTP only.

import spec from "./openapi.json" with { type: "json" };
import { handleRequest } from "./handler.ts";

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function resolvePointer(pointer: string): unknown {
  if (!pointer.startsWith("#/")) {
    throw new Error(`Non-local OpenAPI reference: ${pointer}`);
  }

  return pointer.slice(2).split("/").reduce<unknown>((value, part) => {
    const key = part.replace(/~1/g, "/").replace(/~0/g, "~");
    if (!value || typeof value !== "object" || !(key in value)) {
      throw new Error(`Unresolved OpenAPI reference: ${pointer}`);
    }
    return (value as Record<string, unknown>)[key];
  }, spec);
}

function validateLocalReferences(value: unknown): void {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    value.forEach(validateLocalReferences);
    return;
  }

  const object = value as Record<string, unknown>;
  if (typeof object.$ref === "string") {
    expect(
      resolvePointer(object.$ref) !== undefined,
      `Unresolved ${object.$ref}`,
    );
  }
  Object.values(object).forEach(validateLocalReferences);
}

function operationMap(
  document: Record<string, unknown>,
): Record<string, string[]> {
  const paths = document.paths as Record<string, Record<string, unknown>>;
  return Object.fromEntries(
    Object.entries(paths).map(([path, pathItem]) => [
      path,
      Object.keys(pathItem).filter((method) =>
        ["get", "post", "put", "patch", "delete"].includes(method)
      ).sort(),
    ]),
  );
}

Deno.test("OpenAPI GET serves the bundled contract over loopback", async () => {
  const server = Deno.serve(
    { hostname: "127.0.0.1", port: 0, onListen: () => {} },
    handleRequest,
  );

  try {
    const url = `http://127.0.0.1:${server.addr.port}/functions/v1/openapi`;
    const response = await fetch(url, {
      headers: { Origin: "https://docs.example" },
    });
    expect(response.status === 200, "Expected OpenAPI GET to return 200");
    expect(
      response.headers.get("content-type")?.includes("application/json"),
      "Expected application/json content type",
    );
    expect(
      response.headers.get("access-control-allow-origin") === "*",
      "Expected public CORS origin",
    );
    expect(
      response.headers.get("cache-control") === "public, max-age=300",
      "Expected bounded public cache policy",
    );

    const served = await response.json();
    expect(
      JSON.stringify(served) === JSON.stringify(spec),
      "Served document differs from bundled JSON",
    );
    expect(
      served.info?.x_contract_kind ===
        "repository-current-handler-and-frozen-admin-ai-contract",
      "Missing replacement metadata",
    );
    validateLocalReferences(served);
  } finally {
    await server.shutdown();
  }
});

Deno.test("OpenAPI endpoint handles CORS preflight and rejects other methods", async () => {
  const server = Deno.serve(
    { hostname: "127.0.0.1", port: 0, onListen: () => {} },
    handleRequest,
  );

  try {
    const url = `http://127.0.0.1:${server.addr.port}/functions/v1/openapi`;
    const preflight = await fetch(url, {
      method: "OPTIONS",
      headers: {
        Origin: "https://docs.example",
        "Access-Control-Request-Method": "GET",
      },
    });
    expect(preflight.status === 200, "Expected CORS preflight response");
    expect(
      preflight.headers.get("access-control-allow-origin") === "*",
      "Expected wildcard CORS on preflight",
    );
    expect(
      preflight.headers.get("access-control-allow-methods")?.includes("GET"),
      "Expected GET in CORS methods",
    );

    const rejected = await fetch(url, { method: "POST" });
    expect(rejected.status === 405, "Expected POST to return 405");
    expect(
      rejected.headers.get("access-control-allow-origin") === "*",
      "Expected CORS headers on method errors",
    );
  } finally {
    await server.shutdown();
  }
});

Deno.test("OpenAPI documents the frozen implemented route set", () => {
  const expected: Record<string, string[]> = {
    "/openapi": ["get"],
    "/health": ["get"],
    "/delete-account": ["post"],
    "/recipe-imports": ["post"],
    "/recipe-imports/{job_id}": ["get"],
    "/recipe-imports/{job_id}/retry": ["post"],
    "/recipe-import-artifacts": ["post"],
    "/recipe-import-artifacts/{artifact_id}": ["delete"],
    "/recipe-import-artifacts/{artifact_id}/complete": ["post"],
    "/recipe-import-artifacts/{artifact_id}/download": ["get"],
    "/recipe-import-worker": ["post"],
    "/purge-expired-recipe-import-artifacts": ["post"],
    "/admin-ai/providers": ["get", "post"],
    "/admin-ai/providers/test": ["post"],
    "/admin-ai/providers/{id}": ["delete", "put"],
    "/admin-ai/usage": ["get"],
    "/admin-auth/bootstrap-status": ["get"],
    "/admin-auth/login": ["post"],
    "/admin-auth/login-totp": ["post"],
    "/admin-auth/login-passkey-options": ["post"],
    "/admin-auth/login-passkey-verify": ["post"],
    "/admin-auth/bootstrap": ["post"],
    "/admin-auth/logout": ["post"],
    "/admin-auth/session": ["get"],
    "/admin-auth/change-password": ["post"],
    "/admin-auth/factors": ["get"],
    "/admin-auth/login-events": ["get"],
    "/admin-auth/totp-setup": ["post"],
    "/admin-auth/totp-verify": ["post"],
    "/admin-auth/totp-remove": ["post"],
    "/admin-auth/passkey-registration-options": ["post"],
    "/admin-auth/passkey-registration-verify": ["post"],
    "/admin-auth/passkey-remove": ["post"],
    "/admin-users": ["get"],
    "/admin-users/{user_id}": ["get"],
    "/admin-dashboard": ["get"],
    "/admin-subscriptions/plans": ["get", "post"],
    "/admin-subscriptions/plans/{id}": ["delete", "put"],
    "/admin-subscriptions/records": ["get"],
    "/admin-subscriptions/revenue": ["get"],
    "/revenuecat-webhook": ["post"],
  };

  const actualEntries = Object.entries(operationMap(spec)).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  const expectedEntries = Object.entries(expected).sort(([a], [b]) =>
    a.localeCompare(b)
  );
  expect(
    JSON.stringify(actualEntries) === JSON.stringify(expectedEntries),
    "OpenAPI methods or paths do not match the reviewed route inventory",
  );
});

Deno.test("Admin AI contract freezes roles, types, and unsupported outcomes", () => {
  const document = spec as unknown as {
    paths: Record<string, Record<string, Record<string, unknown>>>;
    components: { schemas: Record<string, Record<string, unknown>> };
  };
  const operations = [
    ["/admin-ai/providers", "get"],
    ["/admin-ai/providers", "post"],
    ["/admin-ai/providers/{id}", "put"],
    ["/admin-ai/providers/{id}", "delete"],
    ["/admin-ai/providers/test", "post"],
    ["/admin-ai/usage", "get"],
  ] as const;

  for (const [path, method] of operations) {
    const operation = document.paths[path][method];
    expect(
      JSON.stringify(operation.security) ===
        JSON.stringify([{ AdminSessionBearer: [] }]),
      `${method.toUpperCase()} ${path} requires a custom admin session`,
    );
    expect(
      JSON.stringify(operation["x-required-admin-roles"]) ===
        JSON.stringify(["owner", "admin"]),
      `${method.toUpperCase()} ${path} is owner/admin only`,
    );
    const responses = operation.responses as Record<string, unknown>;
    expect(responses["401"] !== undefined, `${method} ${path} documents 401`);
    expect(responses["403"] !== undefined, `${method} ${path} documents 403`);
  }

  const schemas = document.components.schemas;
  const providerInput = schemas.LLMProviderInput;
  const providerProperties = providerInput.properties as Record<
    string,
    Record<string, unknown>
  >;
  expect(
    JSON.stringify(Object.keys(providerProperties).sort()) ===
      JSON.stringify(["active", "apiKey", "baseUrl", "model", "name"]),
    "Provider input fields match LLMProviderInput",
  );
  expect(
    providerProperties.apiKey.writeOnly === true,
    "Provider keys are write-only",
  );
  expect(
    !("apiKey" in (schemas.LLMProvider.properties as Record<string, unknown>)),
    "Provider responses never expose key material",
  );
  const providerResponseProperties = schemas.LLMProvider.properties as Record<
    string,
    unknown
  >;
  expect(
    JSON.stringify(Object.keys(providerResponseProperties).sort()) ===
      JSON.stringify([
        "active",
        "apiKeyConfigured",
        "baseUrl",
        "id",
        "model",
        "name",
        "updatedAt",
      ]),
    "Provider response fields match LLMProvider",
  );

  const testInput = schemas.AdminAiProviderTestInput;
  const testInputProperties = testInput.properties as Record<
    string,
    Record<string, unknown>
  >;
  expect(
    JSON.stringify(Object.keys(testInputProperties).sort()) ===
      JSON.stringify(["apiKey", "baseUrl", "model", "name", "providerId"]),
    "Connection-test request fields match admin/src/api.ts",
  );
  expect(
    JSON.stringify(testInput.required) ===
      JSON.stringify(["name", "baseUrl", "model"]),
    "Connection-test key and provider id remain optional",
  );

  const usage = schemas.LLMUsage;
  const usageProperties = usage.properties as Record<
    string,
    Record<string, unknown>
  >;
  const totals = usageProperties.totals;
  const totalProperties = totals.properties as Record<string, unknown>;
  expect(
    JSON.stringify(Object.keys(totalProperties).sort()) ===
      JSON.stringify([
        "averageLatencyMs",
        "cachedInputTokens",
        "inputTokens",
        "outputTokens",
        "requests",
        "totalTokens",
      ]),
    "Usage totals match LLMUsage",
  );
  expect(
    !((totals.required as string[]).includes("cachedInputTokens")),
    "Cached input tokens remain optional when the live schema has no column",
  );
  const usageSeries = usageProperties.series.items as Record<
    string,
    unknown
  >;
  expect(
    JSON.stringify(
      Object.keys(usageSeries.properties as Record<string, unknown>).sort(),
    ) ===
      JSON.stringify([
        "date",
        "inputTokens",
        "outputTokens",
        "requests",
        "totalTokens",
      ]),
    "Usage series fields match LLMUsage",
  );
  const usageByModel = usageProperties.byModel.items as Record<
    string,
    unknown
  >;
  expect(
    JSON.stringify(
      Object.keys(usageByModel.properties as Record<string, unknown>).sort(),
    ) ===
      JSON.stringify(["model", "provider", "requests", "totalTokens"]),
    "Usage model aggregates match LLMUsage",
  );
  const range = (document.paths["/admin-ai/usage"].get.parameters as Array<{
    name: string;
    schema: { enum: string[]; default: string };
  }>).find((parameter) => parameter.name === "range");
  expect(
    JSON.stringify(range?.schema.enum) ===
        JSON.stringify(["7d", "30d", "90d"]) &&
      range?.schema.default === "7d",
    "Usage range matches the current API type",
  );

  const createResponses = document.paths["/admin-ai/providers"].post
    .responses as Record<string, unknown>;
  const updateResponses = document.paths["/admin-ai/providers/{id}"].put
    .responses as Record<string, unknown>;
  const deleteResponses = document.paths["/admin-ai/providers/{id}"].delete
    .responses as Record<string, unknown>;
  const testResponses = document.paths["/admin-ai/providers/test"].post
    .responses as Record<string, unknown>;
  expect(
    createResponses["200"] !== undefined,
    "Provider creation success is documented",
  );
  expect(
    createResponses["400"] !== undefined,
    "Missing provider key is a validation error",
  );
  expect(
    createResponses["409"] !== undefined,
    "Provider creation conflict is explicit",
  );
  expect(
    createResponses["503"] !== undefined,
    "Unavailable v2 key configuration is explicit",
  );
  expect(
    updateResponses["409"] !== undefined,
    "Model mapping conflict is explicit",
  );
  expect(
    updateResponses["503"] !== undefined,
    "Unavailable v2 key configuration is explicit",
  );
  expect(
    deleteResponses["200"] !== undefined,
    "Unreferenced provider deletion succeeds",
  );
  expect(
    deleteResponses["409"] !== undefined,
    "Referenced provider deletion conflict is explicit",
  );
  expect(
    deleteResponses["404"] !== undefined,
    "Unknown provider deletion is explicit",
  );
  expect(
    testResponses["404"] !== undefined,
    "Unknown saved provider test is explicit",
  );
  expect(
    testResponses["409"] !== undefined,
    "Saved provider without key/model is explicit",
  );
  expect(
    testResponses["503"] !== undefined,
    "Unavailable v2 key configuration is explicit for saved-key tests",
  );

  const deleteResponse = schemas.AdminAiProviderDeleteResponse;
  expect(
    (deleteResponse.properties as Record<string, Record<string, unknown>>)
      .ok.const === true,
    "Delete success response matches admin/src/api.ts",
  );
});
