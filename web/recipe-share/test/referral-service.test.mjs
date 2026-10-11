// Developer: gengyun
// Purpose: Exercises referral orchestration with synthetic atomic adapter behavior.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createReferralService } from '../src/referral-service.mjs';
const A = 'c7f04da2-8191-49b4-9a1a-e36d7c72d111';
const B = '8a0c335d-60de-4383-ac43-ebfbcbb5ab01';
const C = 'f20b335d-60de-4383-ac43-ebfbcbb5ab02';
const now = 1000;
const code = 'AbCdEfGhIJKL01234567';
const event = {kind: 'share_page_view', shareToken: 'abc12345EFGH', eventID: 'evt98765432101234'};
const consent = {code, confirmed: true, consentVersion: 'v1'};
const config = {enabled: true, retentionSeconds: 60, eventQuota: 2, consentVersion: 'v1'};
function fixture(overrides = {}) {
  const events = new Map();
  const claims = new Map();
  let writes = 0;
  const share = {id: 'share', ownerID: A, active: true, expiresAt: 100000};
  const invitation = {code, inviterID: A, active: true, expiresAt: 100000};
  const storage = {
    async findShare(token) {return token === event.shareToken ? share : null;},
    async recordEventOnce(input) {
      if (!share.active || share.expiresAt <= input.now) throw Error('unavailable');
      for (const [key, row] of events) if (row.expiresAt <= input.now) events.delete(key);
      const old = events.get(input.eventID);
      if (old) {
        if (old.kind !== input.kind) throw Error('event_conflict');
        return 'replayed';
      }
      if (events.size >= input.quota) throw Error('quota_exceeded');
      events.set(input.eventID, input);
      writes++;
      return 'recorded';
    },
    async getOwnAggregate(ownerID, shareID, time) {
      assert.equal(ownerID, A);
      assert.equal(shareID, share.id);
      const result = {share_page_view: 0, app_store_cta_click: 0, copy_link: 0};
      for (const row of events.values()) if (row.expiresAt > time) result[row.kind]++;
      return {...result, inviteeID: B};
    },
    async findInvitationCode(value) {return value === code ? invitation : null;},
    async claimInvitationOnce(input) {
      if (!invitation.active || invitation.expiresAt <= input.now) throw Error('unavailable');
      const old = claims.get(input.inviteeID);
      if (old) {
        if (old.inviterID !== input.inviterID || old.code !== input.code) throw Error('already_claimed');
        return old;
      }
      claims.set(input.inviteeID, input);
      writes++;
      return input;
    },
    ...overrides
  };
  return {storage, events, claims, share, invitation, get writes() {return writes;}};
}
const rejects = (promise, message) => assert.rejects(promise, new RegExp(message));
test('disabled and missing configuration produce no storage calls', async () => {
  for (const candidate of [{}, {...config, enabled: false}, {...config, retentionSeconds: 0}, {...config, eventQuota: null}, {...config, consentVersion: ''}]) {
    const service = createReferralService(candidate, new Proxy({}, {get() {throw Error('storage touched');}}));
    const error = candidate.enabled === true ? 'configuration_required' : 'disabled';
    await rejects(service.recordEvent(event, now), error);
    await rejects(service.readOwnAggregate(A, event.shareToken, now), error);
    await rejects(service.claimInvitation(consent, B, now), error);
  }
});
test('active event replay is counted once and payload conflicts fail', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  assert.deepEqual(await s.recordEvent(event, now), {status: 'recorded'});
  assert.deepEqual(await s.recordEvent(event, now), {status: 'replayed'});
  await rejects(s.recordEvent({...event, kind: 'copy_link'}, now), 'event_conflict');
  assert.equal(f.writes, 1);
  assert.deepEqual(await s.readOwnAggregate(A, event.shareToken, now), {share_page_view: 1, app_store_cta_click: 0, copy_link: 0});
});
test('share quota limits event writes and expiry bounds aggregation', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  await s.recordEvent(event, now);
  await s.recordEvent({...event, eventID: 'evt98765432101235'}, now);
  await rejects(s.recordEvent({...event, eventID: 'evt98765432101236'}, now), 'quota_exceeded');
  assert.equal(f.writes, 2);
  assert.equal((await s.readOwnAggregate(A, event.shareToken, 61000)).share_page_view, 0);
});
test('unknown revoked and expired shares reject event and owner reads', async () => {
  for (const state of [{active: false}, {expiresAt: now}]) {
    const f = fixture(); Object.assign(f.share, state); const s = createReferralService(config, f.storage);
    await rejects(s.recordEvent(event, now), 'unavailable');
    await rejects(s.readOwnAggregate(A, event.shareToken, now), 'unavailable');
    assert.equal(f.writes, 0);
  }
  const f = fixture(); const s = createReferralService(config, f.storage);
  await rejects(s.recordEvent({...event, shareToken: 'unknownabcdefgh'}, now), 'unavailable');
  await rejects(s.readOwnAggregate(B, event.shareToken, now), 'unavailable');
  await rejects(s.readOwnAggregate(null, event.shareToken, now), 'server_identity_required');
});
test('existing validators still reject identity fields and fake installed events', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  await rejects(s.recordEvent({...event, ip: '127.0.0.1'}, now), 'unexpected_field');
  await rejects(s.recordEvent({...event, kind: 'installed'}, now), 'bad_event');
  assert.equal(f.writes, 0);
});
test('claim requires explicit current consent and trusted identity', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  for (const payload of [{...consent, confirmed: 'true'}, {...consent, confirmed: false}, {...consent, consentVersion: 'old'}]) await rejects(s.claimInvitation(payload, B, now), 'consent_required');
  await rejects(s.claimInvitation({...consent, inviterID: A}, B, now), 'unexpected_field');
  await rejects(s.claimInvitation(consent, 'invalid', now), 'server_identity_required');
  await rejects(s.claimInvitation(consent, A, now), 'self_invitation');
  assert.equal(f.writes, 0);
});
test('expired revoked and unknown codes cannot claim', async () => {
  for (const state of [{active: false}, {expiresAt: now}]) {
    const f = fixture(); Object.assign(f.invitation, state); const s = createReferralService(config, f.storage);
    await rejects(s.claimInvitation(consent, B, now), 'unavailable'); assert.equal(f.writes, 0);
  }
  const f = fixture(); const s = createReferralService(config, f.storage);
  await rejects(s.claimInvitation({...consent, code: 'unknownabcdefghij'}, B, now), 'unavailable');
});
test('claim replay is stable and a different inviter conflicts', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  assert.deepEqual(await s.claimInvitation(consent, B, now), {status: 'pending_review'});
  assert.deepEqual(await s.claimInvitation(consent, B, now), {status: 'pending_review'});
  assert.equal(f.writes, 1); f.invitation.inviterID = C;
  await rejects(s.claimInvitation(consent, B, now), 'already_claimed'); assert.equal(f.writes, 1);
});
test('adapter failure never becomes success or exposes adapter rows', async () => {
  const f = fixture({async recordEventOnce() {throw Error('storage_failed');}, async claimInvitationOnce() {throw Error('storage_failed');}});
  const s = createReferralService(config, f.storage);
  await rejects(s.recordEvent(event, now), 'storage_failed');
  await rejects(s.claimInvitation(consent, B, now), 'storage_failed');
  f.storage.getOwnAggregate = async () => ({share_page_view: -1});
  await rejects(s.readOwnAggregate(A, event.shareToken, now), 'invalid_storage_result');
});
test('server timestamps must be valid and retention cannot overflow', async () => {
  const f = fixture(); const s = createReferralService(config, f.storage);
  await rejects(s.recordEvent(event, NaN), 'invalid_server_time');
  await rejects(s.claimInvitation(consent, B, -1), 'invalid_server_time');
  await rejects(createReferralService({...config, retentionSeconds: Number.MAX_SAFE_INTEGER}, f.storage).recordEvent(event, now), 'configuration_required');
});

test('a missing persisted claim or invalid event result is not acknowledged', async () => {
  const f = fixture({async claimInvitationOnce() {return null;}, async recordEventOnce() {return 'unknown';}});
  const s = createReferralService(config, f.storage);
  await rejects(s.claimInvitation(consent, B, now), 'invalid_storage_result');
  await rejects(s.recordEvent(event, now), 'invalid_storage_result');
});
test('adapter must recheck revocation between lookup and write', async () => {
  const f = fixture();
  const findShare = f.storage.findShare;
  f.storage.findShare = async token => {
    const lookedUp = {...await findShare(token)};
    f.share.active = false;
    return lookedUp;
  };
  const s = createReferralService(config, f.storage);
  await rejects(s.recordEvent(event, now), 'unavailable');
  const findCode = f.storage.findInvitationCode;
  f.storage.findInvitationCode = async value => {
    const lookedUp = {...await findCode(value)};
    f.invitation.active = false;
    return lookedUp;
  };
  await rejects(s.claimInvitation(consent, B, now), 'unavailable');
  assert.equal(f.writes, 0);
});
test('malformed lookup inputs never access storage', async () => {
  const storage = new Proxy({}, {get() {throw Error('storage touched');}});
  const s = createReferralService(config, storage);
  const badIDs = [null, '', 'not-a-uuid', '00000000-0000-0000-0000-000000000000', 'x'.repeat(1000000)];
  for (const id of badIDs) {
    await rejects(s.claimInvitation(consent, id, now), 'server_identity_required');
    await rejects(s.readOwnAggregate(id, event.shareToken, now), 'server_identity_required');
  }
  for (const value of [null, 1, {}, '', 'short', 'x'.repeat(65), 'x'.repeat(1000000)]) {
    await rejects(s.claimInvitation({...consent, code: value}, B, now), 'invalid_or_unverified_code');
  }
  for (const token of [null, 1, {}, '', 'short', 'x'.repeat(129), 'x'.repeat(1000000)]) {
    await rejects(s.readOwnAggregate(A, token, now), 'bad_event');
  }
});
test('uppercase authenticated identities match canonical stored identities', async () => {
  const f = fixture();
  const s = createReferralService(config, f.storage);
  await s.recordEvent(event, now);
  assert.equal((await s.readOwnAggregate(A.toUpperCase(), event.shareToken, now)).share_page_view, 1);
  assert.deepEqual(await s.claimInvitation(consent, B.toUpperCase(), now), {status: 'pending_review'});
  assert.equal(f.claims.get(B).inviteeID, B);
});
