-- Developer: gengyun
-- Purpose: DEV-427 commercial usage ledger regression: ACL, quota arithmetic, idempotent replay,
--          finalize dedup and owner isolation against real PostgreSQL (single connection).
--          Multi-session concurrency is exercised by tests/isolated/recipe-usage-concurrency/ instead.
create extension if not exists pgtap;

begin;
select plan(46);

-- ---------------------------------------------------------------------------
-- ACL: only service_role may execute the settlement entry points; helpers stay private.
-- ---------------------------------------------------------------------------
select ok(
    to_regprocedure('public.recipe_usage_reserve(uuid,uuid,text,text,jsonb)') is not null,
    'recipe_usage_reserve exists'
);
select is(
    has_function_privilege('service_role', 'public.recipe_usage_reserve(uuid,uuid,text,text,jsonb)', 'execute'),
    true,
    'service_role can reserve'
);
select is(
    has_function_privilege('authenticated', 'public.recipe_usage_reserve(uuid,uuid,text,text,jsonb)', 'execute'),
    false,
    'authenticated cannot reserve directly'
);
select is(
    has_function_privilege('anon', 'public.recipe_usage_reserve(uuid,uuid,text,text,jsonb)', 'execute'),
    false,
    'anonymous cannot reserve directly'
);
select is(
    has_function_privilege('authenticated', 'public.recipe_usage_finalize(uuid,uuid,text,text,jsonb,text,jsonb)', 'execute'),
    false,
    'authenticated cannot finalize directly'
);
select is(
    has_function_privilege('service_role', 'public.recipe_usage_finalize(uuid,uuid,text,text,jsonb,text,jsonb)', 'execute'),
    true,
    'service_role can finalize'
);
select is(
    has_function_privilege('authenticated', 'public.recipe_usage_settle(uuid,uuid,text,text)', 'execute'),
    false,
    'authenticated cannot call the internal settle helper'
);
select is(
    has_function_privilege('service_role', 'public.recipe_usage_settle(uuid,uuid,text,text)', 'execute'),
    false,
    'service_role cannot call the internal settle helper either'
);
select is(
    has_function_privilege('authenticated', 'public.recipe_usage_entitlement(uuid)', 'execute'),
    false,
    'entitlement helper is not client-callable'
);
select ok(
    (select relrowsecurity from pg_class where oid = 'public.recipe_usage_counters'::regclass),
    'counter table has row-level security enabled'
);
select ok(
    (select relrowsecurity from pg_class where oid = 'public.recipe_usage_reservations'::regclass),
    'reservation table has row-level security enabled'
);
select is(
    has_table_privilege('authenticated', 'public.recipe_usage_counters', 'SELECT'),
    false,
    'authenticated cannot read counters'
);
select is(
    has_table_privilege('authenticated', 'public.recipe_usage_counters', 'INSERT'),
    false,
    'authenticated cannot insert counters'
);
select is(
    has_table_privilege('authenticated', 'public.recipe_usage_reservations', 'UPDATE'),
    false,
    'authenticated cannot update reservations'
);

-- ---------------------------------------------------------------------------
-- Synthetic subjects.
-- ---------------------------------------------------------------------------
insert into auth.users(id) values
    ('d2977e89-94ab-4a2e-97eb-0f09b65f8d76'),
    ('59a357da-b6d3-4e5f-a1a0-5bfe6da31a36');

set local role service_role;

-- ---------------------------------------------------------------------------
-- Snapshot: free owner gets iso-week import quota and lifetime edit quota.
-- ---------------------------------------------------------------------------
select is(
    (public.recipe_access_snapshot('d2977e89-94ab-4a2e-97eb-0f09b65f8d76', 1, 'freeTest') -> 'entitlement' ->> 'status'),
    'free',
    'owner without subscription reports free entitlement'
);
select is(
    (public.recipe_access_snapshot('d2977e89-94ab-4a2e-97eb-0f09b65f8d76', 1, 'freeTest')
        -> 'capabilities' -> 0 -> 'quota' ->> 'period_type'),
    'iso_week',
    'free smart_import is metered per ISO week'
);
select is(
    (public.recipe_access_snapshot('d2977e89-94ab-4a2e-97eb-0f09b65f8d76', 1, 'freeTest')
        -> 'capabilities' -> 1 -> 'quota' ->> 'period_type'),
    'lifetime',
    'free ai_edit is metered per lifetime'
);

-- ---------------------------------------------------------------------------
-- Reserve/commit: idempotent replay and single charge across week/month observation.
-- ---------------------------------------------------------------------------
select is(
    public.recipe_usage_reserve(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'RESERVED',
    'first reserve admits a reservation'
);
select is(
    public.recipe_usage_reserve(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'REPLAY',
    'identical reserve replays the durable reservation'
);
select is(
    public.recipe_usage_reserve(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001',
        'smart_import',
        repeat('b', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'IDEMPOTENCY_CONFLICT',
    'same key with a different input_hash conflicts'
);
select is(
    public.recipe_usage_commit(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001',
        'smart_import',
        repeat('a', 64)
    ) ->> 'code',
    'COMMITTED',
    'commit settles the dispatched reservation'
);
select is(
    public.recipe_usage_commit(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001',
        'smart_import',
        repeat('a', 64)
    ) ->> 'code',
    'COMMITTED',
    'replaying commit never charges twice'
);
select is(
    (select used from public.recipe_usage_counters
     where owner_id = 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76'
       and capability = 'smart_import' and period_type = 'iso_week'),
    1,
    'a successful import observes the UTC week counter'
);
select is(
    (select used from public.recipe_usage_counters
     where owner_id = 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76'
       and capability = 'smart_import' and period_type = 'utc_month'),
    1,
    'the same import also observes the UTC month counter'
);
select is(
    public.recipe_usage_release(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000001'
    ) ->> 'code',
    'COMMITTED',
    'a committed reservation cannot be released'
);

-- ---------------------------------------------------------------------------
-- Finalize: stable recipe_id, source-level dedup, ack, and owner masking.
-- ---------------------------------------------------------------------------
select is(
    public.recipe_usage_reserve(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000002',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'RESERVED',
    'second operation reserves before finalize'
);
do $$
declare v_final jsonb;
begin
    v_final := public.recipe_usage_finalize(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000002',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb,
        repeat('c', 64),
        '{"title":"Soup"}'::jsonb
    );
    perform set_config('test.recipe_id', v_final ->> 'recipe_id', true);
end $$;
select is(
    (select count(*) from public.recipe_usage_finalizations
     where owner_id = 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76' and capability = 'smart_import'),
    1,
    'finalize persists one durable finalization'
);
select is(
    (public.recipe_usage_finalize(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000002',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb,
        repeat('d', 64),
        '{"title":"Other"}'::jsonb
    ) ->> 'recipe_id'),
    current_setting('test.recipe_id'),
    'replaying finalize returns the same stable recipe_id without a second charge'
);
-- A new operation for the same candidate returns the same durable recipe_id.
select is(
    public.recipe_usage_reserve(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000003',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'RESERVED',
    'a new operation for the same candidate reserves normally'
);
select is(
    (public.recipe_usage_finalize(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000003',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb,
        repeat('c', 64),
        '{"title":"Soup"}'::jsonb
    ) ->> 'recipe_id'),
    current_setting('test.recipe_id'),
    'a new operation for the same candidate dedups to the same recipe_id'
);
select is(
    (select used from public.recipe_usage_counters
     where owner_id = 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76'
       and capability = 'smart_import' and period_type = 'iso_week'),
    2,
    'finalize dedup never charges the source twice'
);
select is(
    public.recipe_usage_release(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000003'
    ) ->> 'code',
    'RELEASED',
    'the still-reserved duplicate operation can be released'
);
select is(
    public.recipe_usage_release(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000003'
    ) ->> 'code',
    'RELEASED',
    'releasing again is idempotent and never goes negative'
);
select is(
    (select reserved from public.recipe_usage_counters
     where owner_id = 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76'
       and capability = 'smart_import' and period_type = 'iso_week'),
    0,
    'release returns the unit and the counter is not negative'
);
select is(
    public.recipe_usage_ack(
        'd2977e89-94ab-4a2e-97eb-0f09b65f8d76',
        'b0000000-0000-4000-8000-000000000002'
    ) ->> 'code',
    'ACKED',
    'ack confirms the finalized save'
);
select is(
    public.recipe_usage_release(
        '59a357da-b6d3-4e5f-a1a0-5bfe6da31a36',
        'b0000000-0000-4000-8000-000000000002'
    ) ->> 'code',
    'NOT_FOUND',
    'a foreign owner cannot release another owner''s operation (masked)'
);

-- ---------------------------------------------------------------------------
-- Quota exhaustion: the sixth free import in one ISO week is rejected.
-- ---------------------------------------------------------------------------
do $$
declare i integer;
begin
    for i in 1..5 loop
        perform public.recipe_usage_reserve(
            '59a357da-b6d3-4e5f-a1a0-5bfe6da31a36',
            (format('b0000000-0000-4000-8000-%012s', i))::uuid,
            'smart_import',
            repeat('a', 64),
            jsonb_build_object(
                'origin', 'import_job',
                'job_id', 'e0000000-0000-4000-8000-000000000005',
                'candidate_ids', jsonb_build_array(format('candidate-v2-%032s', i)),
                'session_id', null,
                'turn_request_id', null
            )
        );
    end loop;
end $$;
select is(
    (select count(*) from public.recipe_usage_reservations
     where owner_id = '59a357da-b6d3-4e5f-a1a0-5bfe6da31a36' and status = 'reserved'),
    5,
    'five free imports in one week reserve successfully'
);
select is(
    public.recipe_usage_reserve(
        '59a357da-b6d3-4e5f-a1a0-5bfe6da31a36',
        'b0000000-0000-4000-8000-000000000099',
        'smart_import',
        repeat('a', 64),
        '{"origin":"import_job","job_id":"e0000000-0000-4000-8000-000000000005","candidate_ids":["candidate-v2-0123456789abcdef0123456789abcdef"],"session_id":null,"turn_request_id":null}'::jsonb
    ) ->> 'code',
    'QUOTA_EXCEEDED',
    'the sixth free import in one ISO week is rejected'
);

reset role;
select * from finish();
rollback;
