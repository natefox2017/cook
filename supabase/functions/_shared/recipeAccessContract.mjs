// Developer: Recipe Pals
// Purpose: DEV-425 shared validated commercial access/usage contract. Never trust a client success flag or quota field.

export function isRecord(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function exactly(v, keys) {
  return isRecord(v) && Object.keys(v).length === keys.length &&
    Object.keys(v).every((key) => keys.includes(key));
}

// Canonical lowercase RFC UUID text; uppercase is rejected to match the Swift decoder.
export function isUUID(v) {
  return typeof v === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
}

export function isHash(v) {
  return typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
}

export function utcTimestamp(v) {
  if (typeof v !== "string" ||
    !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(v)) return null;
  const d = new Date(v);
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 19) === v.slice(0, 19)
    ? d.toISOString() : null;
}

export const CAPABILITIES = new Set([
  "smart_import", "ai_edit", "hands_free_cooking", "weekly_templates",
  "weekly_groceries", "auto_plan", "recipe_question", "recipe_translation",
  "media_import", "pdf_export",
]);

export const RELEASE_STAGES = new Set(["freeTest", "commercial"]);
export const ENTITLEMENT_STATUSES = new Set(["free", "premium", "expired"]);
export const PERIOD_TYPES = new Set(["iso_week", "utc_month", "lifetime"]);
export const UNITS = new Set([
  "successful_imports", "successful_edits", "successful_answers",
  "successful_translations", "media_tasks",
]);
export const TIERS = new Set(["free", "premium"]);
export const RESERVATION_STATUSES = new Set([
  "reserved", "dispatched_unknown", "committed", "released", "expired",
]);
export const ORIGINS = new Set(["import_job", "draft_approval"]);

// Counts above this are rejected so Swift and TypeScript agree on representable integers.
export const SAFE_INTEGER_MAX = 9007199254740991;

// Versioned server-owned policy defaults. Clients never author remaining/limit values.
export const POLICY = {
  schemaVersion: 1,
  reservationTTLSeconds: 600,
  proposalHoldSeconds: 86400,
  quotas: {
    smart_import: { units: "successful_imports", free: { limit: 5, period: "iso_week" }, premium: { limit: 100, period: "utc_month" } },
    ai_edit: { units: "successful_edits", free: { limit: 3, period: "lifetime" }, premium: { limit: 30, period: "utc_month" } },
    recipe_question: { units: "successful_answers", premium: { limit: 100, period: "utc_month" } },
    recipe_translation: { units: "successful_translations", premium: { limit: 20, period: "utc_month" } },
    media_import: { units: "media_tasks", premium: { limit: 20, period: "utc_month" } },
  },
};

function capability(v) {
  return typeof v === "string" && CAPABILITIES.has(v) ? v : null;
}

function uuids(values, minimum) {
  return Array.isArray(values) && values.length >= minimum && values.length <= 60 &&
    new Set(values).size === values.length && values.every(isUUID);
}

// The persisted origin a usage operation settles against; nulls mark the fields that do not apply.
export function usageSource(v) {
  const keys = ["origin", "job_id", "candidate_ids", "session_id", "turn_request_id"];
  if (!exactly(v, keys) || !ORIGINS.has(v.origin)) return null;
  if (v.origin === "import_job") {
    if (!isUUID(v.job_id) || v.session_id !== null || v.turn_request_id !== null) return null;
    if (!uuids(v.candidate_ids, 1)) return null;
    return {origin: v.origin, job_id: v.job_id, candidate_ids: v.candidate_ids, session_id: null, turn_request_id: null};
  }
  if (v.job_id !== null || v.candidate_ids !== null) return null;
  if (!isUUID(v.session_id) || !isUUID(v.turn_request_id)) return null;
  return {origin: v.origin, job_id: null, candidate_ids: null, session_id: v.session_id, turn_request_id: v.turn_request_id};
}

function nonNegative(v) {
  return Number.isSafeInteger(v) && v >= 0 && v <= SAFE_INTEGER_MAX;
}

function positive(v) {
  return Number.isSafeInteger(v) && v >= 1 && v <= SAFE_INTEGER_MAX;
}

export function quota(v) {
  const keys = ["units", "period_type", "period_start", "reset_at", "limit", "used", "reserved", "remaining"];
  if (!exactly(v, keys) || !UNITS.has(v.units) || !PERIOD_TYPES.has(v.period_type)) return null;
  if (!nonNegative(v.limit) || !nonNegative(v.used) || !nonNegative(v.reserved) || !nonNegative(v.remaining)) return null;
  // A downgraded owner can carry used > limit (observed counters) with remaining clamped to zero.
  if (v.remaining !== Math.max(0, v.limit - v.used - v.reserved)) return null;
  let periodStart = v.period_start;
  let resetAt = v.reset_at;
  if (v.period_type === "lifetime") {
    if (periodStart !== null || resetAt !== null) return null;
  } else {
    const start = utcTimestamp(periodStart);
    const reset = utcTimestamp(resetAt);
    if (!start || !reset || new Date(reset).getTime() <= new Date(start).getTime()) return null;
    periodStart = start;
    resetAt = reset;
  }
  return {
    units: v.units, period_type: v.period_type, period_start: periodStart,
    reset_at: resetAt, limit: v.limit, used: v.used, reserved: v.reserved, remaining: v.remaining,
  };
}

function capabilityAccess(v) {
  if (!exactly(v, ["id", "entitled", "quota"])) return null;
  const id = capability(v.id);
  if (!id || typeof v.entitled !== "boolean") return null;
  let q = null;
  if (v.quota !== null) {
    q = quota(v.quota);
    if (!q) return null;
  }
  return {id, entitled: v.entitled, quota: q};
}

function entitlement(v) {
  if (!exactly(v, ["status", "valid_until"]) || !ENTITLEMENT_STATUSES.has(v.status)) return null;
  if (v.status === "free" && v.valid_until !== null) return null;
  let validUntil = null;
  if (v.valid_until !== null) {
    const until = utcTimestamp(v.valid_until);
    if (!until) return null;
    validUntil = until;
  }
  return {status: v.status, valid_until: validUntil};
}

export function accessResponse(v) {
  const keys = ["owner_id", "server_time", "policy_version", "stage", "entitlement", "capabilities"];
  if (!exactly(v, keys) || !isUUID(v.owner_id)) return null;
  const serverTime = utcTimestamp(v.server_time);
  if (!serverTime || !positive(v.policy_version) || !RELEASE_STAGES.has(v.stage)) return null;
  const ent = entitlement(v.entitlement);
  if (!ent) return null;
  if (!Array.isArray(v.capabilities) || v.capabilities.length < 1 || v.capabilities.length > 10) return null;
  const capabilities = v.capabilities.map(capabilityAccess);
  if (capabilities.some((c) => c === null)) return null;
  if (new Set(capabilities.map((c) => c.id)).size !== capabilities.length) return null;
  return {
    owner_id: v.owner_id, server_time: serverTime, policy_version: v.policy_version,
    stage: v.stage, entitlement: ent, capabilities,
  };
}

export function reservationRequest(v) {
  const keys = ["operation_id", "capability", "input_hash", "estimated_units", "source"];
  if (!exactly(v, keys) || !isUUID(v.operation_id) || !isHash(v.input_hash)) return null;
  const id = capability(v.capability);
  if (!id || !positive(v.estimated_units)) return null;
  const source = usageSource(v.source);
  if (!source) return null;
  if (source.origin === "import_job") {
    if (source.candidate_ids.length !== v.estimated_units) return null;
  } else if (v.estimated_units !== 1) {
    return null;
  }
  return {
    operation_id: v.operation_id, capability: id,
    input_hash: v.input_hash, estimated_units: v.estimated_units, source,
  };
}

export function reservation(v) {
  const keys = ["operation_id", "owner_id", "capability", "period_start", "policy_version", "tier_at_reserve", "reserved_units", "status", "reserved_until"];
  if (!exactly(v, keys) || !isUUID(v.operation_id) || !isUUID(v.owner_id)) return null;
  const id = capability(v.capability);
  if (!id || !positive(v.policy_version) || !TIERS.has(v.tier_at_reserve)) return null;
  if (!positive(v.reserved_units) || !RESERVATION_STATUSES.has(v.status)) return null;
  const reservedUntil = utcTimestamp(v.reserved_until);
  if (!reservedUntil) return null;
  let periodStart = null;
  if (v.period_start !== null) {
    periodStart = utcTimestamp(v.period_start);
    if (!periodStart) return null;
  }
  return {
    operation_id: v.operation_id, owner_id: v.owner_id,
    capability: id, period_start: periodStart, policy_version: v.policy_version,
    tier_at_reserve: v.tier_at_reserve, reserved_units: v.reserved_units,
    status: v.status, reserved_until: reservedUntil,
  };
}

export function commitRequest(v) {
  if (!exactly(v, ["capability", "input_hash", "source"]) || !isHash(v.input_hash)) return null;
  const id = capability(v.capability);
  if (!id) return null;
  const source = usageSource(v.source);
  if (!source) return null;
  if (source.origin === "import_job" && source.candidate_ids.length !== 1) return null;
  return {capability: id, input_hash: v.input_hash, source};
}

export function commitResponse(v) {
  const keys = ["operation_id", "status", "committed_units", "period_start"];
  if (!exactly(v, keys) || !isUUID(v.operation_id) || v.status !== "committed") return null;
  if (!positive(v.committed_units)) return null;
  let periodStart = null;
  if (v.period_start !== null) {
    periodStart = utcTimestamp(v.period_start);
    if (!periodStart) return null;
  }
  return {
    operation_id: v.operation_id, status: v.status,
    committed_units: v.committed_units, period_start: periodStart,
  };
}

export function finalizeRequest(v) {
  return commitRequest(v);
}

export function finalizeResponse(v) {
  const keys = ["operation_id", "status", "recipe_id", "payload_hash", "committed_units", "period_start"];
  if (!exactly(v, keys) || !isUUID(v.operation_id) || v.status !== "finalized") return null;
  if (!isUUID(v.recipe_id) || !isHash(v.payload_hash) || !positive(v.committed_units)) return null;
  let periodStart = null;
  if (v.period_start !== null) {
    periodStart = utcTimestamp(v.period_start);
    if (!periodStart) return null;
  }
  return {
    operation_id: v.operation_id, status: v.status,
    recipe_id: v.recipe_id, payload_hash: v.payload_hash,
    committed_units: v.committed_units, period_start: periodStart,
  };
}

export function ackResponse(v) {
  if (!exactly(v, ["operation_id", "status"]) || !isUUID(v.operation_id) || v.status !== "acked") return null;
  return {operation_id: v.operation_id, status: v.status};
}

export const ERROR_STATUSES = {
  AUTH_REQUIRED: 401, OWNER_MISMATCH: 403, NOT_FOUND: 404,
  IDEMPOTENCY_CONFLICT: 409, RESERVATION_EXPIRED: 409,
  INVALID_INPUT: 422, QUOTA_EXCEEDED: 402, UPGRADE_REQUIRED: 402,
  CONFIGURATION_UNAVAILABLE: 503, SERVICE_UNAVAILABLE: 503,
  INTERNAL_ERROR: 500,
};

export function usageError(v) {
  if (!exactly(v, ["code", "message", "recoverable", "request_id"])) return null;
  if (!(v.code in ERROR_STATUSES) || typeof v.recoverable !== "boolean" || !isUUID(v.request_id)) return null;
  if (typeof v.message !== "string" || !v.message.trim() || v.message.length > 300) return null;
  return {
    code: v.code, message: v.message, recoverable: v.recoverable, request_id: v.request_id,
  };
}
