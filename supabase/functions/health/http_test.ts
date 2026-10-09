import { AppError } from "../_shared/errors.ts";
import { createHealthHandler } from "./handler.ts";

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("health endpoint returns authenticated statuses over local HTTP", async () => {
  const authServer = Deno.serve(
    {
      hostname: "127.0.0.1",
      port: 0,
      onListen: () => {},
    },
    (request) => {
      if (request.headers.get("Authorization") !== "Bearer valid-fixture") {
        return Response.json({ message: "Invalid JWT" }, { status: 401 });
      }
      return Response.json({
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        aud: "authenticated",
        role: "authenticated",
        app_metadata: {},
        user_metadata: {},
        created_at: "2026-01-01T00:00:00Z",
      });
    },
  );

  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  Deno.env.set("SUPABASE_URL", `http://127.0.0.1:${authServer.addr.port}`);
  Deno.env.set("SUPABASE_ANON_KEY", "synthetic-publishable-key");

  const healthServer = Deno.serve(
    {
      hostname: "127.0.0.1",
      port: 0,
      onListen: () => {},
    },
    createHealthHandler(),
  );

  try {
    const url = `http://127.0.0.1:${healthServer.addr.port}/functions/v1/health`;
    const unauthenticated = await fetch(url);
    expect(unauthenticated.status === 401, "Expected missing bearer to return 401");

    const rejected = await fetch(url, {
      headers: { Authorization: "Bearer invalid-fixture" },
    });
    expect(rejected.status === 401, "Expected rejected Auth user to return 401");

    const authenticated = await fetch(url, {
      headers: { Authorization: "Bearer valid-fixture" },
    });
    expect(authenticated.status === 200, "Expected valid Auth user to return 200");
    const body = await authenticated.json();
    expect(body.ok === true, "Health response is missing ok=true");
    expect(
      body.openapi === "/functions/v1/openapi",
      "Health response has an unexpected OpenAPI link",
    );
  } finally {
    await healthServer.shutdown();
    await authServer.shutdown();
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousAnonKey === undefined) Deno.env.delete("SUPABASE_ANON_KEY");
    else Deno.env.set("SUPABASE_ANON_KEY", previousAnonKey);
  }
});

Deno.test("health error boundary maps a forbidden auth error over local HTTP", async () => {
  const server = Deno.serve(
    {
      hostname: "127.0.0.1",
      port: 0,
      onListen: () => {},
    },
    createHealthHandler(async () => {
      throw new AppError("forbidden", "Forbidden fixture", 403);
    }),
  );

  try {
    const response = await fetch(
      `http://127.0.0.1:${server.addr.port}/functions/v1/health`,
      { headers: { Authorization: "Bearer forbidden-fixture" } },
    );
    expect(response.status === 403, "Expected forbidden auth error to return 403");
  } finally {
    await server.shutdown();
  }
});
