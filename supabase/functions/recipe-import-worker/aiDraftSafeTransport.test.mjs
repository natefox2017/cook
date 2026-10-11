// Developer: gengyun
// Purpose: Exercise pinned HTTPS options and real writer/reader events without network access.
import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { createAIDraftSafeTransport } from "./aiDraftSafeTransport.ts";
import { createOpenAIDraftProvider } from "./aiDraftProvider.ts";
const public4 = "93.184.216.34", public6 = "2606:4700:4700::1111";
const endpoint = "https://provider.example.test/v1/chat/completions";
const request = (body = "{}", changes = {}) =>
  new Request(changes.url ?? endpoint, {
    method: changes.method ?? "POST",
    redirect: changes.redirect ?? "error",
    headers: {
      Authorization: "Bearer synthetic-secret",
      Accept: "application/json",
      "Content-Type": "application/json",
      ...(changes.headers ?? {}),
    },
    body,
    ...(body instanceof ReadableStream ? { duplex: "half" } : {}),
    ...(changes.signal ? { signal: changes.signal } : {}),
  });
const policy = () => ({
  signal: new AbortController().signal,
  maxResponseBytes: 65536,
});
const fail = async (promise, code) =>
  assert.rejects(promise, (e) => {
    assert.equal(e.code, code);
    assert.equal(e.message, `DRAFT_TRANSPORT_${code}`);
    return true;
  });
function fixture(options = {}) {
  const f = { dns: [], sockets: [], messages: [], writes: [], ends: 0 };
  f.native = (opts, callback) => {
    const req = new EventEmitter();
    req.destroyed = false;
    req.destroy = () => {
      req.destroyed = true;
      return req;
    };
    req.write = (bytes) => {
      f.writes.push(Buffer.from(bytes));
      return true;
    };
    req.end = () => {
      f.ends++;
      queueMicrotask(() => {
        if (f.emit) f.emit(callback, req);
        else f.respond(callback);
      });
    };
    f.sockets.push({ opts, req, callback });
    return req;
  };
  f.respond = (callback, config = {}) => {
    const message = new EventEmitter();
    message.destroyed = false;
    message.destroy = () => {
      message.destroyed = true;
      return message;
    };
    message.statusCode = config.status ?? 200;
    message.headers = {
      "content-type": "application/json",
      ...(config.headers ?? {}),
    };
    f.messages.push(message);
    callback(message);
    if (!message.destroyed && config.auto !== false) {
      for (const chunk of config.chunks ?? [Buffer.from("{}")]) {
        message.emit("data", chunk);
      }
      message.emit("end");
      message.emit("close");
    }
    return message;
  };
  f.options = {
    enabled: true,
    resolveDNS: async (host, record, signal) => {
      f.dns.push({ host, record, signal });
      return record === "A" ? [public4] : [public6];
    },
    requestHTTPS: f.native,
    ...options,
  };
  f.transport = createAIDraftSafeTransport(f.options);
  return f;
}
function lookup(opts, host = opts.hostname, options = {}) {
  return new Promise((resolve, reject) =>
    opts.lookup(
      host,
      options,
      (error, ...args) => error ? reject(error) : resolve(args),
    )
  );
}
test("disabled/factory do not touch env/body/DNS/socket and fake native needs no environment permission", async () => {
  for (const enabled of [undefined, false, "true", 1]) {
    const f = fixture({ enabled });
    await fail(f.transport(request(), policy()), "DISABLED");
    assert.equal(f.dns.length, 0);
    assert.equal(f.sockets.length, 0);
  }
  const p = createAIDraftSafeTransport({ enabled: true });
  assert.equal(typeof p, "function");
  const f = fixture();
  assert.equal((await f.transport(request(), policy())).status, 200);
  assert.equal(f.sockets.length, 1);
});
test("default native proxy environment denied fails closed before DNS/socket (no env grant)", async () => {
  let dns = 0;
  const transport = createAIDraftSafeTransport({
    enabled: true,
    resolveDNS: async () => {
      dns++;
      return [public4];
    },
  });
  await fail(transport(request(), policy()), "BLOCKED");
  assert.equal(dns, 0);
});
test("strict request URL/method/headers/token and invalid UTF8 fail before DNS", async () => {
  for (
    const changes of [
      { url: "http://provider.example.test/v1" },
      { url: "https://127.0.0.1/v1" },
      { url: "https://provider.local/v1" },
      { url: "https://provider.example.test./v1" },
      { url: endpoint + "#private" },
      { url: endpoint + "?secret=x" },
      { url: "https://user:pass@provider.example.test/v1" },
      { url: "https://provider.example.test:8443/v1" },
      { method: "PUT" },
      { redirect: "follow" },
      { headers: { Cookie: "private" } },
      { headers: { Host: "evil.test" } },
      { headers: { "Proxy-Authorization": "Bearer injected" } },
      { headers: { Authorization: "Bearer " + "x".repeat(8193) } },
      { headers: { Accept: "text/plain" } },
      { headers: { "Content-Type": "text/plain" } },
    ]
  ) {
    const f = fixture();
    await assert.rejects(f.transport(request("{}", changes), policy()));
    assert.equal(f.dns.length, 0);
    assert.equal(f.sockets.length, 0);
  }
  const f = fixture();
  await fail(
    f.transport(request(new Uint8Array([255])), policy()),
    "INVALID_REQUEST",
  );
  assert.equal(f.dns.length, 0);
  const good = fixture();
  await good.transport(
    request("{}", { headers: { Authorization: "Bearer " + "x".repeat(8192) } }),
    policy(),
  );
  assert.equal(good.sockets[0].opts.headers.Authorization.length, 8199);
});
test("dual family fresh resolution pins native lookup and CA/SNI without forwarding private headers", async () => {
  const f = fixture();
  const body = '{"text":"é"}';
  const result = await f.transport(request(body), policy());
  assert.equal(await result.text(), "{}");
  const o = f.sockets[0].opts;
  assert.equal(o.hostname, "provider.example.test");
  assert.equal(o.servername, o.hostname);
  assert.equal(o.port, 443);
  assert.equal(o.method, "POST");
  assert.equal(o.path, "/v1/chat/completions");
  assert.equal(o.agent, false);
  assert.equal(o.rejectUnauthorized, true);
  assert.equal(o.maxHeaderSize, 16384);
  assert.ok(o.signal instanceof AbortSignal);
  assert.equal(o.headers["Accept-Encoding"], "identity");
  assert.equal(o.headers.Connection, "close");
  assert.equal(o.headers["Content-Length"], String(Buffer.byteLength(body)));
  assert.equal(o.ca, undefined);
  assert.equal(o.checkServerIdentity, undefined);
  assert.equal(f.writes[0].toString(), body);
  assert.equal(f.writes.length, 1);
  assert.equal(f.ends, 1);
  assert.deepEqual(f.dns.map((x) => x.record), ["A", "AAAA"]);
  assert.deepEqual(await lookup(o, undefined, { all: true }), [[{
    address: public4,
    family: 4,
  }, { address: public6, family: 6 }]]);
  assert.deepEqual(await lookup(o, undefined, { family: 4 }), [public4, 4]);
  assert.deepEqual(await lookup(o, undefined, { family: 6 }), [public6, 6]);
  await assert.rejects(lookup(o, "evil.example.test"));
  await assert.rejects(lookup(o, undefined, { family: 5 }));
  await f.transport(request(), policy());
  assert.equal(f.dns.length, 4);
  assert.equal(f.sockets.length, 2);
});
test("any private/mapped/malformed/wrong-family address blocks both families", async () => {
  for (
    const [record, address] of [
      ["A", "127.0.0.1"],
      ["A", "169.254.169.254"],
      ["A", "10.0.0.2"],
      ["A", "not-an-IP"],
      ["A", public6],
      ["AAAA", "::1"],
      ["AAAA", "fe80::1"],
      ["AAAA", "::ffff:127.0.0.1"],
      ["AAAA", public4],
    ]
  ) {
    const f = fixture({
      resolveDNS: async (host, type) =>
        type === record ? [address] : type === "A" ? [public4] : [public6],
    });
    await fail(f.transport(request(), policy()), "BLOCKED");
    assert.equal(f.sockets.length, 0);
  }
  const f = fixture({ resolveDNS: async () => [] });
  await fail(f.transport(request(), policy()), "BLOCKED");
  assert.equal(f.sockets.length, 0);
});
test("NotFound family is empty while DNS failure/ignored abort fails closed", async () => {
  const f = fixture({
    resolveDNS: async (host, type) => {
      if (type === "AAAA") throw new Deno.errors.NotFound("no records");
      return [public4];
    },
  });
  await f.transport(request(), policy());
  await assert.rejects(lookup(f.sockets[0].opts, undefined, { family: 6 }));
  const broken = fixture({
    resolveDNS: async () => {
      throw Error("DNS secret");
    },
  });
  await fail(broken.transport(request(), policy()), "UPSTREAM");
  assert.equal(broken.sockets.length, 0);
  let release;
  const late = fixture({
    timeoutMs: 20,
    resolveDNS: () =>
      new Promise((resolve) => {
        release = resolve;
      }),
  });
  await fail(late.transport(request(), policy()), "TIMEOUT");
  release([public4]);
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(late.sockets.length, 0);
});
test("65536 request bytes, chunked overflow and Content-Length mismatch are bounded", async () => {
  const f = fixture();
  await f.transport(
    request("x".repeat(65536), { headers: { "Content-Length": "65536" } }),
    policy(),
  );
  assert.equal(f.writes[0].byteLength, 65536);
  for (
    const [body, headers, code] of [
      ["x".repeat(65537), {}, "REQUEST_TOO_LARGE"],
      ["{}", { "Content-Length": "65537" }, "REQUEST_TOO_LARGE"],
      ["{}", { "Content-Length": "1" }, "INVALID_REQUEST"],
      ["", {}, "INVALID_REQUEST"],
      ["{}", { "Content-Length": "02" }, "REQUEST_TOO_LARGE"],
    ]
  ) {
    const g = fixture();
    await fail(g.transport(request(body, { headers }), policy()), code);
    assert.equal(g.sockets.length, 0);
    assert.equal(g.dns.length, 0);
  }
  const stream = new ReadableStream({
    start(c) {
      c.enqueue(new Uint8Array(33000));
      c.enqueue(new Uint8Array(33000));
    },
    cancel() {
      return new Promise(() => {});
    },
  });
  const g = fixture();
  await fail(g.transport(request(stream), policy()), "REQUEST_TOO_LARGE");
  assert.equal(g.sockets.length, 0);
});
test("responses are bounded by actual bytes and caller cap, declarations/types/encodings", async () => {
  const f = fixture();
  f.emit = (cb) =>
    f.respond(cb, {
      chunks: [Buffer.alloc(65536)],
      headers: {
        "content-length": "65536",
        "set-cookie": "PRIVATE",
        "location": "PRIVATE",
      },
    });
  const r = await f.transport(request(), policy());
  assert.equal((await r.arrayBuffer()).byteLength, 65536);
  assert.equal(r.headers.get("set-cookie"), null);
  assert.equal(r.headers.get("location"), null);
  for (
    const config of [
      { chunks: [Buffer.alloc(65537)] },
      { headers: { "content-length": "99999999999999999999" } },
      { headers: { "content-length": "1" } },
      { headers: { "content-length": "02" } },
      { headers: { "content-type": "text/plain" } },
      { headers: { "content-encoding": "gzip" } },
      { headers: { "content-type": ["application/json", "text/plain"] } },
      { chunks: ["not-bytes"] },
    ]
  ) {
    const g = fixture();
    g.emit = (cb) => g.respond(cb, config);
    await assert.rejects(g.transport(request(), policy()));
    assert.equal(g.messages[0].destroyed, true);
    assert.equal(g.sockets[0].req.destroyed, true);
  }
  const g = fixture();
  g.emit = (cb) => g.respond(cb, { chunks: [Buffer.alloc(5)] });
  await fail(
    g.transport(request(), { ...policy(), maxResponseBytes: 4 }),
    "RESPONSE_TOO_LARGE",
  );
});
test("redirects and upstream failures destroy without a second request or retry", async () => {
  for (const status of [301, 302, 303, 307, 308, 400, 401, 429, 500]) {
    const f = fixture();
    f.emit = (cb) =>
      f.respond(cb, { status, headers: { location: "https://evil.test/" } });
    await fail(f.transport(request(), policy()), "UPSTREAM");
    assert.equal(f.sockets.length, 1);
    assert.equal(f.messages[0].destroyed, true);
  }
});
test("native errors/aborted/premature close/double end and late callback cannot double settle", async () => {
  for (const event of ["error", "aborted", "close"]) {
    const f = fixture();
    f.emit = (cb) => {
      const r = f.respond(cb, { auto: false });
      r.emit(event, Error("private payload"));
      r.emit("error", Error("late"));
      r.emit("end");
    };
    await fail(f.transport(request(), policy()), "UPSTREAM");
    assert.equal(f.messages[0].destroyed, true);
  }
  const success = fixture();
  success.emit = (cb) => {
    const r = success.respond(cb);
    r.emit("end");
    r.emit("error", Error("late"));
  };
  assert.equal((await success.transport(request(), policy())).status, 200);
  const thrown = fixture({
    requestHTTPS: () => {
      throw Error("secret");
    },
  });
  await fail(thrown.transport(request(), policy()), "UPSTREAM");
  const f = fixture();
  const abort = new AbortController();
  f.emit = () => {};
  const pending = f.transport(request(), { ...policy(), signal: abort.signal });
  await new Promise((resolve) => setTimeout(resolve, 5));
  abort.abort();
  await fail(pending, "ABORTED");
  const late = f.respond(f.sockets[0].callback, { auto: false });
  assert.equal(late.destroyed, true);
  assert.equal(f.sockets[0].req.destroyed, true);
  assert.equal(f.writes.length, 1);
});
test("caller/request abort, body/DNS/socket hangs honor full transport deadline", async () => {
  for (const source of ["caller", "request"]) {
    const f = fixture(), c = new AbortController();
    c.abort();
    await fail(
      f.transport(
        request("{}", source === "request" ? { signal: c.signal } : {}),
        { ...policy(), ...(source === "caller" ? { signal: c.signal } : {}) },
      ),
      "ABORTED",
    );
    assert.equal(f.sockets.length, 0);
    assert.equal(f.dns.length, 0);
  }
  const hanging = new ReadableStream({
    cancel() {
      return new Promise(() => {});
    },
  });
  const body = fixture({ timeoutMs: 20 });
  await fail(body.transport(request(hanging), policy()), "TIMEOUT");
  assert.equal(body.dns.length, 0);
  const socket = fixture({ timeoutMs: 20 });
  socket.emit = (cb) => socket.respond(cb, { auto: false });
  await fail(socket.transport(request(), policy()), "TIMEOUT");
  assert.equal(socket.messages[0].destroyed, true);
  assert.equal(socket.sockets[0].req.destroyed, true);
});
test("real DEV285 adapter final envelope over32768 fits native65536 and parses bounded output", async () => {
  const f = fixture();
  const outer = {
    choices: [{
      finish_reason: "stop",
      message: {
        role: "assistant",
        content: JSON.stringify({ questions: [], suggestions: [] }),
      },
    }],
    usage: { total_tokens: 0 },
  };
  f.emit = (cb) =>
    f.respond(cb, { chunks: [Buffer.from(JSON.stringify(outer))] });
  const provider = createOpenAIDraftProvider({
    enabled: true,
    route: {
      route_key: "recipe_import_draft_v1",
      primary_model_id: "model",
      enabled: true,
      timeout_ms: 10000,
      max_retries: 0,
      max_output_tokens: 4096,
      temperature: null,
    },
    model: {
      id: "model",
      provider_id: "provider",
      upstream_model_id: "model-name",
      enabled: true,
    },
    provider: {
      id: "provider",
      name: "Synthetic",
      provider_type: "openai_compatible",
      base_url: "https://provider.example.test/v1",
      secret_ref: "synthetic-ref",
      enabled: true,
    },
    resolveSecret: async () => "synthetic-secret",
    transport: f.transport,
  });
  const result = await provider({
    fields: { title: { raw_value: "x".repeat(16000) } },
    evidence: [{ id: "synthetic", excerpt: "y".repeat(16000) }],
    reviewFields: ["title"],
    message: "z".repeat(500),
    maxTotalTokens: 4096,
    signal: new AbortController().signal,
  });
  assert.ok(f.writes[0].byteLength > 32768);
  assert.ok(f.writes[0].byteLength <= 65536);
  assert.deepEqual(result.usage, { totalTokens: 0 });
});

const proxyKeys = [
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "ALL_PROXY",
  "http_proxy",
  "https_proxy",
  "all_proxy",
];
const envGranted =
  (await Deno.permissions.query({ name: "env", variable: "HTTP_PROXY" }))
    .state === "granted";
test(
  "all six proxy variants block default native before DNS and NO_PROXY cannot bypass",
  { skip: !envGranted },
  async () => {
    const saved = new Map(
      [...proxyKeys, "NO_PROXY"].map((key) => [key, Deno.env.get(key)]),
    );
    try {
      for (const key of proxyKeys) Deno.env.delete(key);
      Deno.env.set("NO_PROXY", "*");
      for (const key of proxyKeys) {
        Deno.env.set(key, "synthetic-configured-proxy");
        let dns = 0;
        const native = createAIDraftSafeTransport({
          enabled: true,
          resolveDNS: async () => {
            dns++;
            return [public4];
          },
        });
        await fail(native(request(), policy()), "BLOCKED");
        assert.equal(dns, 0);
        Deno.env.delete(key);
      }
    } finally {
      for (const [key, value] of saved) {
        if (value === undefined) Deno.env.delete(key);
        else Deno.env.set(key, value);
      }
    }
  },
);
test("factory and injected native never read environment flags", async () => {
  const original = Deno.env.get;
  let calls = 0;
  Deno.env.get = () => {
    calls++;
    throw new Deno.errors.PermissionDenied("denied");
  };
  try {
    createAIDraftSafeTransport({ enabled: true });
    const f = fixture();
    await f.transport(request(), policy());
    assert.equal(calls, 0);
  } finally {
    Deno.env.get = original;
  }
});
test("factory dependency snapshot and per-call response cap survive mutations during DNS", async () => {
  let release;
  const ready = new Promise((resolve) => release = resolve);
  const f = fixture({
    resolveDNS: async (_, family) => {
      await ready;
      return family === "A" ? [public4] : [public6];
    },
  });
  const p = { ...policy(), maxResponseBytes: 2 };
  f.emit = (cb) => f.respond(cb, { chunks: [Buffer.from("123")] });
  const pending = f.transport(request(), p);
  f.options.enabled = false;
  f.options.requestHTTPS = () => {
    throw Error("changed hook must not execute");
  };
  f.options.resolveDNS = () => {
    throw Error("changed DNS must not execute");
  };
  f.options.timeoutMs = 100000;
  p.maxResponseBytes = 65536;
  release();
  await fail(pending, "RESPONSE_TOO_LARGE");
  assert.equal(f.sockets.length, 1);
});
test("late response destroy throwing is best effort without uncaught errors", async () => {
  const f = fixture({ timeoutMs: 20 });
  f.emit = () => {};
  await fail(f.transport(request(), policy()), "TIMEOUT");
  const response = new EventEmitter();
  response.destroy = () => {
    throw Error("late cleanup");
  };
  assert.doesNotThrow(() => f.sockets[0].callback(response));
});

test("monotonic deadline rejects blocked callbacks/data/end before timer can run", async () => {
  const block = () => {
    const end = performance.now() + 25;
    while (performance.now() < end) {}
  };
  for (const phase of ["callback", "data", "end"]) {
    const f = fixture({ timeoutMs: 20 });
    f.emit = (cb) => {
      if (phase === "callback") block();
      const r = f.respond(cb, { auto: false });
      if (phase === "data") block();
      r.emit("data", Buffer.from("{}"));
      if (phase === "end") block();
      r.emit("end");
    };
    await fail(f.transport(request(), policy()), "TIMEOUT");
    assert.equal(f.messages[0].destroyed, true);
    assert.equal(f.sockets[0].req.destroyed, true);
  }
});
test("synchronous native write error never ends an already rejected request", async () => {
  const f = fixture();
  f.options.requestHTTPS = (opts, callback) => {
    const req = f.native(opts, callback);
    req.write = (bytes) => {
      f.writes.push(Buffer.from(bytes));
      req.emit("error", Error("sync writer error"));
      return false;
    };
    return req;
  };
  f.transport = createAIDraftSafeTransport(f.options);
  await fail(f.transport(request(), policy()), "UPSTREAM");
  assert.equal(f.writes.length, 1);
  assert.equal(f.ends, 0);
  assert.equal(f.sockets[0].req.destroyed, true);
});
