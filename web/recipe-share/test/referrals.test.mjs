import {test} from "node:test";
import assert from "node:assert/strict";
import {validateAggregateShareEvent,proposeExplicitInvitationClaim} from "../src/referrals.mjs";

const A="c7f04da2-8191-49b4-9a1a-e36d7c72d111";
const B="8a0c335d-60de-4383-ac43-ebfbcbb5ab01";
const code="AbCdEfGhIJKL01234567";
const valid={kind:"app_store_cta_click",shareToken:"abc12345EFGH",eventID:"evt98765432101234"};

test("anonymous events are restricted to known names and no identity",()=>{
  assert.deepEqual(validateAggregateShareEvent(valid),valid);
  assert.throws(()=>validateAggregateShareEvent({...valid,ip:"127.0.0.1"}),/unexpected_field/);
  assert.throws(()=>validateAggregateShareEvent({...valid,email:"a@example.com"}),/unexpected_field/);
  assert.throws(()=>validateAggregateShareEvent({...valid,kind:"installed"}),/bad_event/);
  assert.throws(()=>validateAggregateShareEvent({...valid,shareToken:"x"}),/bad_event/);
});
test("verified invitation requires explicit consent and known inviter",()=>{
  const payload={
    authenticatedInviteeID:B,lookedUpInviterID:A,
    lookedUpInviteCode:code,submittedCode:code,
    confirmedByInvitee:true,existingInvitationClaim:false
  };
  assert.deepEqual(proposeExplicitInvitationClaim(payload),{
    inviteeID:B,inviterID:A,code,status:"pending_review"
  });
  assert.throws(()=>proposeExplicitInvitationClaim({...payload,confirmedByInvitee:false}),/consent_required/);
  assert.throws(()=>proposeExplicitInvitationClaim({...payload,lookedUpInviteCode:"other"}),/invalid_or_unverified_code/);
});
test("cannot refer yourself or claim repeatedly",()=>{
  const payload={
    authenticatedInviteeID:B,lookedUpInviterID:A,
    lookedUpInviteCode:code,submittedCode:code,
    confirmedByInvitee:true,existingInvitationClaim:false
  };
  assert.throws(()=>proposeExplicitInvitationClaim({...payload,lookedUpInviterID:B}),/self_invitation/);
  assert.throws(()=>proposeExplicitInvitationClaim({...payload,existingInvitationClaim:true}),/already_claimed/);
  assert.throws(()=>proposeExplicitInvitationClaim({...payload,authenticatedInviteeID:"not-a-uuid"}),/server_identity_required/);
});
