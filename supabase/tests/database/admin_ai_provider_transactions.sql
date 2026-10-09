-- Developer: gengyun
-- Purpose: Verify atomic provider writes, retained secrets, ACLs and history guards.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();
select ok(not has_function_privilege('anon', 'public.admin_ai_save_provider(uuid,text,text,text,boolean,jsonb)', 'execute'), 'anon cannot save');
select ok(not has_function_privilege('authenticated', 'public.admin_ai_save_provider(uuid,text,text,text,boolean,jsonb)', 'execute'), 'authenticated cannot save');
select ok(not has_function_privilege('anon', 'public.admin_ai_delete_provider(uuid)', 'execute'), 'anon cannot delete');
select ok(not has_function_privilege('authenticated', 'public.admin_ai_delete_provider(uuid)', 'execute'), 'authenticated cannot delete');
select ok(has_function_privilege('service_role', 'public.admin_ai_save_provider(uuid,text,text,text,boolean,jsonb)', 'execute'), 'service role can save');
select ok(has_function_privilege('service_role', 'public.admin_ai_delete_provider(uuid)', 'execute'), 'service role can delete');
select ok(not (select prosecdef from pg_proc where oid='public.admin_ai_save_provider(uuid,text,text,text,boolean,jsonb)'::regprocedure), 'save uses invoker');
select ok(not (select prosecdef from pg_proc where oid='public.admin_ai_delete_provider(uuid)'::regprocedure), 'delete uses invoker');
select is((select proconfig::text from pg_proc where oid='public.admin_ai_save_provider(uuid,text,text,text,boolean,jsonb)'::regprocedure), '{"search_path=\"\""}', 'save has empty search path');
set local role anon;
select throws_ok($$select public.admin_ai_save_provider(null,'Fixture','https://example.com','model',true,null)$$, '42501', null, 'anon execution denied');
reset role;
set local role authenticated;
select throws_ok($$select public.admin_ai_delete_provider('00000000-0000-4000-8000-000000000001')$$, '42501', null, 'authenticated execution denied');
reset role;

create temporary table provider_fixture as
select public.admin_ai_save_provider(null,'Fixture','https://example.com/v1','first',true,
  '{"secret_ref":"fixture-v2","ciphertext":"synthetic","nonce":"AAAAAAAAAAAAAAAA","key_version":2}') as result;
select is((select count(*)::integer from ai_providers where name='Fixture'), 1, 'create stores provider');
select is((select count(*)::integer from ai_models where provider_id=(select (result->>'id')::uuid from provider_fixture)), 1, 'create stores exactly one model');
select is((select key_version from ai_secrets where secret_ref='fixture-v2'), 2, 'create stores v2 envelope');
create temporary table model_fixture as select id from ai_models where provider_id=(select (result->>'id')::uuid from provider_fixture);
select lives_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'Edited','https://example.com/v2','second',false,null)$$, 'unreferenced single model can change');
select is((select id from ai_models where provider_id=(select (result->>'id')::uuid from provider_fixture)), (select id from model_fixture), 'model ID remains unchanged');
select is((select secret_ref from ai_providers where name='Edited'), 'fixture-v2', 'blank key keeps reference');
select is((select count(*)::integer from ai_secrets where secret_ref='fixture-v2'), 1, 'blank key keeps secret');
select ok(not (select enabled from ai_providers where name='Edited'), 'active edit persists');
select lives_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'Edited','https://example.com/v2','second',true,
  '{"secret_ref":"fixture-rotated","ciphertext":"newsynthetic","nonce":"AAAAAAAAAAAAAAAA","key_version":2}')$$, 'explicit rotation succeeds');
select is((select secret_ref from ai_providers where name='Edited'), 'fixture-rotated', 'rotation switches reference');
select is((select ciphertext from ai_secrets where secret_ref='fixture-v2'), 'synthetic', 'rotation retains old row');
select throws_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'Bad','https://example.com','third',true,
  '{"secret_ref":"fixture-rotated","ciphertext":"changed","nonce":"AAAAAAAAAAAAAAAA","key_version":2}')$$, '23505', null, 'reusing secret reference rejects whole save');
select is((select upstream_model_id from ai_models where id=(select id from model_fixture)), 'second', 'failed rotation rolls model back');
select is((select name from ai_providers where id=(select (result->>'id')::uuid from provider_fixture)), 'Edited', 'failed rotation rolls provider back');

-- Inject a late model-insert failure to prove secret/provider rollback on create.
create function pg_temp.fail_model_insert() returns trigger language plpgsql as $$begin raise exception 'synthetic failure'; end;$$;
create trigger synthetic_model_failure before insert on ai_models for each row execute function pg_temp.fail_model_insert();
select throws_ok($$select public.admin_ai_save_provider(null,'Rollback','https://example.com','rollback',true,
  '{"secret_ref":"fixture-rollback","ciphertext":"synthetic","nonce":"AAAAAAAAAAAAAAAA","key_version":2}')$$, 'P0001', 'synthetic failure', 'late create failure propagates');
select is((select count(*)::integer from ai_providers where name='Rollback'), 0, 'failed create leaves no provider');
select is((select count(*)::integer from ai_secrets where secret_ref='fixture-rollback'), 0, 'failed create leaves no secret');
drop trigger synthetic_model_failure on ai_models;

insert into ai_routes(route_key, primary_model_id) select 'fixture-primary', id from model_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'primary route blocks delete');
select throws_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'No','https://example.com','third',true,null)$$, 'PT409', null, 'primary route blocks model change');
select lives_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'Edited','https://example.com/v2','second',false,null)$$, 'referenced provider metadata remains editable');
delete from ai_routes where route_key='fixture-primary';
insert into ai_routes(route_key, fallback_model_ids) select 'fixture-fallback', array[id] from model_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'fallback route blocks delete');
delete from ai_routes where route_key='fixture-fallback';

insert into ai_usage_events(request_id, route_key, status, provider_id) select 'fixture-provider','fixture','success',(result->>'id')::uuid from provider_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'provider usage blocks delete');
delete from ai_usage_events where request_id='fixture-provider';
insert into ai_usage_events(request_id, route_key, status, model_id) select 'fixture-model','fixture','success',id from model_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'model usage blocks delete');
delete from ai_usage_events where request_id='fixture-model';
insert into ai_usage_events(request_id, route_key, status, final_model_id) select 'fixture-final','fixture','success',id from model_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'final model usage blocks delete');
delete from ai_usage_events where request_id='fixture-final';
insert into ai_usage_events(request_id, route_key, status, attempted_models) select 'fixture-attempt','fixture','error',jsonb_build_array(jsonb_build_object('modelId',upper(id::text))) from model_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'attempted model JSON blocks delete');
select throws_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'No','https://example.com','third',true,null)$$, 'PT409', null, 'attempted history blocks rename');
delete from ai_usage_events where request_id='fixture-attempt';
insert into admin_audit_logs(action,object_type,object_id) select 'fixture','ai_provider',result->>'id' from provider_fixture;
select throws_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'PT409', null, 'audit history blocks delete');
delete from admin_audit_logs where action='fixture';
insert into ai_models(provider_id,display_name,upstream_model_id,enabled) select (result->>'id')::uuid,'Other','other',false from provider_fixture;
select throws_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'No','https://example.com','third',true,null)$$, 'PT409', null, 'multiple models block rename');
select lives_ok($$select public.admin_ai_save_provider((select (result->>'id')::uuid from provider_fixture),'Edited','https://example.com/v2','second',false,null)$$, 'multiple model metadata edit succeeds');
insert into ai_provider_health(provider_id) select (result->>'id')::uuid from provider_fixture;
select lives_ok($$select public.admin_ai_delete_provider((select (result->>'id')::uuid from provider_fixture))$$, 'unreferenced provider deletes');
select is((select count(*)::integer from ai_models where provider_id=(select (result->>'id')::uuid from provider_fixture)), 0, 'unreferenced models cascade');
select is((select count(*)::integer from ai_provider_health where provider_id=(select (result->>'id')::uuid from provider_fixture)), 0, 'health cascades');
select is((select count(*)::integer from ai_secrets where secret_ref in ('fixture-v2','fixture-rotated')), 2, 'deletion preserves all secrets');
select * from finish();
rollback;
