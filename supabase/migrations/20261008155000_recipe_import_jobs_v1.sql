-- Developer: gengyun
-- Purpose: Create owner-scoped, versioned import jobs with transactional PGMQ admission.

-- The existing durable pgmq.q_recipe_import queue is reused. All three
-- operations below are one Postgres transaction per RPC request, so an
-- unsuccessful enqueue cannot leave a job falsely marked queued.
create table if not exists public.recipe_import_jobs (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    client_request_id uuid not null,
    input_type text not null check (input_type in ('url', 'text')),
    source_value text not null,
    source_fingerprint text not null,
    platform_hint text,
    status text not null default 'received'
        check (status in (
            'received', 'queued', 'extracting',
            'parsing', 'validating', 'completed', 'failed'
        )),
    stage text not null default 'receive',
    attempt_count integer not null default 0 check (attempt_count >= 0),
    queue_message_id bigint,
    server_received_at timestamptz not null default now(),
    queue_confirmed_at timestamptz,
    recipe_id uuid,
    recipe_status text check (recipe_status in ('ready', 'needs_review')),
    review_count integer not null default 0 check (review_count >= 0),
    result jsonb,
    error jsonb,
    completed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (owner_id, client_request_id)
);

comment on table public.recipe_import_jobs is
    'Owner-scoped RecipePouch asynchronous import jobs; V1 HTTP contract.';

create index if not exists recipe_import_jobs_owner_created_idx
    on public.recipe_import_jobs(owner_id, created_at desc);

create index if not exists recipe_import_jobs_owner_fingerprint_idx
    on public.recipe_import_jobs(owner_id, source_fingerprint);

create index if not exists recipe_import_jobs_pending_idx
    on public.recipe_import_jobs(status, created_at)
    where status in ('received', 'queued', 'extracting', 'parsing', 'validating');

alter table public.recipe_import_jobs enable row level security;

drop policy if exists "read own recipe import jobs" on public.recipe_import_jobs;
create policy "read own recipe import jobs"
    on public.recipe_import_jobs
    for select to authenticated
    using (owner_id = (select auth.uid()));

-- No owner can tamper with job status, queue ID, evidence or result by direct
-- REST insert/update/delete. A limited validated RPC owns writes.
revoke all on public.recipe_import_jobs from public, anon, authenticated;
grant select on public.recipe_import_jobs to authenticated;
grant all on public.recipe_import_jobs to service_role;

create or replace function public.submit_own_recipe_import(
    p_client_request_id uuid,
    p_input_type text,
    p_source_value text,
    p_platform_hint text default null
)
returns setof public.recipe_import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_job public.recipe_import_jobs%rowtype;
    v_message_id bigint;
    v_source text;
    v_fingerprint text;
    v_authority text;
    v_host text;
begin
    if v_owner is null
       or auth.jwt() ->> 'is_anonymous' = 'true' then
        raise exception 'AUTH_REQUIRED' using errcode = '42501';
    end if;

    if p_client_request_id is null
       or p_input_type is null
       or p_input_type not in ('url','text')
       or p_source_value is null then
        raise exception 'INVALID_INPUT' using errcode = '22023';
    end if;

    v_source := btrim(p_source_value);
    if length(v_source) < 1
       or (p_input_type = 'text' and length(v_source) > 100000)
       or length(coalesce(p_platform_hint,'')) > 80 then
        raise exception 'INVALID_INPUT' using errcode = '22023';
    end if;

    if p_input_type = 'url' then
        -- Direct authenticated RPC calls must receive the same URL preflight
        -- as the Edge API. This never replaces DNS-pinned fetch protections.
        v_authority := substring(v_source from '^https://([^/?#]+)');
        v_host := lower(split_part(v_authority, ':', 1));
        if length(v_source) > 8192
           or v_authority is null
           or v_authority !~ '^[A-Za-z0-9.-]+(:443)?$'
           or v_host !~ '^([a-z0-9-]+[.])+[a-z0-9-]+$'
           or v_host ~ '^([0-9]+[.]){3}[0-9]+$'
           or v_host ~ '[.](local|internal|lan|test|invalid|onion)$'
        then
            raise exception 'INVALID_INPUT' using errcode = '22023';
        end if;
    end if;

    -- This is an index hint for owner-local dedup, not a cryptographic
    -- authorization token. The original source stays untouched in the row.
    v_fingerprint := md5(p_input_type || ':' || v_source);

    -- Serialize creates for the same owner before checking quota and unique
    -- idempotency. This does not grant any cross-user access.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_owner::text));

    select * into v_job from public.recipe_import_jobs
    where owner_id = v_owner
      and client_request_id = p_client_request_id
    for update;

    if found then
        -- The persisted source is the unmodified input, not v_source (which
        -- is trimmed solely for validation/fingerprinting). Comparing against
        -- the trimmed value makes identical requests with outer whitespace
        -- fail their own idempotent replay.
        if v_job.input_type <> p_input_type
           or v_job.source_value <> p_source_value then
            raise exception 'CLIENT_REQUEST_ID_CONFLICT' using errcode = '23505';
        end if;
        return next v_job;
        return;
    end if;

    if (select count(*) from public.recipe_import_jobs
        where owner_id = v_owner
          and created_at >= now() - interval '1 hour') >= 30 then
        raise exception 'RATE_LIMITED' using errcode = 'P0001';
    end if;

    insert into public.recipe_import_jobs (
        owner_id, client_request_id, input_type, source_value,
        source_fingerprint, platform_hint
    ) values (
        v_owner, p_client_request_id, p_input_type, p_source_value,
        v_fingerprint, p_platform_hint
    ) returning * into v_job;

    -- pgmq uses a logged queue. Message send and job status commit together.
    select s.send into v_message_id
    from pgmq.send(
        'recipe_import'::text,
        pg_catalog.jsonb_build_object(
            'contract_version', 1,
            'job_id', v_job.id,
            'owner_id', v_owner
        )
    ) as s(send);

    if v_message_id is null then
        raise exception 'QUEUE_UNAVAILABLE' using errcode = 'P0001';
    end if;

    update public.recipe_import_jobs
    set status = 'queued',
        stage = 'receive',
        queue_message_id = v_message_id,
        queue_confirmed_at = now(),
        updated_at = now()
    where id = v_job.id
    returning * into v_job;

    return next v_job;
end;
$$;

revoke all on function public.submit_own_recipe_import(
    uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_own_recipe_import(
    uuid, text, text, text
) to authenticated;

create or replace function public.retry_own_recipe_import(
    p_job_id uuid
)
returns setof public.recipe_import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_job public.recipe_import_jobs%rowtype;
    v_message_id bigint;
begin
    if v_owner is null
       or auth.jwt() ->> 'is_anonymous' = 'true' then
        raise exception 'AUTH_REQUIRED' using errcode = '42501';
    end if;

    select * into v_job from public.recipe_import_jobs
    where owner_id = v_owner and id = p_job_id
    for update;

    if not found then
        raise exception 'NOT_FOUND' using errcode = 'P0002';
    end if;

    if v_job.status <> 'failed'
       or v_job.attempt_count >= 3
       or coalesce(v_job.error ->> 'recoverable','false') <> 'true' then
        raise exception 'NOT_RETRYABLE' using errcode = '23505';
    end if;

    select s.send into v_message_id
    from pgmq.send(
        'recipe_import'::text,
        pg_catalog.jsonb_build_object(
            'contract_version', 1,
            'job_id', v_job.id,
            'owner_id', v_owner,
            'retry', true
        )
    ) as s(send);

    if v_message_id is null then
        raise exception 'QUEUE_UNAVAILABLE' using errcode = 'P0001';
    end if;

    update public.recipe_import_jobs
    set status = 'queued',
        stage = 'receive',
        queue_message_id = v_message_id,
        queue_confirmed_at = now(),
        error = null,
        updated_at = now()
    where id = v_job.id
    returning * into v_job;

    return next v_job;
end;
$$;

revoke all on function public.retry_own_recipe_import(uuid)
    from public, anon, authenticated;
grant execute on function public.retry_own_recipe_import(uuid)
    to authenticated;

-- Service-only processing lease. Queue messages are at-least-once: claiming
-- must be atomic, must reject superseded message IDs, and must recover after
-- worker crashes. Job result writes are restricted to the service role.
create or replace function public.claim_recipe_import_job(
    p_job_id uuid,
    p_message_id bigint
)
returns setof public.recipe_import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_job public.recipe_import_jobs%rowtype;
begin
    select * into v_job
    from public.recipe_import_jobs
    where id = p_job_id
    for update;

    if not found
       or v_job.queue_message_id is distinct from p_message_id then
        return;
    end if;

    if not (
        v_job.status = 'queued'
        or (
            v_job.status in ('extracting', 'parsing', 'validating')
            and v_job.updated_at < now() - interval '2 minutes'
        )
    ) then
        return;
    end if;

    if v_job.attempt_count >= 3 then
        update public.recipe_import_jobs
        set status = 'failed', stage = 'done',
            error = pg_catalog.jsonb_build_object(
                'code','INTERNAL_ERROR',
                'message','Processing stopped after repeated interruptions.',
                'recoverable',false,
                'request_id',gen_random_uuid()
            ),
            completed_at = now(), updated_at = now()
        where id = p_job_id
        returning * into v_job;
        return next v_job;
        return;
    end if;

    update public.recipe_import_jobs
    set status = 'extracting', stage = 'extract',
        attempt_count = attempt_count + 1,
        updated_at = now()
    where id = p_job_id
    returning * into v_job;

    return next v_job;
end;
$$;

revoke all on function public.claim_recipe_import_job(uuid, bigint)
    from public, anon, authenticated;
grant execute on function public.claim_recipe_import_job(uuid, bigint)
    to service_role;
