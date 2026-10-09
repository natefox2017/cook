-- Developer: gengyun
-- Purpose: Verify admin factor data is private and constrained to registered administrators.
begin;

select plan(30);

insert into public.admin_accounts (id, username, password_hash, role)
values ('11111111-1111-4111-8111-111111111111', 'factor-owner', 'fixture', 'owner');

select ok((select relrowsecurity from pg_class where oid = 'public.admin_auth_factors'::regclass), 'TOTP factors have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_passkeys'::regclass), 'passkeys have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_auth_login_challenges'::regclass), 'login challenges have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_auth_webauthn_challenges'::regclass), 'WebAuthn challenges have RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_auth_login_state'::regclass), 'account lock state has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_auth_login_events'::regclass), 'login events have RLS enabled');
select ok(not has_table_privilege('anon', 'public.admin_auth_factors', 'SELECT'), 'anon cannot read TOTP factors');
select ok(not has_table_privilege('authenticated', 'public.admin_passkeys', 'SELECT'), 'authenticated cannot read passkeys');
select ok(not has_table_privilege('anon', 'public.admin_auth_login_events', 'SELECT'), 'anon cannot read login events');
select ok(has_table_privilege('service_role', 'public.admin_auth_factors', 'SELECT,INSERT,UPDATE,DELETE'), 'service role can manage TOTP factors');
select ok(has_table_privilege('service_role', 'public.admin_passkeys', 'SELECT,INSERT,UPDATE,DELETE'), 'service role can manage passkeys');
select ok(has_table_privilege('service_role', 'public.admin_auth_login_events', 'SELECT,INSERT'), 'service role can read and append login events');
select ok(not has_function_privilege('anon', 'public.admin_record_login_event(text,uuid,text,boolean,boolean,text,text,text)', 'EXECUTE'), 'anon cannot record login events');

insert into public.admin_auth_factors (admin_id, totp_secret_ciphertext)
values ('11111111-1111-4111-8111-111111111111', 'v1.iv.ciphertext');
select ok((select totp_enabled_at is null from public.admin_auth_factors where admin_id = '11111111-1111-4111-8111-111111111111'), 'TOTP remains pending until verified');

insert into public.admin_passkeys (credential_id, admin_id, public_key, sign_count)
values ('credential-1', '11111111-1111-4111-8111-111111111111', 'public-key', 0);
select is((select count(*)::integer from public.admin_passkeys where admin_id = '11111111-1111-4111-8111-111111111111'), 1, 'passkey credential is tied to its admin');

select throws_ok(
    $$insert into public.admin_auth_webauthn_challenges (admin_id, purpose, challenge, expires_at)
      values ('11111111-1111-4111-8111-111111111111', 'register', 'challenge', now() + interval '5 minutes')$$,
    '23514', null, 'registration challenge requires its admin session'
);
select throws_ok(
    $$insert into public.admin_passkeys (credential_id, admin_id, public_key, sign_count)
      values ('bad-counter', '11111111-1111-4111-8111-111111111111', 'public-key', -1)$$,
    '23514', null, 'negative signature counters are rejected'
);
select throws_ok(
    $$insert into public.admin_auth_login_challenges (admin_id, challenge_hash, expires_at, attempts)
      values ('11111111-1111-4111-8111-111111111111', 'hash', now() + interval '5 minutes', 6)$$,
    '23514', null, 'TOTP login challenges cannot exceed five attempts'
);

select lives_ok($$select * from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'password', false, true, '192.0.2.1', 'test-agent', 'invalid_credentials')$$, 'first failed password is recorded');
select lives_ok($$select * from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'totp', false, true, '192.0.2.1', 'test-agent', 'invalid_totp')$$, 'TOTP shares the account failure counter');
select lives_ok($$select * from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'password', false, true, '192.0.2.1', 'test-agent', 'invalid_credentials')$$, 'password and TOTP failures are counted together');
select lives_ok($$select * from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'totp', false, true, '192.0.2.1', 'test-agent', 'invalid_totp')$$, 'four failures remain below the lock threshold');
select lives_ok($$select * from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'password', true, false, '192.0.2.1', 'test-agent', null)$$, 'correct password before TOTP does not clear factor failures');
select is((select failed_attempts::integer from public.admin_auth_login_state where identity_key = 'admin:11111111-1111-4111-8111-111111111111'), 4, 'MFA password success preserves the shared failure count');
select ok(not (select allowed from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'password', false, true, '192.0.2.1', 'test-agent', 'invalid_credentials')), 'fifth failure locks the account');
select is((select failed_attempts::integer from public.admin_auth_login_state where identity_key = 'admin:11111111-1111-4111-8111-111111111111'), 5, 'lock persists five account failures');
select ok((select locked_until > now() + interval '23 hours' from public.admin_auth_login_state where identity_key = 'admin:11111111-1111-4111-8111-111111111111'), 'lock lasts 24 hours');
select ok(not (select allowed from public.admin_record_login_event('admin:11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'totp', true, true, '192.0.2.1', 'test-agent', null)), 'correct factor cannot bypass active lock');
select is((select count(*)::integer from public.admin_auth_login_events where admin_id = '11111111-1111-4111-8111-111111111111'), 7, 'authentication events persist without credential payloads');

delete from public.admin_accounts where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::integer from public.admin_passkeys), 0, 'deleting an admin cascades its registered passkeys');

select * from finish();
rollback;
