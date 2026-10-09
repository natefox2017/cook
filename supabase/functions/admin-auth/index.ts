// Admin dashboard auth: custom bearer sessions, password, TOTP, and passkeys.
// This is separate from end-user Supabase Auth.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  type AuthenticatorTransportFuture,
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from "npm:@simplewebauthn/server@13.3.0";
import { handleCors, publicCorsHeaders } from "../_shared/cors.ts";
import { AppError, errorResponse, json } from "../_shared/errors.ts";
import { parseAdminRole } from "../_shared/admin-role.ts";
import { readBoundedJSONObject } from "../_shared/bounded-json.ts";
import { createServiceClient } from "../_shared/auth.ts";
import { log } from "../_shared/logger.ts";
import {
  createAdminSession,
  requireAdminSession,
  sha256Hex,
} from "../_shared/admin-session.ts";
import {
  isAdminProductionRuntime,
  isDefaultAdminCredentials,
  validateAdminPassword,
} from "../_shared/admin-password.ts";
import {
  publicAdminBootstrapError,
  withAdminBootstrapAuthorization,
} from "../_shared/admin-bootstrap.ts";
import {
  decryptTotpSecret,
  encryptTotpSecret,
  hashChallenge,
  matchingTotpCounter,
  newChallenge,
  newTotpSecret,
  webauthnConfig,
} from "./factors.ts";
import { bootstrapStatus } from "./bootstrap-status.ts";

function routeAction(req: Request): string {
  const parts = new URL(req.url).pathname.split("/").filter(Boolean);
  const idx = parts.findIndex((part) => part === "admin-auth");
  return (idx >= 0 ? parts[idx + 1] : parts.at(-1) ?? "").toLowerCase();
}

const MAX_ADMIN_AUTH_BODY_BYTES = 16 * 1024;
const FACTOR_CHALLENGE_TTL_MS = 5 * 60 * 1000;
const supportedTransports = new Set([
  "ble",
  "hybrid",
  "internal",
  "nfc",
  "usb",
]);

function credentialTransports(value: unknown): AuthenticatorTransportFuture[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is AuthenticatorTransportFuture =>
    typeof item === "string" && supportedTransports.has(item)
  );
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  return readBoundedJSONObject(req, MAX_ADMIN_AUTH_BODY_BYTES);
}

function requestIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const value = forwarded || req.headers.get("x-real-ip")?.trim() || "";
  return value.slice(0, 64);
}

async function recordLoginEvent(
  req: Request,
  input: {
    identityKey: string | null;
    adminId: string | null;
    method: "password" | "totp" | "passkey" | "bootstrap";
    success: boolean;
    resetFailures?: boolean;
    failureReason?:
      | "invalid_credentials"
      | "invalid_totp"
      | "invalid_passkey"
      | "account_locked"
      | "bootstrap_failed";
  },
): Promise<boolean> {
  const { data, error } = await createServiceClient().rpc(
    "admin_record_login_event",
    {
      p_identity_key: input.identityKey,
      p_admin_id: input.adminId,
      p_method: input.method,
      p_success: input.success,
      p_reset_failures: input.resetFailures ?? true,
      p_ip_address: requestIp(req),
      p_user_agent: (req.headers.get("user-agent") ?? "").slice(0, 512),
      p_failure_reason: input.failureReason ?? null,
    },
  );
  if (error) {
    log("error", "admin_login_event_write_failed", { method: input.method });
    throw new AppError(
      "internal_error",
      "Unable to record authentication event",
      500,
    );
  }
  const result = Array.isArray(data) ? data[0] : data;
  return Boolean(result?.allowed);
}

function adminIdentityKey(adminId: string): string {
  return `admin:${adminId}`;
}

async function unknownIdentityKey(username: string): Promise<string> {
  return `unknown:${await hashChallenge(username.trim().toLowerCase())}`;
}

function denyLocked(): never {
  throw new AppError("unauthorized", "Invalid username or password", 401);
}

async function revokeOtherAdminSessions(
  adminId: string,
  currentSessionId: string,
) {
  const { error } = await createServiceClient().from("admin_sessions")
    .update({ revoked_at: new Date().toISOString() })
    .eq("admin_id", adminId)
    .is("revoked_at", null)
    .neq("id", currentSessionId);
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to revoke prior admin sessions",
      500,
    );
  }
}

async function loadAdminRow(adminId: string) {
  const { data, error } = await createServiceClient()
    .from("admin_accounts")
    .select("id, username, role, is_default_seed, must_change_password")
    .eq("id", adminId)
    .maybeSingle();
  if (error) {
    throw new AppError("internal_error", "Failed to load admin account", 500);
  }
  if (!data) throw new AppError("unauthorized", "Invalid admin account", 401);
  return data;
}

function mapAdmin(row: {
  id: string;
  username: string;
  role?: string | null;
  must_change_password?: boolean | null;
}) {
  return {
    id: row.id,
    username: row.username,
    role: parseAdminRole(row.role),
    mustChangePassword: Boolean(row.must_change_password),
  };
}

function requireString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || !value.trim()) {
    throw new AppError("validation_error", `${key} is required`, 400);
  }
  return value.trim();
}

function expiry(): string {
  return new Date(Date.now() + FACTOR_CHALLENGE_TTL_MS).toISOString();
}

async function createLoginChallenge(adminId: string): Promise<string> {
  const now = new Date().toISOString();
  await createServiceClient().from("admin_auth_login_challenges")
    .delete()
    .lt("expires_at", now);
  await createServiceClient().from("admin_auth_webauthn_challenges")
    .delete()
    .lt("expires_at", now);
  const token = newChallenge();
  const { error } = await createServiceClient().from(
    "admin_auth_login_challenges",
  ).insert({
    admin_id: adminId,
    challenge_hash: await hashChallenge(token),
    expires_at: expiry(),
  });
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to start factor verification",
      500,
    );
  }
  return token;
}

async function enabledLoginFactors(adminId: string): Promise<string[]> {
  const admin = createServiceClient();
  const [
    { data: factor, error: factorError },
    { data: passkeys, error: passkeyError },
  ] = await Promise.all([
    admin.from("admin_auth_factors").select("totp_enabled_at").eq(
      "admin_id",
      adminId,
    ).maybeSingle(),
    admin.from("admin_passkeys").select("credential_id").eq(
      "admin_id",
      adminId,
    ),
  ]);
  if (factorError || passkeyError) {
    throw new AppError(
      "internal_error",
      "Unable to load administrator factors",
      500,
    );
  }
  return [
    ...(factor?.totp_enabled_at ? ["totp"] : []),
    ...(passkeys?.length ? ["passkey"] : []),
  ];
}

async function requireLoginFactor(
  adminId: string,
  account: ReturnType<typeof mapAdmin>,
) {
  const methods = await enabledLoginFactors(adminId);
  if (!methods.length) return null;
  const requiredMethods = methods.includes("totp") ? ["totp"] : methods;
  return {
    factorRequired: true as const,
    challengeToken: await createLoginChallenge(adminId),
    methods: requiredMethods,
    admin: account,
  };
}

async function findLoginChallenge(token: string) {
  const { data, error } = await createServiceClient()
    .from("admin_auth_login_challenges")
    .select("id, admin_id, expires_at, consumed_at, attempts")
    .eq("challenge_hash", await hashChallenge(token))
    .maybeSingle();
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to verify login challenge",
      500,
    );
  }
  if (
    !data || data.consumed_at || data.attempts >= 5 ||
    Date.parse(data.expires_at) <= Date.now()
  ) {
    throw new AppError(
      "unauthorized",
      "Invalid or expired factor challenge",
      401,
    );
  }
  return data;
}

async function failLoginChallenge(
  challenge: { id: string; attempts: number },
): Promise<void> {
  const attempts = Number(challenge.attempts) + 1;
  const update: Record<string, unknown> = { attempts };
  if (attempts >= 5) update.consumed_at = new Date().toISOString();
  await createServiceClient().from("admin_auth_login_challenges")
    .update(update)
    .eq("id", challenge.id)
    .eq("attempts", challenge.attempts)
    .is("consumed_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("id")
    .maybeSingle();
}

async function consumeLoginChallenge(id: string): Promise<void> {
  const { data, error } = await createServiceClient()
    .from("admin_auth_login_challenges")
    .update({ consumed_at: new Date().toISOString() })
    .eq("id", id)
    .is("consumed_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("id")
    .maybeSingle();
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to complete factor verification",
      500,
    );
  }
  if (!data) {
    throw new AppError(
      "unauthorized",
      "Invalid or expired factor challenge",
      401,
    );
  }
}

async function consumeWebauthnChallenge(id: string, purpose: string) {
  const { data, error } = await createServiceClient()
    .from("admin_auth_webauthn_challenges")
    .update({ consumed_at: new Date().toISOString() })
    .eq("id", id)
    .eq("purpose", purpose)
    .is("consumed_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("id, admin_id, session_id, login_challenge_id")
    .maybeSingle();
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to complete passkey verification",
      500,
    );
  }
  if (!data) {
    throw new AppError(
      "unauthorized",
      "Invalid or expired passkey challenge",
      401,
    );
  }
  return data;
}

async function verifyPassword(
  req: Request,
  adminId: string,
  password: string,
): Promise<void> {
  const account = await loadAdminRow(adminId);
  const { data, error } = await createServiceClient().rpc(
    "admin_verify_credentials",
    {
      p_username: account.username,
      p_password: password,
    },
  );
  const row = Array.isArray(data) ? data[0] : data;
  if (error || row?.id !== adminId) {
    await recordLoginEvent(req, {
      identityKey: adminIdentityKey(adminId),
      adminId,
      method: "password",
      success: false,
      failureReason: "invalid_credentials",
    });
    throw new AppError("unauthorized", "Password confirmation failed", 401);
  }
  if (
    !await recordLoginEvent(req, {
      identityKey: adminIdentityKey(adminId),
      adminId,
      method: "password",
      success: true,
    })
  ) denyLocked();
}

async function startPasskeyLogin(req: Request, body: Record<string, unknown>) {
  const admin = createServiceClient();
  let adminId: string;
  let loginChallengeId: string | null = null;
  if (typeof body.challengeToken === "string" && body.challengeToken) {
    const challenge = await findLoginChallenge(body.challengeToken);
    adminId = challenge.admin_id;
    loginChallengeId = challenge.id;
    if ((await enabledLoginFactors(adminId)).includes("totp")) {
      throw new AppError("unauthorized", "TOTP verification is required", 401);
    }
  } else {
    const username = requireString(body, "username").toLowerCase();
    const { data, error } = await admin.from("admin_accounts")
      .select("id")
      .eq("username", username)
      .maybeSingle();
    if (error || !data) {
      await recordLoginEvent(req, {
        identityKey: await unknownIdentityKey(username),
        adminId: null,
        method: "passkey",
        success: false,
        failureReason: "invalid_passkey",
      });
      throw new AppError("unauthorized", "Passkey sign-in failed", 401);
    }
    adminId = data.id;
  }

  const { data: credentials, error: credentialError } = await admin
    .from("admin_passkeys")
    .select("credential_id, transports")
    .eq("admin_id", adminId);
  if (credentialError || !credentials?.length) {
    await recordLoginEvent(req, {
      identityKey: adminIdentityKey(adminId),
      adminId,
      method: "passkey",
      success: false,
      failureReason: "invalid_passkey",
    });
    throw new AppError("unauthorized", "Passkey sign-in failed", 401);
  }
  const config = webauthnConfig();
  const options = await generateAuthenticationOptions({
    rpID: config.rpID,
    allowCredentials: credentials.map((
      credential: { credential_id: string; transports: string[] },
    ) => ({
      id: credential.credential_id,
      transports: credentialTransports(credential.transports),
    })),
    userVerification: "required",
  });
  const { data: challenge, error } = await admin.from(
    "admin_auth_webauthn_challenges",
  )
    .insert({
      admin_id: adminId,
      purpose: "login",
      challenge: options.challenge,
      login_challenge_id: loginChallengeId,
      expires_at: expiry(),
    })
    .select("id")
    .single();
  if (error) {
    throw new AppError(
      "internal_error",
      "Unable to start passkey sign-in",
      500,
    );
  }
  return { challengeId: challenge.id, options };
}

Deno.serve(async (req) => {
  const cors = handleCors(req, "public");
  if (cors) return cors;
  try {
    const action = routeAction(req);
    const method = req.method.toUpperCase();
    const admin = createServiceClient();

    if (action === "bootstrap-status" && method === "GET") {
      const { data, error } = await admin.from("admin_accounts")
        .select("is_default_seed").eq("is_default_seed", false).limit(1);
      if (error) {
        throw new AppError(
          "internal_error",
          "Unable to check bootstrap status",
          500,
        );
      }
      return json(bootstrapStatus(data ?? []), 200, publicCorsHeaders);
    }

    if (action === "login" && method === "POST") {
      const body = await readJson(req);
      const username = String(body.username ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (!username || !password) {
        throw new AppError(
          "validation_error",
          "username and password are required",
          400,
        );
      }
      const { data: candidate, error: candidateError } = await admin
        .from("admin_accounts").select("id")
        .eq("username", username).maybeSingle();
      if (candidateError) {
        throw new AppError(
          "internal_error",
          "Credential verification failed",
          500,
        );
      }
      const identityKey = candidate?.id
        ? adminIdentityKey(candidate.id)
        : await unknownIdentityKey(username);
      if (
        isAdminProductionRuntime() &&
        isDefaultAdminCredentials(username, password)
      ) {
        await recordLoginEvent(req, {
          identityKey,
          adminId: candidate?.id ?? null,
          method: "password",
          success: false,
          failureReason: "invalid_credentials",
        });
        log("warn", "admin_default_credentials_blocked");
        throw new AppError(
          "forbidden",
          "Default admin credentials are disabled in production. Bootstrap an Owner password first.",
          403,
        );
      }
      const { data, error } = await admin.rpc("admin_verify_credentials", {
        p_username: username,
        p_password: password,
      });
      if (error) {
        log("error", "admin_verify_failed");
        throw new AppError(
          "internal_error",
          "Credential verification failed",
          500,
        );
      }
      const row = Array.isArray(data) ? data[0] : data;
      if (!row?.id) {
        await recordLoginEvent(req, {
          identityKey,
          adminId: candidate?.id ?? null,
          method: "password",
          success: false,
          failureReason: "invalid_credentials",
        });
        throw new AppError("unauthorized", "Invalid username or password", 401);
      }
      const account = await loadAdminRow(row.id as string);
      if (
        isAdminProductionRuntime() && account.is_default_seed &&
        isDefaultAdminCredentials(username, password)
      ) {
        await recordLoginEvent(req, {
          identityKey,
          adminId: account.id,
          method: "password",
          success: false,
          failureReason: "invalid_credentials",
        });
        throw new AppError(
          "forbidden",
          "Default seed account cannot sign in to production. Call /admin-auth/bootstrap.",
          403,
        );
      }
      const loginFactors = await enabledLoginFactors(account.id as string);
      if (
        !await recordLoginEvent(req, {
          identityKey,
          adminId: account.id,
          method: "password",
          success: true,
          resetFailures: loginFactors.length === 0,
        })
      ) denyLocked();
      const factorStep = await requireLoginFactor(
        account.id as string,
        mapAdmin(account),
      );
      if (factorStep) return json(factorStep, 200, publicCorsHeaders);
      const session = await createAdminSession(account.id as string);
      log("info", "admin_login_ok", {
        admin_id: account.id,
        role: account.role,
      });
      return json(
        {
          token: session.token,
          expiresAt: session.expiresAt,
          admin: mapAdmin(account),
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "login-totp" && method === "POST") {
      const body = await readJson(req);
      const challenge = await findLoginChallenge(
        requireString(body, "challengeToken"),
      );
      const { data: factor, error } = await admin.from("admin_auth_factors")
        .select(
          "admin_id, totp_secret_ciphertext, totp_last_counter, totp_enabled_at",
        )
        .eq("admin_id", challenge.admin_id)
        .maybeSingle();
      if (error || !factor?.totp_enabled_at || !factor.totp_secret_ciphertext) {
        await failLoginChallenge(challenge);
        await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "totp",
          success: false,
          failureReason: "invalid_totp",
        });
        throw new AppError("unauthorized", "TOTP sign-in failed", 401);
      }
      const key = Deno.env.get("ADMIN_AUTH_FACTOR_ENCRYPTION_KEY") ?? "";
      const secret = await decryptTotpSecret(
        factor.totp_secret_ciphertext,
        key,
      );
      const code = typeof body.code === "string" ? body.code.trim() : "";
      const counter = await matchingTotpCounter(
        secret,
        code,
        Date.now(),
        Number(factor.totp_last_counter),
      );
      if (counter === null) {
        await failLoginChallenge(challenge);
        await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "totp",
          success: false,
          failureReason: "invalid_totp",
        });
        throw new AppError("unauthorized", "TOTP sign-in failed", 401);
      }
      const counterUpdate = admin.from("admin_auth_factors")
        .update({
          totp_last_counter: counter,
          updated_at: new Date().toISOString(),
        })
        .eq("admin_id", challenge.admin_id)
        .lt("totp_last_counter", counter);
      const { data: updated, error: updateError } = await counterUpdate
        .select("admin_id")
        .maybeSingle();
      if (updateError || !updated) {
        throw new AppError("unauthorized", "TOTP sign-in failed", 401);
      }
      await consumeLoginChallenge(challenge.id);
      if (
        !await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "totp",
          success: true,
        })
      ) denyLocked();
      const session = await createAdminSession(challenge.admin_id);
      const account = await loadAdminRow(challenge.admin_id);
      return json(
        {
          token: session.token,
          expiresAt: session.expiresAt,
          admin: mapAdmin(account),
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "login-passkey-options" && method === "POST") {
      await createServiceClient().from("admin_auth_login_challenges").delete()
        .lt("expires_at", new Date().toISOString());
      await createServiceClient().from("admin_auth_webauthn_challenges")
        .delete().lt("expires_at", new Date().toISOString());
      return json(
        await startPasskeyLogin(req, await readJson(req)),
        200,
        publicCorsHeaders,
      );
    }

    if (action === "login-passkey-verify" && method === "POST") {
      const body = await readJson(req);
      const challengeId = requireString(body, "challengeId");
      const { data: challenge, error } = await admin.from(
        "admin_auth_webauthn_challenges",
      )
        .select(
          "id, admin_id, challenge, login_challenge_id, consumed_at, expires_at",
        )
        .eq("id", challengeId)
        .eq("purpose", "login")
        .maybeSingle();
      if (
        error || !challenge || challenge.consumed_at ||
        Date.parse(challenge.expires_at) <= Date.now()
      ) {
        await recordLoginEvent(req, {
          identityKey: challenge?.admin_id
            ? adminIdentityKey(challenge.admin_id)
            : null,
          adminId: challenge?.admin_id ?? null,
          method: "passkey",
          success: false,
          failureReason: "invalid_passkey",
        });
        throw new AppError("unauthorized", "Passkey sign-in failed", 401);
      }
      const response = body.response as { id?: unknown } | undefined;
      if (!response || typeof response.id !== "string") {
        throw new AppError("validation_error", "response is required", 400);
      }
      const { data: credential, error: credentialError } = await admin.from(
        "admin_passkeys",
      )
        .select("credential_id, public_key, sign_count, transports")
        .eq("credential_id", response.id)
        .eq("admin_id", challenge.admin_id)
        .maybeSingle();
      if (credentialError || !credential) {
        await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "passkey",
          success: false,
          failureReason: "invalid_passkey",
        });
        throw new AppError("unauthorized", "Passkey sign-in failed", 401);
      }
      const config = webauthnConfig();
      let verification;
      try {
        verification = await verifyAuthenticationResponse({
          response: body.response as never,
          expectedChallenge: challenge.challenge,
          expectedOrigin: config.origin,
          expectedRPID: config.rpID,
          requireUserVerification: true,
          credential: {
            id: credential.credential_id,
            publicKey: Uint8Array.from(
              atob(credential.public_key),
              (character) => character.charCodeAt(0),
            ),
            counter: Number(credential.sign_count),
            transports: credentialTransports(credential.transports),
          },
        });
      } catch {
        await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "passkey",
          success: false,
          failureReason: "invalid_passkey",
        });
        throw new AppError("unauthorized", "Passkey sign-in failed", 401);
      }
      if (!verification.verified) {
        await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "passkey",
          success: false,
          failureReason: "invalid_passkey",
        });
        throw new AppError("unauthorized", "Passkey sign-in failed", 401);
      }
      const consumed = await consumeWebauthnChallenge(challenge.id, "login");
      if (consumed.login_challenge_id) {
        await consumeLoginChallenge(consumed.login_challenge_id);
      }
      const { error: updateError } = await admin.from("admin_passkeys")
        .update({
          sign_count: verification.authenticationInfo.newCounter,
          last_used_at: new Date().toISOString(),
        })
        .eq("credential_id", credential.credential_id)
        .eq("admin_id", challenge.admin_id)
        .eq("sign_count", credential.sign_count);
      if (updateError) {
        throw new AppError(
          "internal_error",
          "Unable to update passkey state",
          500,
        );
      }
      if (
        !await recordLoginEvent(req, {
          identityKey: adminIdentityKey(challenge.admin_id),
          adminId: challenge.admin_id,
          method: "passkey",
          success: true,
        })
      ) denyLocked();
      const session = await createAdminSession(challenge.admin_id);
      const account = await loadAdminRow(challenge.admin_id);
      return json(
        {
          token: session.token,
          expiresAt: session.expiresAt,
          admin: mapAdmin(account),
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "bootstrap" && method === "POST") {
      return await withAdminBootstrapAuthorization(
        req,
        Deno.env.get("COOKAPP_ADMIN_BOOTSTRAP_TOKEN") ?? "",
        isAdminProductionRuntime(),
        async () => {
          const body = await readJson(req);
          const username = String(body.username ?? "admin").trim()
            .toLowerCase();
          const newPassword = String(body.newPassword ?? "");
          const currentPassword = body.currentPassword == null
            ? null
            : String(body.currentPassword);
          const strength = validateAdminPassword(newPassword);
          if (!strength.ok) {
            throw new AppError(
              "validation_error",
              strength.message ?? "Weak password",
              400,
            );
          }
          const { data, error } = await admin.rpc("admin_bootstrap_owner", {
            p_username: username,
            p_new_password: newPassword,
            p_current_password: currentPassword,
          });
          if (error) {
            const publicError = publicAdminBootstrapError(error.message ?? "");
            log("warn", "admin_bootstrap_failed", {
              code: publicError.code,
              status: publicError.status,
            });
            throw publicError;
          }
          const row = Array.isArray(data) ? data[0] : data;
          if (!row?.id) {
            throw new AppError(
              "internal_error",
              "Bootstrap returned no account",
              500,
            );
          }
          const account = await loadAdminRow(row.id as string);
          if (
            !await recordLoginEvent(req, {
              identityKey: adminIdentityKey(row.id as string),
              adminId: row.id as string,
              method: "bootstrap",
              success: true,
            })
          ) denyLocked();
          const factorStep = await requireLoginFactor(
            row.id as string,
            mapAdmin(account),
          );
          if (factorStep) return json(factorStep, 200, publicCorsHeaders);
          const session = await createAdminSession(row.id as string);
          log("info", "admin_bootstrap_ok", {
            admin_id: row.id,
            role: row.role,
          });
          return json(
            {
              token: session.token,
              expiresAt: session.expiresAt,
              admin: {
                id: row.id,
                username: row.username,
                role: parseAdminRole(row.role),
                mustChangePassword: false,
              },
            },
            200,
            publicCorsHeaders,
          );
        },
      );
    }

    if (action === "logout" && method === "POST") {
      const session = await requireAdminSession(req);
      const { error } = await admin.from("admin_sessions").update({
        revoked_at: new Date().toISOString(),
      }).eq("id", session.sessionId);
      if (error) {
        throw new AppError(
          "internal_error",
          "Failed to revoke admin session",
          500,
        );
      }
      log("info", "admin_logout_ok", { admin_id: session.adminId });
      return json({ ok: true }, 200, publicCorsHeaders);
    }

    if (action === "session" && method === "GET") {
      const session = await requireAdminSession(req);
      return json(
        { admin: mapAdmin(await loadAdminRow(session.adminId)) },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "change-password" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      const currentPassword = String(body.currentPassword ?? "");
      const newPassword = String(body.newPassword ?? "");
      if (!currentPassword || !newPassword) {
        throw new AppError(
          "validation_error",
          "currentPassword and newPassword are required",
          400,
        );
      }
      const strength = validateAdminPassword(newPassword);
      if (!strength.ok) {
        throw new AppError(
          "validation_error",
          strength.message ?? "Weak password",
          400,
        );
      }
      const { data, error } = await admin.rpc("admin_change_password", {
        p_admin_id: session.adminId,
        p_current_password: currentPassword,
        p_new_password: newPassword,
      });
      if (error) {
        log("error", "admin_change_password_failed");
        if ((error.message ?? "").includes("strength")) {
          throw new AppError(
            "validation_error",
            "newPassword does not meet strength policy",
            400,
          );
        }
        throw new AppError("internal_error", "Password change failed", 500);
      }
      if (!data) {
        throw new AppError(
          "unauthorized",
          "Current password is incorrect",
          401,
        );
      }
      const account = await loadAdminRow(session.adminId);
      const next = await createAdminSession(session.adminId);
      const { error: revokeError } = await admin.from("admin_sessions")
        .update({ revoked_at: new Date().toISOString() })
        .eq("admin_id", session.adminId)
        .is("revoked_at", null)
        .neq("token_hash", await sha256Hex(next.token));
      if (revokeError) {
        throw new AppError(
          "internal_error",
          "Password changed but prior sessions could not be revoked",
          500,
        );
      }
      return json(
        {
          ok: true,
          token: next.token,
          expiresAt: next.expiresAt,
          admin: mapAdmin(account),
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "factors" && method === "GET") {
      const session = await requireAdminSession(req);
      const [
        { data: factor, error: factorError },
        { data: passkeys, error: passkeyError },
      ] = await Promise.all([
        admin.from("admin_auth_factors").select("totp_enabled_at").eq(
          "admin_id",
          session.adminId,
        ).maybeSingle(),
        admin.from("admin_passkeys").select(
          "credential_id, name, created_at, last_used_at",
        ).eq("admin_id", session.adminId).order("created_at", {
          ascending: true,
        }),
      ]);
      if (factorError || passkeyError) {
        throw new AppError(
          "internal_error",
          "Unable to load security factors",
          500,
        );
      }
      return json(
        {
          totp: {
            enabled: Boolean(factor?.totp_enabled_at),
            enabledAt: factor?.totp_enabled_at ?? null,
          },
          passkeys: passkeys ?? [],
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "login-events" && method === "GET") {
      const session = await requireAdminSession(req);
      const requested = Number(
        new URL(req.url).searchParams.get("limit") ?? 50,
      );
      const limit = Number.isFinite(requested)
        ? Math.min(100, Math.max(1, Math.floor(requested)))
        : 50;
      const { data, error, count } = await admin.from("admin_auth_login_events")
        .select(
          "id, created_at, method, success, ip_address, user_agent, failure_reason",
          { count: "exact" },
        )
        .eq("admin_id", session.adminId)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) {
        throw new AppError(
          "internal_error",
          "Unable to load login history",
          500,
        );
      }
      return json(
        {
          data: (data ?? []).map((event) => ({
            id: event.id,
            createdAt: event.created_at,
            method: event.method,
            success: event.success,
            ipAddress: event.ip_address,
            userAgent: event.user_agent,
            failureReason: event.failure_reason,
          })),
          total: count ?? 0,
        },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "totp-setup" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      await verifyPassword(
        req,
        session.adminId,
        requireString(body, "currentPassword"),
      );
      const { data: current, error } = await admin.from("admin_auth_factors")
        .select("totp_enabled_at").eq("admin_id", session.adminId)
        .maybeSingle();
      if (error) {
        throw new AppError(
          "internal_error",
          "Unable to prepare TOTP setup",
          500,
        );
      }
      if (current?.totp_enabled_at) {
        throw new AppError(
          "conflict",
          "Remove the current TOTP factor before replacing it",
          409,
        );
      }
      const secret = newTotpSecret();
      const key = Deno.env.get("ADMIN_AUTH_FACTOR_ENCRYPTION_KEY") ?? "";
      let ciphertext: string;
      try {
        ciphertext = await encryptTotpSecret(secret, key);
      } catch {
        throw new AppError(
          "server_misconfigured",
          "TOTP encryption is unavailable",
          500,
        );
      }
      const { error: saveError } = await admin.from("admin_auth_factors")
        .upsert({
          admin_id: session.adminId,
          totp_secret_ciphertext: ciphertext,
          totp_enabled_at: null,
          totp_last_counter: -1,
          updated_at: new Date().toISOString(),
        }, { onConflict: "admin_id" });
      if (saveError) {
        throw new AppError(
          "internal_error",
          "Unable to prepare TOTP setup",
          500,
        );
      }
      const account = await loadAdminRow(session.adminId);
      const issuer = "RecipePouch Admin";
      const label = encodeURIComponent(`${issuer}:${account.username}`);
      const uri = `otpauth://totp/${label}?secret=${secret}&issuer=${
        encodeURIComponent(issuer)
      }&algorithm=SHA1&digits=6&period=30`;
      return json({ secret, otpauthUri: uri }, 200, publicCorsHeaders);
    }

    if (action === "totp-verify" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      const { data: factor, error } = await admin.from("admin_auth_factors")
        .select("totp_secret_ciphertext, totp_enabled_at")
        .eq("admin_id", session.adminId)
        .maybeSingle();
      if (error || !factor?.totp_secret_ciphertext || factor.totp_enabled_at) {
        throw new AppError(
          "conflict",
          "TOTP setup is not awaiting verification",
          409,
        );
      }
      let secret: string;
      try {
        secret = await decryptTotpSecret(
          factor.totp_secret_ciphertext,
          Deno.env.get("ADMIN_AUTH_FACTOR_ENCRYPTION_KEY") ?? "",
        );
      } catch {
        throw new AppError(
          "server_misconfigured",
          "TOTP encryption is unavailable",
          500,
        );
      }
      const counter = await matchingTotpCounter(
        secret,
        requireString(body, "code"),
      );
      if (counter === null) {
        throw new AppError("unauthorized", "TOTP code is invalid", 401);
      }
      const { data: updated, error: updateError } = await admin.from(
        "admin_auth_factors",
      )
        .update({
          totp_enabled_at: new Date().toISOString(),
          totp_last_counter: counter,
          updated_at: new Date().toISOString(),
        })
        .eq("admin_id", session.adminId)
        .is("totp_enabled_at", null)
        .eq("totp_secret_ciphertext", factor.totp_secret_ciphertext)
        .select("admin_id")
        .maybeSingle();
      if (updateError || !updated) {
        throw new AppError("conflict", "TOTP setup changed; start again", 409);
      }
      await revokeOtherAdminSessions(session.adminId, session.sessionId);
      return json({ enabled: true }, 200, publicCorsHeaders);
    }

    if (action === "totp-remove" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      await verifyPassword(
        req,
        session.adminId,
        requireString(body, "currentPassword"),
      );
      const { data: factor, error } = await admin.from("admin_auth_factors")
        .select(
          "admin_id, totp_secret_ciphertext, totp_enabled_at, totp_last_counter",
        )
        .eq("admin_id", session.adminId)
        .maybeSingle();
      if (error) {
        throw new AppError("internal_error", "Unable to remove TOTP", 500);
      }
      if (factor?.totp_enabled_at && factor.totp_secret_ciphertext) {
        const secret = await decryptTotpSecret(
          factor.totp_secret_ciphertext,
          Deno.env.get("ADMIN_AUTH_FACTOR_ENCRYPTION_KEY") ?? "",
        );
        const counter = await matchingTotpCounter(
          secret,
          requireString(body, "code"),
          Date.now(),
          Number(factor.totp_last_counter),
        );
        if (counter === null) {
          await recordLoginEvent(req, {
            identityKey: adminIdentityKey(session.adminId),
            adminId: session.adminId,
            method: "totp",
            success: false,
            failureReason: "invalid_totp",
          });
          throw new AppError("unauthorized", "TOTP confirmation failed", 401);
        }
      }
      const { error: removeError } = await admin.from("admin_auth_factors")
        .delete().eq("admin_id", session.adminId);
      if (removeError) {
        throw new AppError("internal_error", "Unable to remove TOTP", 500);
      }
      await revokeOtherAdminSessions(session.adminId, session.sessionId);
      return json({ removed: true }, 200, publicCorsHeaders);
    }

    if (action === "passkey-registration-options" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      await verifyPassword(
        req,
        session.adminId,
        requireString(body, "currentPassword"),
      );
      await admin.from("admin_auth_login_challenges").delete().lt(
        "expires_at",
        new Date().toISOString(),
      );
      await admin.from("admin_auth_webauthn_challenges").delete().lt(
        "expires_at",
        new Date().toISOString(),
      );
      const account = await loadAdminRow(session.adminId);
      const { data: existing, error } = await admin.from("admin_passkeys")
        .select("credential_id, transports").eq("admin_id", session.adminId);
      if (error) {
        throw new AppError("internal_error", "Unable to load passkeys", 500);
      }
      const config = webauthnConfig();
      const options = await generateRegistrationOptions({
        rpName: config.rpName,
        rpID: config.rpID,
        userID: new TextEncoder().encode(session.adminId),
        userName: account.username,
        attestationType: "none",
        excludeCredentials: (existing ?? []).map((
          credential: { credential_id: string; transports: string[] },
        ) => ({
          id: credential.credential_id,
          transports: credentialTransports(credential.transports),
        })),
        authenticatorSelection: {
          residentKey: "preferred",
          userVerification: "required",
        },
      });
      const { data: challenge, error: challengeError } = await admin.from(
        "admin_auth_webauthn_challenges",
      )
        .insert({
          admin_id: session.adminId,
          purpose: "register",
          challenge: options.challenge,
          session_id: session.sessionId,
          expires_at: expiry(),
        })
        .select("id")
        .single();
      if (challengeError) {
        throw new AppError(
          "internal_error",
          "Unable to start passkey setup",
          500,
        );
      }
      return json(
        { challengeId: challenge.id, options },
        200,
        publicCorsHeaders,
      );
    }

    if (action === "passkey-registration-verify" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      const challengeId = requireString(body, "challengeId");
      const { data: challenge, error } = await admin.from(
        "admin_auth_webauthn_challenges",
      )
        .select("id, admin_id, session_id, challenge, consumed_at, expires_at")
        .eq("id", challengeId)
        .eq("purpose", "register")
        .eq("admin_id", session.adminId)
        .eq("session_id", session.sessionId)
        .maybeSingle();
      if (
        error || !challenge || challenge.consumed_at ||
        Date.parse(challenge.expires_at) <= Date.now()
      ) {
        throw new AppError(
          "unauthorized",
          "Invalid or expired passkey challenge",
          401,
        );
      }
      const config = webauthnConfig();
      let verification;
      try {
        verification = await verifyRegistrationResponse({
          response: body.response as never,
          expectedChallenge: challenge.challenge,
          expectedOrigin: config.origin,
          expectedRPID: config.rpID,
          requireUserVerification: true,
        });
      } catch {
        throw new AppError("unauthorized", "Passkey registration failed", 401);
      }
      if (!verification.verified || !verification.registrationInfo) {
        throw new AppError("unauthorized", "Passkey registration failed", 401);
      }
      await consumeWebauthnChallenge(challenge.id, "register");
      const credential = verification.registrationInfo.credential;
      const transports = credentialTransports(
        (body.response as { response?: { transports?: unknown } })?.response
          ?.transports,
      );
      const name = typeof body.name === "string" && body.name.trim()
        ? body.name.trim().slice(0, 80)
        : "Passkey";
      const { error: saveError } = await admin.from("admin_passkeys").insert({
        credential_id: credential.id,
        admin_id: session.adminId,
        public_key: btoa(String.fromCharCode(...credential.publicKey)),
        sign_count: credential.counter,
        transports,
        name,
      });
      if (saveError) {
        throw new AppError(
          "conflict",
          "This passkey is already registered",
          409,
        );
      }
      await revokeOtherAdminSessions(session.adminId, session.sessionId);
      return json({ created: true }, 201, publicCorsHeaders);
    }

    if (action === "passkey-remove" && method === "POST") {
      const session = await requireAdminSession(req);
      const body = await readJson(req);
      await verifyPassword(
        req,
        session.adminId,
        requireString(body, "currentPassword"),
      );
      const credentialId = requireString(body, "credentialId");
      const { data, error } = await admin.from("admin_passkeys").delete()
        .eq("credential_id", credentialId)
        .eq("admin_id", session.adminId)
        .select("credential_id")
        .maybeSingle();
      if (error) {
        throw new AppError("internal_error", "Unable to remove passkey", 500);
      }
      if (!data) throw new AppError("not_found", "Passkey not found", 404);
      await revokeOtherAdminSessions(session.adminId, session.sessionId);
      return json({ removed: true }, 200, publicCorsHeaders);
    }

    throw new AppError(
      "not_found",
      `Unknown admin-auth route: ${method} ${action || "/"}`,
      404,
    );
  } catch (err) {
    return errorResponse(err, publicCorsHeaders);
  }
});
