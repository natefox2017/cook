// Pure first-party attribution boundaries. No cookies, fingerprinting, payments or network calls.
const SHARE_TOKEN = /^[A-Za-z0-9_-]{8,128}$/;
const REFERRAL_CODE = /^[A-Za-z0-9_-]{16,64}$/;
const EVENT_ID = /^[A-Za-z0-9_-]{16,64}$/;
const KINDS = new Set(["share_page_view", "app_store_cta_click", "copy_link"]);

export class ReferralValidationError extends Error {
  constructor(code) { super(code); this.code = code; }
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
  if (!KINDS.has(payload.kind) || typeof payload.shareToken !== "string" ||
    !SHARE_TOKEN.test(payload.shareToken) || typeof payload.eventID !== "string" ||
    !EVENT_ID.test(payload.eventID)) {
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
  if (!confirmedByInvitee) {
    throw new ReferralValidationError("consent_required");
  }
  const ids = [authenticatedInviteeID, lookedUpInviterID];
  if (ids.some(id => typeof id !== "string" ||
    !/^[a-f0-9-]{36}$/i.test(id))) {
    throw new ReferralValidationError("server_identity_required");
  }
  if (!REFERRAL_CODE.test(submittedCode || "") ||
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
    inviteeID: authenticatedInviteeID,
    inviterID: lookedUpInviterID,
    code: submittedCode,
    status: "pending_review"
  };
}
