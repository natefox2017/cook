// Developer: gengyun
// Purpose: Exercise actual Deno handlers and Supabase Auth/REST clients with offline synthetic HTTP responses.
// Intercept only server registration while importing the unchanged Edge entrypoints.
// Production keeps its unconditional Deno.serve registration.
const serve = Deno.serve;
const registrations: unknown[] = [];
Deno.serve = ((handler: unknown) => {
  registrations.push(handler);
  return {};
}) as typeof Deno.serve;
let manage: typeof import("../index.ts").handleRecipeShareManage;
let guest:
  typeof import("../../recipe-share-public/index.ts").handlePublicShare;
try {
  ({ handleRecipeShareManage: manage } = await import("../index.ts"));
  ({ handlePublicShare: guest } = await import(
    "../../recipe-share-public/index.ts"
  ));
} finally {
  Deno.serve = serve;
}

const owner = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
const shareID = "33333333-3333-4333-8333-333333333333";
const key = "44444444-4444-4444-8444-444444444444";
const snapshot = {
  title: "Synthetic soup",
  summary: "Approved",
  sourceURL: null,
  servings: 2,
  prepMinutes: 5,
  cookMinutes: 10,
  ingredients: [{ name: "Salt", amountText: "to taste" }],
  steps: [{ title: "Mix", instruction: "Stir." }],
};
const payload = {
  idempotencyKey: key,
  sourceRecipeID: key,
  sourceRecipeUpdatedAt: "2026-10-10T11:00:00Z",
  scope: "fullInstructions",
  hasDistributionRights: true,
  snapshot,
};
type Row = Record<string, unknown>;
let row: Row | null;
let calls: string[];
let quota: boolean;
let databaseError: boolean;

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
}
function json(data: unknown, status = 200) {
  return Response.json(data, { status });
}

// No socket permission is granted. Every SDK request must terminate here;
// an unexpected target fails instead of falling through to a live service.
async function syntheticFetch(input: RequestInfo | URL, init?: RequestInit) {
  const request = new Request(input, init);
  const url = new URL(request.url);
  assert(url.origin === "https://fixture.invalid", "unexpected SDK target");
  calls.push(request.method + " " + url.pathname);
  if (url.pathname === "/auth/v1/user") {
    const token = request.headers.get("authorization");
    if (
      !["Bearer owner-a", "Bearer owner-b", "Bearer anonymous"].includes(
        token ?? "",
      )
    ) {
      return json({ message: "Invalid synthetic token" }, 401);
    }
    return json({
      id: token === "Bearer owner-b" ? other : owner,
      aud: "authenticated",
      role: "authenticated",
      app_metadata: {},
      user_metadata: {},
      created_at: "2026-10-10T00:00:00Z",
      is_anonymous: token === "Bearer anonymous",
    });
  }
  assert(request.headers.get("apikey") === "synthetic-service-key");
  if (databaseError) {
    return json({ code: "FIXTURE_ERROR", message: "PRIVATE_MARKER" }, 500);
  }
  if (url.pathname === "/rest/v1/rpc/create_recipe_share_once") {
    const args = await request.json();
    if (
      row && row.owner_id === args.p_owner_id &&
      row.idempotency_key === args.p_payload.idempotencyKey
    ) {
      return json(
        row.revoked_at || row.request_hash !== args.p_request_hash
          ? { status: 409 }
          : { status: 200, share: row },
      );
    }
    if (quota) return json({ status: 429 });
    row = {
      share_id: shareID,
      owner_id: args.p_owner_id,
      opaque_slug: args.p_slug,
      share_version: 1,
      scope: args.p_payload.scope,
      has_distribution_rights: args.p_payload.hasDistributionRights,
      sanitized_snapshot: args.p_payload.snapshot,
      idempotency_key: args.p_payload.idempotencyKey,
      request_hash: args.p_request_hash,
      revoked_at: null,
      created_at: "2026-10-10T11:00:00Z",
      updated_at: "2026-10-10T11:00:00Z",
    };
    return json({ status: 201, share: row });
  }
  assert(url.pathname === "/rest/v1/recipe_shared_snapshots");
  const filters = [...url.searchParams].filter(([name]) =>
    !["select", "order", "limit"].includes(name)
  );
  const matched = row && filters.every(([name, expression]) => {
    if (expression === "is.null") return row![name] === null;
    assert(expression.startsWith("eq."));
    return String(row![name]) === expression.slice(3);
  });
  if (request.method === "PATCH" && matched) {
    Object.assign(row!, await request.json());
  } else assert(request.method === "GET" || request.method === "PATCH");
  const selected = matched
    ? Object.fromEntries(
      url.searchParams.get("select")!.split(",").map((
        name,
      ) => [name, row![name]]),
    )
    : null;
  // maybeSingle GET asks for JSON arrays; PATCH asks for PostgREST object JSON.
  if (request.headers.get("accept")?.includes("vnd.pgrst.object")) {
    return selected
      ? json(selected)
      : json({ code: "PGRST116", details: "The result contains 0 rows" }, 406);
  }
  return json(selected ? [selected] : []);
}

function request(
  method: string,
  id = "",
  body: unknown = payload,
  token = "owner-a",
  version?: string,
) {
  return new Request(
    "https://edge.invalid/functions/v1/recipe-share-manage" +
      (id ? "/" + id : ""),
    {
      method,
      headers: {
        authorization: "Bearer " + token,
        "content-type": "application/json",
        ...(version ? { "if-match": version } : {}),
      },
      ...(["POST", "PUT"].includes(method)
        ? { body: JSON.stringify(body) }
        : {}),
    },
  );
}
function visitor(method = "GET", slug = String(row?.opaque_slug)) {
  return new Request(
    "https://edge.invalid/functions/v1/recipe-share-public/" + slug,
    { method },
  );
}
async function status(response: Promise<Response>, expected: number) {
  const result = await response;
  equal(result.status, expected);
  assert(result.headers.get("cache-control")?.includes("no-store"));
  assert(result.headers.get("x-robots-tag")?.includes("noindex"));
  return result;
}

Deno.test("offline Deno SDK: owner auth, publish/guest/update/revoke and private failures", async () => {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "RECIPE_PALS_PUBLIC_WEB_ORIGIN",
  ];
  const prior = names.map((name) => Deno.env.get(name));
  const fetch = globalThis.fetch;
  assert(
    registrations.length === 2 && registrations[0] === manage &&
      registrations[1] === guest,
  );
  try {
    Deno.env.set(names[0], "https://fixture.invalid");
    Deno.env.set(names[1], "synthetic-anon-key");
    Deno.env.set(names[2], "synthetic-service-key");
    Deno.env.set(names[3], "https://recipes.recipepals.app");
    globalThis.fetch = syntheticFetch;
    row = null;
    calls = [];
    quota = false;
    databaseError = false;

    await status(
      manage(
        new Request("https://edge.invalid/recipe-share-manage", {
          method: "GET",
        }),
      ),
      401,
    );
    await status(manage(request("POST", "", payload, "expired")), 401);
    await status(
      manage(request("POST", "", payload, "synthetic-service-key")),
      401,
    );
    await status(manage(request("POST", "", payload, "anonymous")), 401);
    assert(!calls.some((call) => call.includes("/rest/")));
    Deno.env.delete(names[3]);
    await status(manage(request("POST")), 503);
    equal(row, null);
    Deno.env.set(names[3], "https://recipes.recipepals.app");
    for (
      const bad of [{ ...payload, ownerID: other }, {
        ...payload,
        hasDistributionRights: false,
      }, {
        ...payload,
        snapshot: { ...snapshot, sourceURL: "https://localhost/private" },
      }]
    ) {
      await status(manage(request("POST", "", bad)), 400);
      equal(row, null);
    }
    const huge = request("POST");
    huge.headers.set("content-length", String(2 * 1024 * 1024 + 1));
    await status(manage(huge), 413);
    equal(row, null);

    const created = await (await status(manage(request("POST")), 201)).json();
    assert(/^[A-Za-z0-9_-]{43}$/.test(created.slug));
    equal(
      created.publicURL,
      "https://recipes.recipepals.app/r/" + created.slug,
    );
    equal(
      Object.keys(created).sort(),
      [
        "shareID",
        "slug",
        "shareVersion",
        "scope",
        "createdAt",
        "updatedAt",
        "revokedAt",
        "publicURL",
      ].sort(),
    );
    equal(await (await status(manage(request("POST")), 200)).json(), created);
    await status(
      manage(
        request("POST", "", {
          ...payload,
          snapshot: { ...snapshot, title: "Changed" },
        }),
      ),
      409,
    );
    equal(await (await status(guest(visitor()), 200)).json(), snapshot);
    equal(await (await status(guest(visitor("HEAD")), 200)).text(), "");
    equal(
      (await (await status(manage(request("GET")), 200)).json()).shares.length,
      1,
    );
    await status(manage(request("GET", shareID, undefined, "owner-b")), 404);
    equal(
      (await (await status(
        manage(request("GET", "", undefined, "owner-b")),
        200,
      )).json()).shares,
      [],
    );
    const { idempotencyKey: _key, ...update } = payload;
    await status(
      manage(request("PUT", shareID, update, "owner-b", '"v1"')),
      404,
    );
    await status(manage(request("DELETE", shareID, undefined, "owner-b")), 404);
    await status(
      manage(request("PUT", shareID, update, "owner-a", '"v9"')),
      409,
    );
    const fresh = {
      ...update,
      snapshot: { ...snapshot, title: "Fresh approved" },
    };
    equal(
      (await (await status(
        manage(request("PUT", shareID, fresh, "owner-a", '"v1"')),
        200,
      )).json()).shareVersion,
      2,
    );
    await status(
      manage(request("PUT", shareID, update, "owner-a", '"v1"')),
      409,
    );
    equal(
      (await (await status(guest(visitor()), 200)).json()).title,
      "Fresh approved",
    );
    Deno.env.delete(names[3]);
    await status(manage(request("DELETE", shareID)), 204);
    await status(manage(request("DELETE", shareID)), 204);
    await status(guest(visitor()), 404);
    Deno.env.set(names[3], "https://recipes.recipepals.app");
    await status(
      manage(request("PUT", shareID, update, "owner-a", '"v2"')),
      404,
    );
    await status(manage(request("POST")), 409);
    equal(row!.sanitized_snapshot, null);
    row = null;
    await status(guest(visitor("GET", created.slug)), 404);
    quota = true;
    await status(manage(request("POST")), 429);
    equal(row, null);
    databaseError = true;
    const failed = await status(manage(request("POST")), 503);
    assert(!(await failed.text()).includes("PRIVATE_MARKER"));
    equal(
      await (await status(guest(visitor("HEAD", created.slug)), 503)).text(),
      "",
    );
    const count = calls.length;
    await status(guest(visitor("POST", created.slug)), 405);
    await status(guest(visitor("GET", "short")), 404);
    equal(calls.length, count);
  } finally {
    globalThis.fetch = fetch;
    names.forEach((name, index) =>
      prior[index] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, prior[index]!)
    );
  }
});
