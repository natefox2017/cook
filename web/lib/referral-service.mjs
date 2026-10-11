// Developer: gengyun
// Purpose: Enforces disabled-by-default referral orchestration over trusted atomic storage.
import {
  ReferralValidationError,
  isValidAccountID,
  isValidShareToken,
  isValidReferralCode,
  validateAggregateShareEvent,
  proposeExplicitInvitationClaim
} from './referrals.mjs';

/**
 * Server-only boundary; identity and lookups must never come from request bodies.
 * Adapter methods must check active state and expiry inside their atomic writes:
 * recordEventOnce({shareID,eventID,kind,now,expiresAt,quota}) returns recorded/replayed,
 * or throws event_conflict/quota_exceeded/unavailable. It atomically enforces the
 * (shareID,eventID) unique key and per-share quota of unexpired retained events,
 * including concurrent requests. Replay does not extend retention or count twice.
 * claimInvitationOnce({inviteeID,inviterID,code,consentVersion,now}) returns a claim,
 * atomically enforcing one invitee binding, same-claim replay and different-inviter
 * conflict. It must recheck code/account validity after any lookup-to-write race.
 * getOwnAggregate must filter by both ownerID and shareID, never expose recipients.
 * Retention, cleanup and account-delete handling remain storage requirements.
 * In-memory adapter tests do not demonstrate database atomicity or RLS.
 */
export function createReferralService(config, storage) {
  function requireConfiguration() {
    if (config?.enabled !== true) throw new ReferralValidationError('disabled');
    if (!Number.isSafeInteger(config.retentionSeconds) || config.retentionSeconds <= 0 ||
        !Number.isSafeInteger(config.eventQuota) || config.eventQuota <= 0 ||
        typeof config.consentVersion !== 'string' || !config.consentVersion.trim()) {
      throw new ReferralValidationError('configuration_required');
    }
  }

  function active(record, now) {
    return record && record.active === true &&
      Number.isFinite(record.expiresAt) && record.expiresAt > now;
  }

  function timestamp(now) {
    if (!Number.isSafeInteger(now) || now < 0) {
      throw new ReferralValidationError('invalid_server_time');
    }
    return now;
  }

  return {
    async recordEvent(payload, now) {
      requireConfiguration();
      timestamp(now);
      const event = validateAggregateShareEvent(payload);
      const share = await storage.findShare(event.shareToken);
      if (!active(share, now)) throw new ReferralValidationError('unavailable');
      const expiresAt = now + config.retentionSeconds * 1000;
      if (!Number.isSafeInteger(expiresAt)) {
        throw new ReferralValidationError('configuration_required');
      }
      const result = await storage.recordEventOnce({
        shareID: share.id, eventID: event.eventID, kind: event.kind,
        now, expiresAt, quota: config.eventQuota
      });
      if (!['recorded', 'replayed'].includes(result)) {
        throw new ReferralValidationError('invalid_storage_result');
      }
      return { status: result };
    },

    async readOwnAggregate(authenticatedOwnerID, shareToken, now) {
      requireConfiguration();
      timestamp(now);
      if (!isValidAccountID(authenticatedOwnerID)) {
        throw new ReferralValidationError('server_identity_required');
      }
      if (!isValidShareToken(shareToken)) throw new ReferralValidationError('bad_event');
      const ownerID = authenticatedOwnerID.toLowerCase();
      const share = await storage.findShare(shareToken);
      if (!active(share, now) || !isValidAccountID(share.ownerID) ||
          share.ownerID.toLowerCase() !== ownerID) {
        throw new ReferralValidationError('unavailable');
      }
      const counts = await storage.getOwnAggregate(ownerID, share.id, now);
      // Return a fixed shape; never forward adapter rows or recipient identities.
      const result = {};
      for (const kind of ['share_page_view', 'app_store_cta_click', 'copy_link']) {
        const count = counts?.[kind];
        if (!Number.isSafeInteger(count) || count < 0) {
          throw new ReferralValidationError('invalid_storage_result');
        }
        result[kind] = count;
      }
      return result;
    },

    async claimInvitation(payload, authenticatedInviteeID, now) {
      requireConfiguration();
      timestamp(now);
      if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
          Object.keys(payload).some(key => !['code', 'confirmed', 'consentVersion'].includes(key))) {
        throw new ReferralValidationError('unexpected_field');
      }
      if (payload.confirmed !== true || payload.consentVersion !== config.consentVersion) {
        throw new ReferralValidationError('consent_required');
      }
      if (!isValidAccountID(authenticatedInviteeID)) {
        throw new ReferralValidationError('server_identity_required');
      }
      if (!isValidReferralCode(payload.code)) {
        throw new ReferralValidationError('invalid_or_unverified_code');
      }
      const code = await storage.findInvitationCode(payload.code);
      if (!active(code, now)) throw new ReferralValidationError('unavailable');
      const proposal = proposeExplicitInvitationClaim({
        authenticatedInviteeID, lookedUpInviterID: code.inviterID,
        lookedUpInviteCode: code.code, submittedCode: payload.code,
        confirmedByInvitee: true, existingInvitationClaim: false
      });
      // Existing claims are checked atomically by storage, not via a stale pre-read.
      const saved = await storage.claimInvitationOnce({
        inviteeID: proposal.inviteeID, inviterID: proposal.inviterID,
        code: proposal.code, consentVersion: payload.consentVersion, now
      });
      if (saved?.inviteeID !== proposal.inviteeID ||
          saved?.inviterID !== proposal.inviterID || saved?.code !== proposal.code) {
        throw new ReferralValidationError('invalid_storage_result');
      }
      return { status: 'pending_review' };
    }
  };
}
