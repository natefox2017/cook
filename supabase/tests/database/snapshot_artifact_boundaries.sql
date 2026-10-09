-- Developer: gengyun
-- Purpose: Verify snapshot CAS and private artifact isolation as actual unprivileged database roles.
create extension if not exists pgtap;
begin;
select plan(25);

insert into auth.users(id) values
('11111111-1111-4111-8111-111111111111'),
('22222222-2222-4222-8222-222222222222');

select is((select public from storage.buckets where id = 'recipe-import-artifacts'), false,
    'artifact bucket configuration is private');
select is((select file_size_limit from storage.buckets where id = 'recipe-import-artifacts'), 10485760::bigint,
    'artifact bucket configuration enforces ten MiB');
insert into public.recipe_import_artifacts(
    id, owner_id, client_request_id, input_type, kind, storage_path, mime_type, size_bytes, state, expires_at
) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-0000-4000-8000-000000000001', 'file', 'original',
 '11111111-1111-4111-8111-111111111111/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/original.pdf',
 'application/pdf', 100, 'available', now() + interval '7 days'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '11111111-1111-4111-8111-111111111111',
 'bbbbbbbb-0000-4000-8000-000000000001', 'file', 'original',
 '11111111-1111-4111-8111-111111111111/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/original.pdf',
 'application/pdf', 100, 'available', now() - interval '1 second');

set local role authenticated;
select ok(not (select rolsuper or rolbypassrls from pg_roles where rolname = current_user),
    'authenticated tests run without superuser or BYPASSRLS');
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","is_anonymous":false}', true);
select is((select revision from public.save_own_user_snapshot(
    auth.uid(), 0, 1, '{"recipes":[]}', now())), 1::bigint, 'owner creates snapshot at revision one');
select is((select count(*) from public.save_own_user_snapshot(
    auth.uid(), 0, 1, '{"recipes":[]}', now())), 0::bigint, 'replayed creation cannot overwrite snapshot');
select is((select revision from public.save_own_user_snapshot(
    auth.uid(), 1, 1, '{"recipes":["updated"]}', now())), 2::bigint, 'owner update increments snapshot revision');
select is((select count(*) from public.save_own_user_snapshot(
    auth.uid(), 1, 1, '{"recipes":["stale"]}', now())), 0::bigint, 'stale revision cannot overwrite current snapshot');
select is((select payload from public.user_snapshots where user_id = auth.uid()),
    '{"recipes":["updated"]}'::jsonb, 'stale update preserves stored data');
select throws_ok($$update public.user_snapshots set payload = '{}'$$, '42501', null,
    'direct snapshot writes remain forbidden');
select throws_ok($$select * from public.save_own_user_snapshot(
    '22222222-2222-4222-8222-222222222222', 0, 1, '{}', now())$$, '42501', null,
    'owner cannot save another account snapshot');
select throws_ok($$select * from public.save_own_user_snapshot(
    auth.uid(), 2, 1, '[]', now())$$, '22023', 'Invalid snapshot.',
    'invalid snapshot shape is rejected');
select is((select count(*) from public.recipe_import_artifacts), 2::bigint,
    'owner reads their own artifact metadata');
select throws_ok($$update public.recipe_import_artifacts set state = 'available'$$, '42501', null,
    'owner cannot forge artifact availability');
select is((select status from public.submit_own_recipe_artifact_import(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'file', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'files', null)),
    'queued', 'available owner artifact is durably queued');
select is((select status from public.submit_own_recipe_artifact_import(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'file', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'files', null)),
    'queued', 'identical artifact submission is replayable');
select is((select count(*) from public.recipe_import_jobs), 1::bigint,
    'artifact replay creates no duplicate job');
select throws_ok($$select * from public.submit_own_recipe_artifact_import(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'file', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', null, null)$$,
    'P0001', 'ARTIFACT_NOT_READY', 'expired artifact cannot enter the queue');

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","is_anonymous":false}', true);
select is((select count(*) from public.user_snapshots), 0::bigint,
    'another account cannot read snapshot through RLS');
select is((select count(*) from public.recipe_import_artifacts), 0::bigint,
    'another account cannot read artifact through RLS');
select is((select count(*) from public.recipe_import_jobs), 0::bigint,
    'another account cannot read artifact job through RLS');
select throws_ok($$select * from public.submit_own_recipe_artifact_import(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'file', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, null)$$,
    'P0001', 'ARTIFACT_NOT_READY', 'another account cannot import a private artifact');
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","is_anonymous":true}', true);
select throws_ok($$select * from public.submit_own_recipe_artifact_import(
    'ffffffff-ffff-4fff-8fff-ffffffffffff', 'file', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null, null)$$,
    '42501', 'AUTH_REQUIRED', 'anonymous Auth user cannot submit artifact import');
set local role anon;
select throws_ok($$select * from public.recipe_import_artifacts$$, '42501', null,
    'anon role cannot read artifact table');
select throws_ok($$select * from public.save_own_user_snapshot(
    '11111111-1111-4111-8111-111111111111', 0, 1, '{}', now())$$, '42501', null,
    'anon role cannot invoke snapshot writes');
reset role;
select is((select count(*) from pgmq.q_recipe_import_v1
    where message ->> 'owner_id' = '11111111-1111-4111-8111-111111111111'), 1::bigint,
    'artifact replay and rejected submissions enqueue no duplicate messages');
select * from finish();
rollback;
