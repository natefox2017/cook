// Developer: gengyun
// Purpose: Exercise URL, DNS, redirect, size, timeout and MIME boundaries without external writes.

import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  fetchPublicHTML,
  isPublicAddress,
  SafeFetchError,
  validatePublicHTTPSURL,
} from "./safeURLFetch.ts";

const htmlResponse = (body = "<html></html>") => ({
  status: 200,
  headers: { "content-type": "text/html; charset=utf-8" },
  body: new TextEncoder().encode(body),
});

Deno.test("accepts only HTTPS DNS hostnames on the default port", () => {
  assertEquals(
    validatePublicHTTPSURL("https://recipes.example/soup#step-1").toString(),
    "https://recipes.example/soup",
  );
  for (
    const value of [
      "http://recipes.example/soup",
      "https://127.0.0.1/soup",
      "https://127.1/soup",
      "https://2130706433/soup",
      "https://0x7f000001/soup",
      "https://[::1]/soup",
      "https://user@recipes.example/soup",
      "https://recipes.example:8443/soup",
      "https://localhost/soup",
      "https://private.local/soup",
    ]
  ) {
    let blocked = false;
    try {
      validatePublicHTTPSURL(value);
    } catch (error) {
      blocked = error instanceof SafeFetchError &&
        error.code === "FETCH_BLOCKED";
    }
    assertEquals(blocked, true, value);
  }
});

Deno.test("rejects private, link-local, documentation and benchmarking IP ranges", () => {
  for (
    const address of [
      "10.1.2.3",
      "127.0.0.1",
      "169.254.10.2",
      "172.20.1.1",
      "192.168.1.20",
      "192.0.2.20",
      "198.18.0.54",
      "198.51.100.12",
      "203.0.113.12",
      "224.0.0.1",
    ]
  ) {
    assertEquals(isPublicAddress(address), false, address);
  }
  assertEquals(isPublicAddress("151.101.1.91"), true);
});

Deno.test("pins every redirect to a freshly resolved public address", async () => {
  const resolved: string[] = [];
  const connected: Array<{ host: string; address: string }> = [];
  const result = await fetchPublicHTML("https://first.example/recipe", {
    resolveIPv4: async (host) => {
      resolved.push(host);
      return host === "first.example" ? ["151.101.1.91"] : ["151.101.65.91"];
    },
    request: async (url, addresses) => {
      connected.push({ host: url.hostname, address: addresses[0] });
      return url.hostname === "first.example"
        ? {
          status: 302,
          headers: { location: "https://second.example/recipe" },
          body: new Uint8Array(),
        }
        : htmlResponse("<html>recipe</html>");
    },
  });

  assertEquals(resolved, ["first.example", "second.example"]);
  assertEquals(connected, [
    { host: "first.example", address: "151.101.1.91" },
    { host: "second.example", address: "151.101.65.91" },
  ]);
  assertEquals(result.canonicalURL, "https://second.example/recipe");
  assertEquals(result.html, "<html>recipe</html>");
});

Deno.test("blocks a redirect whose freshly resolved address is private", async () => {
  let requests = 0;
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: async (host) =>
          host === "first.example" ? ["151.101.1.91"] : ["10.0.0.4"],
        request: async () => {
          requests++;
          return {
            status: 302,
            headers: { location: "https://inside.example/admin" },
            body: new Uint8Array(),
          };
        },
      }),
    SafeFetchError,
    "non-public address",
  );
  assertEquals(requests, 1);
});

Deno.test("rejects a DNS answer set that mixes public and private addresses", async () => {
  let requests = 0;
  await assertRejects(
    () =>
      fetchPublicHTML("https://mixed.example/", {
        resolveIPv4: async () => ["151.101.1.91", "192.168.1.8"],
        request: async () => {
          requests++;
          return htmlResponse();
        },
      }),
    SafeFetchError,
    "non-public address",
  );
  assertEquals(requests, 0);
});

Deno.test("rejects non-HTTPS redirects and redirect chains over the limit", async () => {
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: async () => ["151.101.1.91"],
        request: async () => ({
          status: 302,
          headers: { location: "http://second.example/" },
          body: new Uint8Array(),
        }),
      }),
    SafeFetchError,
    "Only public HTTPS",
  );

  let requests = 0;
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: async () => ["151.101.1.91"],
        request: async (url) => {
          requests++;
          return {
            status: 302,
            headers: { location: `https://${url.hostname}/again` },
            body: new Uint8Array(),
          };
        },
      }),
    SafeFetchError,
    "redirect limit",
  );
  assertEquals(requests, 4);
});

Deno.test("enforces body size, content type and content encoding", async () => {
  const resolver = async () => ["151.101.1.91"];
  const oversized = new Uint8Array(1_500_001);
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: resolver,
        request: async () => ({
          status: 200,
          headers: { "content-type": "text/html" },
          body: oversized,
        }),
      }),
    SafeFetchError,
    "size limit",
  );
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: resolver,
        request: async () => ({
          status: 200,
          headers: { "content-type": "application/pdf" },
          body: new Uint8Array(),
        }),
      }),
    SafeFetchError,
    "did not return an HTML",
  );
  await assertRejects(
    () =>
      fetchPublicHTML("https://first.example/", {
        resolveIPv4: resolver,
        request: async () => ({
          status: 200,
          headers: {
            "content-type": "text/html",
            "content-encoding": "gzip",
          },
          body: new Uint8Array(),
        }),
      }),
    SafeFetchError,
    "content encoding",
  );
});
