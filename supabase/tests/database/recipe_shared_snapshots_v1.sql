-- Developer: Recipe Pals
-- Purpose: DEV-241 owner/anonymous sharing isolation in a DISPOSABLE local Supabase database.
-- Apply migrations/20261011044118_recipe_shared_snapshots_v1.sql in a disposable DB.
-- Offline replay/rollback: tests/isolated/recipe-share-migration.test.mjs.

create extension if not exists pgtap;
begin;
select plan(32);

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


-- Additional constraint and sequential CAS negatives, not multi-session race evidence.
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111');
set local role service_role;
insert into public.recipe_shared_snapshots (
 owner_id, source_recipe_id, source_client_updated_at, opaque_slug, scope,
 has_distribution_rights, sanitized_snapshot, idempotency_key, request_hash
) values (
 '11111111-1111-4111-8111-111111111111',
 '33333333-3333-4333-8333-333333333333', '2026-10-10T11:00:00Z',
 repeat('a',43), 'summaryAndSource', false,
 '{"title":"Soup","summary":"Safe","sourceURL":null,"servings":2,"prepMinutes":10,"cookMinutes":5,"ingredients":[],"steps":[]}',
 '44444444-4444-4444-8444-444444444444', repeat('a',64)
);
select throws_ok($$update public.recipe_shared_snapshots set scope='fullInstructions'
 where owner_id='11111111-1111-4111-8111-111111111111'$$,
 '23514',null,'full instructions require distribution rights at DB boundary');
select throws_ok($$update public.recipe_shared_snapshots
 set sanitized_snapshot=jsonb_set(sanitized_snapshot,'{ingredients}','[{"name":"Salt","amountText":"to taste"}]')
 where owner_id='11111111-1111-4111-8111-111111111111'$$,
 '23514',null,'summary rejects nonempty ingredients');
select throws_ok($$update public.recipe_shared_snapshots
 set sanitized_snapshot=jsonb_set(sanitized_snapshot,'{steps}','[{"title":"Mix","instruction":"Mix."}]')
 where owner_id='11111111-1111-4111-8111-111111111111'$$,
 '23514',null,'summary rejects nonempty steps');
select throws_ok($$insert into public.recipe_shared_snapshots
 (owner_id,source_recipe_id,source_client_updated_at,opaque_slug,scope,
 has_distribution_rights,sanitized_snapshot,idempotency_key,request_hash)
 select owner_id,source_recipe_id,source_client_updated_at,repeat('b',43),scope,
 has_distribution_rights,sanitized_snapshot,idempotency_key,request_hash
 from public.recipe_shared_snapshots$$,
 '23505',null,'same owner cannot create a second share with the same retry key');
select lives_ok($$insert into public.recipe_shared_snapshots
 (owner_id,source_recipe_id,source_client_updated_at,opaque_slug,scope,
 has_distribution_rights,sanitized_snapshot,idempotency_key,request_hash)
 select '22222222-2222-4222-8222-222222222222'::uuid,source_recipe_id,
 source_client_updated_at,repeat('b',43),scope,has_distribution_rights,
 sanitized_snapshot,idempotency_key,request_hash from public.recipe_shared_snapshots$$,
 'different owner may use the same retry key independently');
select is((select count(*) from public.recipe_shared_snapshots),2::bigint,
 'retry-key conflict does not lose or duplicate either owner record');
with changed as (
 update public.recipe_shared_snapshots set share_version=2
 where owner_id='11111111-1111-4111-8111-111111111111'
 and share_version=1 and revoked_at is null returning share_id
) select is((select count(*) from changed),1::bigint,'current CAS updates exactly one owner row');
with changed as (
 update public.recipe_shared_snapshots set share_version=2,
 sanitized_snapshot=jsonb_set(sanitized_snapshot,'{title}','"Stale overwrite"')
 where owner_id='11111111-1111-4111-8111-111111111111'
 and share_version=1 and revoked_at is null returning share_id
) select is((select count(*) from changed),0::bigint,'stale CAS updates zero rows');
select is((select sanitized_snapshot->>'title' from public.recipe_shared_snapshots
 where owner_id='11111111-1111-4111-8111-111111111111'),
 'Soup','stale CAS preserves approved public content');
update public.recipe_shared_snapshots set revoked_at=now(),sanitized_snapshot=null
 where owner_id='11111111-1111-4111-8111-111111111111';
with changed as (
 update public.recipe_shared_snapshots set share_version=3,
 revoked_at=null,sanitized_snapshot='{"ingredients":[],"steps":[]}'
 where owner_id='11111111-1111-4111-8111-111111111111'
 and share_version=2 and revoked_at is null returning share_id
) select is((select count(*) from changed),0::bigint,'active-state CAS cannot resurrect revoked row');
reset role;
delete from auth.users where id='11111111-1111-4111-8111-111111111111';
select is((select count(*) from public.recipe_shared_snapshots
 where owner_id='11111111-1111-4111-8111-111111111111'),0::bigint,
 'account deletion removes only deleted owner shares');
select is((select sanitized_snapshot->>'title' from public.recipe_shared_snapshots
 where owner_id='22222222-2222-4222-8222-222222222222'),
 'Soup','deleting A preserves B approved share content');


-- Service-only RPC performs quota/retry admission in one transaction.
select ok(not has_function_privilege('anon',
 'public.create_recipe_share_once(uuid,jsonb,text,text)','EXECUTE'),
 'anon cannot invoke privileged create admission');
select ok(not has_function_privilege('authenticated',
 'public.create_recipe_share_once(uuid,jsonb,text,text)','EXECUTE'),
 'authenticated cannot nominate a create owner through RPC');
select ok(has_function_privilege('service_role',
 'public.create_recipe_share_once(uuid,jsonb,text,text)','EXECUTE'),
 'service role can invoke create admission');
set local role service_role;
insert into public.recipe_shared_snapshots (
 owner_id,source_recipe_id,source_client_updated_at,opaque_slug,scope,
 has_distribution_rights,sanitized_snapshot,idempotency_key,request_hash
) select owner_id,source_recipe_id,source_client_updated_at,
 lpad(n::text,43,'q'),scope,has_distribution_rights,sanitized_snapshot,
 gen_random_uuid(),request_hash
 from public.recipe_shared_snapshots cross join generate_series(1,198) n;
select set_config('test.share_payload',
 '{"idempotencyKey":"55555555-5555-4555-8555-555555555555","sourceRecipeID":"33333333-3333-4333-8333-333333333333","sourceRecipeUpdatedAt":"2026-10-10T11:00:00Z","scope":"summaryAndSource","hasDistributionRights":false,"snapshot":{"title":"Quota soup","ingredients":[],"steps":[]}}',true);
select is((public.create_recipe_share_once(
 '22222222-2222-4222-8222-222222222222',current_setting('test.share_payload')::jsonb,
 repeat('c',43),repeat('c',64))->>'status')::int,201,
 '199 prior shares admit the 200th intent');
select is((public.create_recipe_share_once(
 '22222222-2222-4222-8222-222222222222',
 jsonb_set(current_setting('test.share_payload')::jsonb,'{idempotencyKey}',
 '"66666666-6666-4666-8666-666666666666"'),repeat('d',43),repeat('d',64))->>'status')::int,429,
 '200 prior shares reject the next new intent');
select is((public.create_recipe_share_once(
 '22222222-2222-4222-8222-222222222222',current_setting('test.share_payload')::jsonb,
 repeat('e',43),repeat('c',64))->>'status')::int,200,
 'same retry bypasses quota without inserting another slug');
select is((public.create_recipe_share_once(
 '22222222-2222-4222-8222-222222222222',current_setting('test.share_payload')::jsonb,
 repeat('f',43),repeat('f',64))->>'status')::int,409,
 'changed retry digest conflicts even at quota');
select is((select count(*) from public.recipe_shared_snapshots),200::bigint,
 'quota rejection and retries keep exactly 200 owner shares');
reset role;

select * from finish();
rollback;
