import { AppError } from "../_shared/errors.ts";
import { withAdminBootstrapAuthorization } from "../_shared/admin-bootstrap.ts";
import { handleCors } from "../_shared/cors.ts";

function request(headers?: HeadersInit): Request {
  return new Request(
    "https://example.test/functions/v1/admin-auth/bootstrap",
    { method: "POST", headers },
  );
}

async function expectAppError(
  operation: () => Promise<unknown>,
  code: string,
  status: number,
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    if (!(error instanceof AppError)) {
      throw new Error("Expected an AppError.");
    }
    if (error.code !== code || error.status !== status) {
      throw new Error(`Unexpected error: ${error.code} / ${error.status}`);
    }
    return;
  }
  throw new Error("Expected the request to be rejected.");
}

Deno.test("production bootstrap rejects a missing server token before its handler", async () => {
  let handlerCalled = false;
  await expectAppError(
    () =>
      withAdminBootstrapAuthorization(
        request(),
        "",
        true,
        async () => {
          handlerCalled = true;
        },
      ),
    "server_misconfigured",
    500,
  );
  if (handlerCalled) {
    throw new Error("The bootstrap handler ran without server configuration.");
  }
});

Deno.test("production bootstrap rejects missing and invalid tokens before its handler", async () => {
  for (const headers of [undefined, { "X-CookApp-Bootstrap-Token": "wrong" }]) {
    let handlerCalled = false;
    await expectAppError(
      () =>
        withAdminBootstrapAuthorization(
          request(headers),
          "expected-secret",
          true,
          async () => {
            handlerCalled = true;
          },
        ),
      "forbidden",
      403,
    );
    if (handlerCalled) {
      throw new Error("The bootstrap handler ran without a valid token.");
    }
  }
});

Deno.test("production bootstrap rejects prefixes, suffixes and oversized headers", async () => {
  for (const token of [
    "prefix-expected-secret",
    "expected-secret-extra",
    "expected-secre",
    "x".repeat(513),
  ]) {
    let handlerCalled = false;
    await expectAppError(
      () =>
        withAdminBootstrapAuthorization(
          request({ "X-CookApp-Bootstrap-Token": token }),
          "expected-secret",
          true,
          async () => {
            handlerCalled = true;
          },
        ),
      "forbidden",
      403,
    );
    if (handlerCalled) {
      throw new Error("A partial or oversized bootstrap token was accepted.");
    }
  }
});

Deno.test("production bootstrap accepts the configured header or bearer token", async () => {
  const acceptedHeaders: HeadersInit[] = [
    { "X-CookApp-Bootstrap-Token": "expected-secret" },
    { Authorization: "Bearer expected-secret" },
  ];
  for (const headers of acceptedHeaders) {
    const response = await withAdminBootstrapAuthorization(
      request(headers),
      "expected-secret",
      true,
      async () => new Response("bootstrap reached"),
    );
    if (await response.text() !== "bootstrap reached") {
      throw new Error("The authorized bootstrap handler did not run.");
    }
  }
});

Deno.test("bootstrap token header is allowed by public CORS preflight", () => {
  const response = handleCors(
    new Request("https://example.test/functions/v1/admin-auth/bootstrap", {
      method: "OPTIONS",
      headers: {
        "Access-Control-Request-Headers": "x-cookapp-bootstrap-token",
      },
    }),
  );
  const allowedHeaders = response?.headers.get("Access-Control-Allow-Headers")
    ?.toLowerCase() ?? "";

  if (
    !allowedHeaders.split(",").map((header) => header.trim()).includes(
      "x-cookapp-bootstrap-token",
    )
  ) {
    throw new Error(
      "CORS preflight does not allow the bootstrap token header.",
    );
  }
});

Deno.test("non-production bootstrap keeps the existing no-token behavior", async () => {
  const response = await withAdminBootstrapAuthorization(
    request(),
    "",
    false,
    async () => new Response("bootstrap reached"),
  );
  if (await response.text() !== "bootstrap reached") {
    throw new Error("The non-production bootstrap handler did not run.");
  }
});
