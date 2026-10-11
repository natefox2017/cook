// Pure first-party attribution boundaries. No cookies, fingerprinting, payments or network calls.
const SHARE_TOKEN = /^[A-Za-z0-9_-]{8,128}$/;
const REFERRAL_CODE = /^[A-Za-z0-9_-]{16,64}$/;
const EVENT_ID = /^[A-Za-z0-9_-]{16,64}$/;
const ACCOUNT_UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const NIL_UUID = "00000000-0000-0000-0000-000000000000";
const KINDS = new Set(["share_page_view", "app_store_cta_click", "copy_link"]);

export class ReferralValidationError extends Error {
  constructor(code) { super(code); this.code = code; }
}

export function isValidAccountID(value) {
  // Identity must be a canonical UUID; the nil UUID is never a real account.
  return typeof value === "string" && value.length === 36 &&
    ACCOUNT_UUID.test(value) &&
    value.toLowerCase() !== NIL_UUID;
}

export function isValidShareToken(value) {
  return typeof value === "string" && value.trim() === value &&
    value.length >= 8 && value.length <= 128 && SHARE_TOKEN.test(value);
}

export function isValidReferralCode(value) {
  return typeof value === "string" && value.trim() === value &&
    value.length >= 16 && value.length <= 64 && REFERRAL_CODE.test(value);
}

/**
 * Validate a single anonymous first-party event without accepting IP addresses,
 * emails, device IDs, user agents, or any caller-defined keys.
 *
 * Storage layer must still enforce consent/retention, rate limits, bot filtering
 * and event-idempotent aggregate counting. This module does not track installs.
 */
export function validateAggregateShareEvent(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new ReferralValidationError("bad_event");
  }
  const keys = Object.keys(payload);
  if (keys.some(key => !["kind", "shareToken", "eventID"].includes(key))) {
    throw new ReferralValidationError("unexpected_field");
  }
  if (!KINDS.has(payload.kind) || !isValidShareToken(payload.shareToken) || typeof payload.eventID !== "string" ||
    payload.eventID.trim() !== payload.eventID || !EVENT_ID.test(payload.eventID)) {
    throw new ReferralValidationError("bad_event");
  }
  // Safe aggregation input: no IP/UA/referrer/user-id fields or cookies.
  return {
    kind: payload.kind,
    shareToken: payload.shareToken,
    eventID: payload.eventID
  };
}

/**
 * An authenticated server should provide account IDs and its own lookup of a
 * previously issued, unexpired referral code. Client-reported ownership is never
 * sufficient proof, and the result is merely a pending claim, NOT a reward.
 */
export function proposeExplicitInvitationClaim({
  authenticatedInviteeID,
  lookedUpInviterID,
  lookedUpInviteCode,
  submittedCode,
  confirmedByInvitee,
  existingInvitationClaim
}) {
  if (confirmedByInvitee !== true) {
    throw new ReferralValidationError("consent_required");
  }
  if (!isValidAccountID(authenticatedInviteeID) ||
    !isValidAccountID(lookedUpInviterID)) {
    throw new ReferralValidationError("server_identity_required");
  }
  if (!isValidReferralCode(submittedCode) ||
    submittedCode !== lookedUpInviteCode) {
    throw new ReferralValidationError("invalid_or_unverified_code");
  }
  if (authenticatedInviteeID.toLowerCase() === lookedUpInviterID.toLowerCase()) {
    throw new ReferralValidationError("self_invitation");
  }
  if (existingInvitationClaim) {
    throw new ReferralValidationError("already_claimed");
  }
  return {
    inviteeID: authenticatedInviteeID.toLowerCase(),
    inviterID: lookedUpInviterID.toLowerCase(),
    code: submittedCode,
    status: "pending_review"
  };
}
