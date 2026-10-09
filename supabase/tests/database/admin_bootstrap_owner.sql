-- Developer: gengyun
-- Purpose: Verify default-seed conversion updates the owner and revokes sessions.
begin;

select plan(8);

insert into public.admin_accounts (
    id, username, password_hash, role, is_default_seed, must_change_password
) values (
    '11111111-1111-4111-8111-111111111111',
    'seed-admin',
    extensions.crypt('SeedPassword123', extensions.gen_salt('bf')),
    'admin',
    true,
    true
);

select is(
    (select exists(select 1 from public.admin_accounts where is_default_seed = false)),
    false,
    'bootstrap status is uninitialized before seed conversion'
);

insert into public.admin_sessions (id, admin_id, token_hash, expires_at)
values (
    '22222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    'fixture-token-hash',
    '2099-01-01 00:00:00+00'::timestamptz
);

select lives_ok(
    $$select * from public.admin_bootstrap_owner(
        'admin', 'NewStrongPassword123', 'SeedPassword123'
    )$$,
    'converts the default seed without ambiguous id references'
);
select is(
    (select exists(select 1 from public.admin_accounts where is_default_seed = false)),
    true,
    'bootstrap status is initialized after successful setup'
);
select is(
    (select username from public.admin_accounts where id = '11111111-1111-4111-8111-111111111111'),
    'admin'::text,
    'sets the requested owner username'
);
select is(
    (select role from public.admin_accounts where id = '11111111-1111-4111-8111-111111111111'),
    'owner'::text,
    'promotes the seed account to owner'
);
select is(
    (select is_default_seed from public.admin_accounts where id = '11111111-1111-4111-8111-111111111111'),
    false,
    'removes the default-seed marker'
);
select is(
    (select must_change_password from public.admin_accounts where id = '11111111-1111-4111-8111-111111111111'),
    false,
    'clears the forced password-change flag'
);
select is(
    (select count(*)::integer from public.admin_sessions where admin_id = '11111111-1111-4111-8111-111111111111' and revoked_at is null),
    0,
    'revokes existing admin sessions'
);

select * from finish();
rollback;
