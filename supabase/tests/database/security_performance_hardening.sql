-- Staging-only read assertions for 20261009014500_security_performance_hardening.sql.
-- Requires pgTAP (supabase test db); this file must not mutate user data.
create extension if not exists pgtap;
begin;

select plan(12);

select ok(to_regclass('public.ai_routes_primary_model_id_idx') is not null,
  'ai_routes primary model has a covering index');
select ok(to_regclass('public.ai_usage_events_final_model_id_idx') is not null,
  'ai_usage_events final model has a covering index');
select ok(to_regclass('public.ai_usage_events_model_id_idx') is not null,
  'ai_usage_events model has a covering index');
select ok(to_regclass('public.payment_transactions_purchase_event_id_idx') is not null,
  'payment transactions purchase event has a covering index');
select ok(to_regclass('public.store_integrations_secret_ref_idx') is not null,
  'store integrations secret reference has a covering index');

select ok((select proconfig @> array['search_path=']::text[]
    from pg_proc where oid='public.touch_subscription_plans_updated_at()'::regprocedure),
  'subscription plan trigger has an immutable lookup path');
select ok((select proconfig @> array['search_path=']::text[]
    from pg_proc where oid='public.touch_runtime_config_updated_at()'::regprocedure),
  'runtime config trigger has an immutable lookup path');
select ok((select proconfig @> array['search_path=']::text[]
    from pg_proc where oid='public.touch_payment_transactions_updated_at()'::regprocedure),
  'payment transaction trigger has an immutable lookup path');
select ok((select proconfig @> array['search_path=']::text[]
    from pg_proc where oid='public.map_commerce_store(text)'::regprocedure),
  'commerce store mapping has an immutable lookup path');
select ok((select proconfig @> array['search_path=']::text[]
    from pg_proc where oid='public.map_commerce_platform(text)'::regprocedure),
  'commerce platform mapping has an immutable lookup path');

select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'public'
     and tablename in (
       'profiles', 'subscriptions', 'purchase_events', 'ingredients',
       'recipes', 'collections', 'grocery_lists', 'meal_plans',
       'pantry_items', 'payment_transactions'
     )
     and (qual ilike '%select auth.uid()%' or with_check ilike '%select auth.uid()%')),
  30,
  'all 30 owner-scoped policies cache auth.uid() per statement'
);

select ok(
  not has_table_privilege('anon', 'public.user_snapshots', 'SELECT') and
  not has_table_privilege('authenticated', 'public.user_snapshots', 'UPDATE'),
  'snapshot direct-write and anonymous access restrictions are unchanged'
);

select * from finish();
rollback;
