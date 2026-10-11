-- Developer: Recipe Pals
-- Purpose: DEV-241 owner/anonymous sharing isolation in a DISPOSABLE local Supabase database.
-- Apply the reviewed SQL via a CLI-generated migration before running this pgTAP fixture.

create extension if not exists pgtap;
begin;
select plan(12);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.recipe_shared_snapshots'::regclass),
  'share registry has RLS'
);
select ok(not has_table_privilege('anon','public.recipe_shared_snapshots','SELECT'),
  'guest has no direct Data API SELECT');
select ok(not has_table_privilege('authenticated','public.recipe_shared_snapshots','INSERT'),
  'client cannot forge public share rows');
select ok(not has_table_privilege('authenticated','public.recipe_shared_snapshots','UPDATE'),
  'client cannot forge public snapshot changes');
select ok(not has_table_privilege('authenticated','public.recipe_shared_snapshots','DELETE'),
  'client cannot bypass versioned revoke');

insert into auth.users(id)
values ('11111111-1111-4111-8111-111111111111'),
       ('22222222-2222-4222-8222-222222222222');

set local role service_role;
insert into public.recipe_shared_snapshots (
 owner_id, source_recipe_id, source_client_updated_at,
 opaque_slug, scope, has_distribution_rights, sanitized_snapshot,
 idempotency_key, request_hash
) values (
 '11111111-1111-4111-8111-111111111111',
 '33333333-3333-4333-8333-333333333333',
 '2026-10-10T11:00:00Z',
 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
 'summaryAndSource', false,
 '{"title":"Soup","summary":"Safe","sourceURL":null,"servings":2,"prepMinutes":10,"cookMinutes":5,"ingredients":[],"steps":[]}'::jsonb,
 '44444444-4444-4444-8444-444444444444',
 repeat('a',64)
);
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
select is((select count(*) from public.recipe_shared_snapshots),1::bigint,
  'owner A can read only own share');
select throws_ok($$update public.recipe_shared_snapshots set sanitized_snapshot='{}'$$,
  '42501',null,'owner A cannot directly bypass Edge rights validation');
select throws_ok($$delete from public.recipe_shared_snapshots$$,
  '42501',null,'owner A cannot directly erase share audit');

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}',true);
select is((select count(*) from public.recipe_shared_snapshots),0::bigint,
  'owner B cannot read owner A share');

set local role anon;
select is(has_table_privilege('anon','public.recipe_shared_snapshots','SELECT'),false,
  'anonymous request has no registry SQL permission');

set local role service_role;
update public.recipe_shared_snapshots
set revoked_at=now(), sanitized_snapshot=null
where owner_id='11111111-1111-4111-8111-111111111111';
select is((select sanitized_snapshot from public.recipe_shared_snapshots limit 1),
  null::jsonb,'revoke irreversibly clears guest payload');

reset role;
delete from auth.users where id='11111111-1111-4111-8111-111111111111';
select is((select count(*) from public.recipe_shared_snapshots),0::bigint,
  'account deletion cascades old public share records');

select * from finish();
rollback;
