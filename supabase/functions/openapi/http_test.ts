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
      served.info?.x_contract_kind === "repository-current-handler-replacement",
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
