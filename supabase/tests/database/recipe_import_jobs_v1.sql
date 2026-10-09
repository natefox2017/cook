create extension if not exists pgtap;

begin;
select plan(40);

select ok(
    to_regclass('pgmq.q_recipe_import_v1') is not null,
    'migration creates a dedicated V1 PGMQ queue'
);
select ok(
    (select relrowsecurity from pg_class where oid = 'public.recipe_import_jobs'::regclass),
    'job table has row-level security enabled'
);
select ok(
    not has_function_privilege('anon', 'public.submit_own_recipe_import(uuid,text,text,text)', 'EXECUTE'),
    'anonymous users cannot submit jobs'
);
select ok(
    not has_function_privilege('authenticated', 'public.submit_own_recipe_import(uuid,text,text,text)', 'EXECUTE'),
    'authenticated users cannot bypass frozen request validation through the internal RPC'
);
select ok(
    has_function_privilege('authenticated', 'public.submit_own_recipe_import(uuid,text,text,text,text)', 'EXECUTE'),
    'authenticated users can use the full owner-checked submit RPC'
);
select ok(
    not has_function_privilege('anon', 'public.recipe_import_v1_queue_read(integer,integer)', 'EXECUTE'),
    'anonymous users cannot read the V1 queue'
);
select ok(
    not has_function_privilege('authenticated', 'public.recipe_import_v1_queue_read(integer,integer)', 'EXECUTE'),
    'authenticated users cannot read the V1 queue'
);
select ok(
    has_function_privilege('service_role', 'public.recipe_import_v1_queue_read(integer,integer)', 'EXECUTE'),
    'service role can read the V1 queue'
);
select ok(
    has_function_privilege('service_role', 'public.recipe_import_v1_queue_archive(bigint)', 'EXECUTE'),
    'service role can archive V1 messages'
);
select ok(
    not has_function_privilege('anon', 'public.recipe_import_v1_queue_archive(bigint)', 'EXECUTE'),
    'anonymous users cannot archive V1 messages'
);
select ok(
    not has_table_privilege('authenticated', 'public.recipe_import_jobs', 'INSERT'),
    'authenticated users cannot insert job rows directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.recipe_import_jobs', 'UPDATE'),
    'authenticated users cannot update job rows directly'
);
select ok(
    not has_table_privilege('authenticated', 'public.recipe_import_jobs', 'DELETE'),
    'authenticated users cannot delete job rows directly'
);

insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
    ('d2977e89-94ab-4a2e-97eb-0f09b65f8d76', 'authenticated', 'authenticated', 'owner-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('59a357da-b6d3-4e5f-a1a0-5bfe6da31a36', 'authenticated', 'authenticated', 'owner-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

do $$
begin
    if not exists (
        select 1 from pgmq.list_queues()
        where queue_name = 'recipe_import'
    ) then
        perform pgmq.create('recipe_import');
    end if;
    perform set_config(
        'test.legacy_message_id',
        pgmq.send('recipe_import', '{"legacy_marker":"legacy-test-message"}'::jsonb)::text,
        true
    );
end;
$$;

set local role authenticated;
do $$
declare
    v_job public.recipe_import_jobs%rowtype;
    v_owner uuid := 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76';
begin
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_owner,
            'role', 'authenticated',
            'is_anonymous', false
        )::text,
        true
    );
    select * into v_job
    from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'Ingredients: rice\nSteps: cook until done',
        'social',
        'https://social.example/posts/123'
    );
    perform set_config('test.job_id', v_job.id::text, true);
    perform set_config('test.v1_message_id', v_job.queue_message_id::text, true);
end;
$$;

select is(
    (select status from public.recipe_import_jobs where id = current_setting('test.job_id')::uuid),
    'queued'::text,
    'submit returns only after durable V1 queue admission'
);
select is(
    (select id::text from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'Ingredients: rice\nSteps: cook until done',
        'social',
        'https://social.example/posts/123'
    )),
    current_setting('test.job_id'),
    'same request replay returns the existing job'
);
select is(
    (select original_source_url from public.recipe_import_jobs
     where id = current_setting('test.job_id')::uuid),
    'https://social.example/posts/123',
    'optional original source URL is stored with the job'
);
select throws_ok(
    $$select * from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'Ingredients: rice\nSteps: cook until done',
        'social',
        'https://social.example/posts/changed'
    )$$,
    '23505',
    'CLIENT_REQUEST_ID_CONFLICT',
    'same request ID cannot replace immutable source metadata'
);
select throws_ok(
    $$select * from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'Ingredients: rice\nSteps: cook until done',
        'different-platform',
        'https://social.example/posts/123'
    )$$,
    '23505',
    'CLIENT_REQUEST_ID_CONFLICT',
    'same request ID cannot replace platform metadata'
);
select throws_ok(
    $$select * from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'changed source',
        'social',
        'https://social.example/posts/123'
    )$$,
    '23505',
    'CLIENT_REQUEST_ID_CONFLICT',
    'changed source cannot reuse an idempotency key'
);
select throws_ok(
    $$select * from public.submit_own_recipe_import(
        'e0fb0c8c-7a27-48e7-99fd-8d62c46d4caa',
        'text',
        'changed source'
    )$$,
    '42501',
    'permission denied for function submit_own_recipe_import',
    'obsolete defaulted internal RPC remains inaccessible to authenticated users'
);
select is(
    (select count(*)::integer from public.recipe_import_jobs
     where id = current_setting('test.job_id')::uuid and owner_id = auth.uid()),
    1,
    'owner can read their own job through RLS'
);

set local role service_role;
select is(
    (select count(*)::integer
     from public.recipe_import_v1_queue_read(30, 5)
     where message ->> 'job_id' = current_setting('test.job_id')),
    1,
    'V1 consumer reads the submitted V1 message'
);
reset role;
select is(
    (select count(*)::integer
     from pgmq.q_recipe_import_v1
     where message ->> 'legacy_marker' = 'legacy-test-message'),
    0,
    'legacy payload is not present in the V1 queue table'
);
set local role service_role;
select is(
    (select attempt_count from public.claim_recipe_import_job(
        current_setting('test.job_id')::uuid,
        current_setting('test.v1_message_id')::bigint
    )),
    1,
    'worker atomically claims the first delivery attempt'
);
reset role;
do $$
begin
    update public.recipe_import_jobs
    set updated_at = now() - interval '3 minutes'
    where id = current_setting('test.job_id')::uuid;

    update pgmq.q_recipe_import_v1
    set vt = now() - interval '1 second'
    where msg_id = current_setting('test.v1_message_id')::bigint;
end;
$$;
set local role service_role;
select is(
    (select read_ct from public.recipe_import_v1_queue_read(30, 5)
     where msg_id = current_setting('test.v1_message_id')::bigint),
    2::bigint,
    'expired PGMQ visibility makes the same V1 message readable again'
);
select is(
    (select attempt_count from public.claim_recipe_import_job(
        current_setting('test.job_id')::uuid,
        current_setting('test.v1_message_id')::bigint
    )),
    2,
    'expired processing lease is reclaimed as a new attempt'
);
do $$
declare
    v_rows integer;
begin
    update public.recipe_import_jobs
    set status = 'completed', result = '{"stale":true}'::jsonb
    where id = current_setting('test.job_id')::uuid
      and queue_message_id = current_setting('test.v1_message_id')::bigint
      and attempt_count = 1;
    get diagnostics v_rows = row_count;
    perform set_config('test.stale_update_count', v_rows::text, true);
end;
$$;
select is(
    current_setting('test.stale_update_count')::integer,
    0,
    'stale worker from attempt one cannot write over attempt two'
);
reset role;
select ok(
    exists (select 1 from pgmq.q_recipe_import_v1
            where msg_id = current_setting('test.v1_message_id')::bigint),
    'claimed message remains unacknowledged before result persistence'
);
set local role service_role;
do $$
declare
    v_rows integer;
begin
    update public.recipe_import_jobs
    set status = 'completed', stage = 'done', result = '{"test":"saved"}'::jsonb,
        completed_at = now(), updated_at = now()
    where id = current_setting('test.job_id')::uuid
      and queue_message_id = current_setting('test.v1_message_id')::bigint
      and status = 'extracting'
      and attempt_count = 2;
    get diagnostics v_rows = row_count;
    perform set_config('test.saved_update_count', v_rows::text, true);
end;
$$;
select is(
    current_setting('test.saved_update_count')::integer,
    1,
    'current attempt persists the terminal result'
);
select is(
    (select status from public.recipe_import_jobs where id = current_setting('test.job_id')::uuid),
    'completed'::text,
    'durable result is visible before queue ACK'
);
select ok(
    public.recipe_import_v1_queue_archive(current_setting('test.v1_message_id')::bigint),
    'V1 consumer can archive its own message'
);

reset role;
select ok(
    exists (select 1 from pgmq.a_recipe_import_v1
            where msg_id = current_setting('test.v1_message_id')::bigint),
    'V1 message is archived in the V1 archive table'
);
select ok(
    exists (select 1 from pgmq.q_recipe_import
            where msg_id = current_setting('test.legacy_message_id')::bigint),
    'legacy message remains pending after V1 read and archive'
);
select ok(
    not exists (select 1 from pgmq.a_recipe_import
                where msg_id = current_setting('test.legacy_message_id')::bigint),
    'V1 archive does not move legacy messages'
);

set local role authenticated;
do $$
declare
    v_owner uuid := '59a357da-b6d3-4e5f-a1a0-5bfe6da31a36';
begin
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_owner,
            'role', 'authenticated',
            'is_anonymous', false
        )::text,
        true
    );
end;
$$;
select is(
    (select count(*)::integer from public.recipe_import_jobs
     where id = current_setting('test.job_id')::uuid),
    0,
    'another account cannot read the job through RLS'
);
select throws_ok(
    $$select * from public.retry_own_recipe_import(current_setting('test.job_id')::uuid)$$,
    'P0002',
    'NOT_FOUND',
    'another account cannot retry the job'
);

reset role;
update public.recipe_import_jobs
set status = 'failed', error = '{"recoverable":true}'::jsonb
where id = current_setting('test.job_id')::uuid;
set local role authenticated;
do $$
declare
    v_owner uuid := 'd2977e89-94ab-4a2e-97eb-0f09b65f8d76';
    v_job public.recipe_import_jobs%rowtype;
begin
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform set_config(
        'request.jwt.claims',
        jsonb_build_object(
            'sub', v_owner,
            'role', 'authenticated',
            'is_anonymous', false
        )::text,
        true
    );
    select * into v_job
    from public.retry_own_recipe_import(current_setting('test.job_id')::uuid);
    perform set_config('test.retry_status', v_job.status, true);
    perform set_config('test.retry_message_id', v_job.queue_message_id::text, true);
end;
$$;
select is(current_setting('test.retry_status'), 'queued', 'recoverable owner retry is re-queued');
select is(
    current_setting('test.retry_message_id')::bigint <> current_setting('test.v1_message_id')::bigint,
    true,
    'retry admits a new durable queue message for the existing job'
);
reset role;
select ok(
    exists (select 1 from pgmq.q_recipe_import_v1
            where msg_id = current_setting('test.retry_message_id')::bigint
              and message ->> 'job_id' = current_setting('test.job_id')),
    'retry message is admitted to the V1 queue'
);
set local role authenticated;
select throws_ok(
    $$select * from public.retry_own_recipe_import(current_setting('test.job_id')::uuid)$$,
    '23505',
    'NOT_RETRYABLE',
    'queued job cannot be retried twice'
);

reset role;
select * from finish();
rollback;
