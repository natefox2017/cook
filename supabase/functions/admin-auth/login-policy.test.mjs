// Developer: gengyun
// Purpose: Exercise the actual admin-auth handler's independent passkey policy with local service mocks.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

// No Deno runtime, database, browser authenticator, or cryptographic verification
// is simulated as an end-to-end PASS. Only handler orchestration is tested here.
const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
const executable = stripTypeScriptTypes(source).replace(
  /^import\s+[\s\S]*?;\s*$/gm,
  "",
);

function fixture({ totp = true, locked = false, verified = true } = {}) {
  let handler;
  let sessionCount = 0;
  let loginConsumed = false;
  let passkeyConsumed = false;
  let verificationCalls = 0;
  const events = [];
  const account = { id: "owner", username: "owner", role: "owner" };
  const login = {
    id: "password-challenge", admin_id: account.id, attempts: 0,
    expires_at: new Date(Date.now() + 60_000).toISOString(), consumed_at: null,
  };
  const webauthn = {
    id: "webauthn-challenge", admin_id: account.id, challenge: "expected",
    login_challenge_id: null, expires_at: login.expires_at, consumed_at: null,
  };
  const credential = {
    credential_id: "credential", public_key: "AA==", sign_count: 7, transports: ["internal"],
  };

  class AppError extends Error {
    constructor(code, message, status) {
      super(message);
      this.code = code;
      this.status = status;
    }
  }

  function query(table) {
    let operation = "select";
    let payload;
    const filters = [];
    const chain = {
      select() { return chain; },
      eq(key, value) { filters.push([key, value]); return chain; },
      is() { return chain; },
      gt() { return chain; },
      lt() { return chain; },
      delete() { operation = "delete"; return chain; },
      insert(value) { operation = "insert"; payload = value; return chain; },
      update(value) { operation = "update"; payload = value; return chain; },
      maybeSingle() { return result(true); },
      single() { return result(true); },
      then(resolve, reject) { return result(false).then(resolve, reject); },
    };
    async function result(single) {
      if (operation === "delete") return { data: null, error: null };
      if (table === "admin_accounts") return { data: account, error: null };
      if (table === "admin_auth_factors") {
        return { data: { totp_enabled_at: totp ? "enabled" : null }, error: null };
      }
      if (table === "admin_passkeys") {
        if (operation === "update") {
          assert.equal(payload.sign_count, 8);
          assert.ok(filters.some(([key, value]) => key === "sign_count" && value === 7));
          return { data: null, error: null };
        }
        return { data: single ? credential : [credential], error: null };
      }
      if (table === "admin_auth_login_challenges") {
        if (operation === "insert") return { data: null, error: null };
        if (operation === "update") {
          if (loginConsumed) return { data: null, error: null };
          loginConsumed = true;
          return { data: login, error: null };
        }
        return { data: { ...login, consumed_at: loginConsumed ? "consumed" : null }, error: null };
      }
      if (table === "admin_auth_webauthn_challenges") {
        if (operation === "insert") {
          webauthn.login_challenge_id = payload.login_challenge_id;
          return { data: { id: webauthn.id }, error: null };
        }
        if (operation === "update") {
          if (passkeyConsumed) return { data: null, error: null };
          passkeyConsumed = true;
          return { data: webauthn, error: null };
        }
        return { data: { ...webauthn, consumed_at: passkeyConsumed ? "consumed" : null }, error: null };
      }
      throw new Error(`Unexpected table: ${table}`);
    }
    return chain;
  }

  const client = {
    from: query,
    async rpc(name, input) {
      if (name === "admin_verify_credentials") return { data: account, error: null };
      assert.equal(name, "admin_record_login_event");
      events.push(input);
      return { data: { allowed: !locked }, error: null };
    },
  };
  runInNewContext(executable, {
    Request, Response, URL, Date, Uint8Array, atob, TextEncoder, console,
    Deno: { serve(callback) { handler = callback; } },
    createServiceClient: () => client,
    handleCors: () => null, publicCorsHeaders: {}, AppError,
    json: (body, status = 200) => new Response(JSON.stringify(body), { status }),
    errorResponse: (error) => new Response(JSON.stringify({ error: error.message }), { status: error.status ?? 500 }),
    readBoundedJSONObject: (request) => request.json(),
    log: () => {}, parseAdminRole: (role) => role,
    isAdminProductionRuntime: () => false, isDefaultAdminCredentials: () => false,
    hashChallenge: async (value) => value, newChallenge: () => "password-token",
    webauthnConfig: () => ({ origin: "https://admin.example.test", rpID: "admin.example.test" }),
    generateAuthenticationOptions: async (options) => {
      assert.equal(options.userVerification, "required");
      assert.equal(options.rpID, "admin.example.test");
      assert.equal(options.allowCredentials[0].id, credential.credential_id);
      return { challenge: "expected" };
    },
    verifyAuthenticationResponse: async (options) => {
      verificationCalls++;
      assert.equal(options.expectedOrigin, "https://admin.example.test");
      assert.equal(options.expectedRPID, "admin.example.test");
      assert.equal(options.expectedChallenge, "expected");
      assert.equal(options.requireUserVerification, true);
      assert.equal(options.credential.counter, 7);
      return { verified, authenticationInfo: { newCounter: 8 } };
    },
    createAdminSession: async (id) => {
      assert.equal(id, account.id);
      sessionCount++;
      return { token: "session", expiresAt: login.expires_at };
    },
  });
  return {
    async call(action, body) {
      const response = await handler(new Request(`https://example.test/admin-auth/${action}`, {
        method: "POST", body: JSON.stringify(body),
      }));
      return { status: response.status, body: await response.json() };
    },
    login, webauthn, events,
    get sessionCount() { return sessionCount; },
    get verificationCalls() { return verificationCalls; },
  };
}

for (const totp of [false, true]) {
  for (const viaChallenge of [false, true]) {
    test(`passkey independently signs in: TOTP=${totp}, password challenge=${viaChallenge}`, async () => {
      const app = fixture({ totp });
      const options = await app.call("login-passkey-options", viaChallenge
        ? { challengeToken: "password-token" }
        : { username: "owner" });
      assert.equal(options.status, 200);
      assert.equal(app.sessionCount, 0);
      assert.equal(app.webauthn.login_challenge_id, viaChallenge ? app.login.id : null);
      const result = await app.call("login-passkey-verify", {
        challengeId: app.webauthn.id, response: { id: "credential" },
      });
      assert.equal(result.status, 200);
      assert.equal(result.body.token, "session");
      assert.equal(app.sessionCount, 1);
      const replay = await app.call("login-passkey-verify", {
        challengeId: app.webauthn.id, response: { id: "credential" },
      });
      assert.equal(replay.status, 401);
      assert.equal(app.sessionCount, 1);
      if (viaChallenge) {
        assert.equal((await app.call("login-passkey-options", { challengeToken: "password-token" })).status, 401);
      }
    });
  }
}

test("password with TOTP enabled still returns only a TOTP challenge and retains failure count", async () => {
  const app = fixture();
  const result = await app.call("login", { username: "owner", password: "password" });
  assert.equal(result.status, 200);
  assert.equal(result.body.factorRequired, true);
  assert.deepEqual(result.body.methods, ["totp"]);
  assert.equal(result.body.token, undefined);
  assert.equal(app.sessionCount, 0);
  assert.equal(app.events[0].p_reset_failures, false);
});

test("verified passkey cannot create a session when final account lockout guard rejects it", async () => {
  const app = fixture({ locked: true });
  const result = await app.call("login-passkey-verify", {
    challengeId: app.webauthn.id, response: { id: "credential" },
  });
  assert.equal(result.status, 401);
  assert.equal(app.verificationCalls, 1);
  assert.equal(app.sessionCount, 0);
});

test("unverified passkey cannot create a session or consume the password challenge", async () => {
  const app = fixture({ verified: false });
  await app.call("login-passkey-options", { challengeToken: "password-token" });
  const result = await app.call("login-passkey-verify", {
    challengeId: app.webauthn.id, response: { id: "credential" },
  });
  assert.equal(result.status, 401);
  assert.equal(app.sessionCount, 0);
  assert.equal((await app.call("login-passkey-options", { challengeToken: "password-token" })).status, 200);
});

test("expired password and WebAuthn challenges cannot proceed", async () => {
  const app = fixture();
  app.login.expires_at = new Date(0).toISOString();
  assert.equal((await app.call("login-passkey-options", { challengeToken: "password-token" })).status, 401);
  app.webauthn.expires_at = new Date(0).toISOString();
  assert.equal((await app.call("login-passkey-verify", {
    challengeId: app.webauthn.id, response: { id: "credential" },
  })).status, 401);
  assert.equal(app.verificationCalls, 0);
  assert.equal(app.sessionCount, 0);
});
