-- Developer: gengyun
-- Purpose: Add private owner-scoped import artifacts with bounded retention.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'recipe-import-artifacts',
    'recipe-import-artifacts',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'application/pdf', 'text/plain']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.recipe_import_artifacts (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    client_request_id uuid not null,
    input_type text not null check (input_type in ('image', 'file')),
    kind text not null check (kind in ('original', 'screenshot')),
    storage_bucket text not null default 'recipe-import-artifacts'
        check (storage_bucket = 'recipe-import-artifacts'),
    storage_path text not null unique,
    mime_type text not null check (mime_type in (
        'image/jpeg', 'image/png', 'image/heic', 'image/heif',
        'application/pdf', 'text/plain'
    )),
    size_bytes bigint not null check (size_bytes between 1 and 10485760),
    checksum_sha256 text check (
        checksum_sha256 is null or checksum_sha256 ~ '^[a-fA-F0-9]{64}$'
    ),
    state text not null default 'upload_pending' check (state in (
        'upload_pending', 'available', 'rejected', 'expired'
    )),
    expires_at timestamptz not null,
    uploaded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, owner_id),
    unique (owner_id, client_request_id),
    check (
        (input_type = 'image' and kind = 'screenshot' and mime_type like 'image/%')
        or (input_type = 'file' and kind = 'original'
            and mime_type in ('application/pdf', 'text/plain'))
    )
);

create index if not exists recipe_import_artifacts_expiry_idx
    on public.recipe_import_artifacts (expires_at)
    where state in ('upload_pending', 'available', 'rejected');

alter table public.recipe_import_artifacts enable row level security;
revoke all on public.recipe_import_artifacts from public, anon, authenticated;
grant select on public.recipe_import_artifacts to authenticated;
grant all on public.recipe_import_artifacts to service_role;

drop policy if exists "read own recipe import artifacts"
    on public.recipe_import_artifacts;
create policy "read own recipe import artifacts"
    on public.recipe_import_artifacts
    for select to authenticated
    using (owner_id = (select auth.uid()));

-- The bucket is private and has no end-user Storage object policies. Authenticated
-- Edge Functions verify artifact ownership before issuing short-lived signed URLs.

alter table public.recipe_import_jobs
    add column if not exists artifact_id uuid;
alter table public.recipe_import_jobs
    drop constraint if exists recipe_import_jobs_artifact_owner_fkey;
alter table public.recipe_import_jobs
    add constraint recipe_import_jobs_artifact_owner_fkey
        foreign key (artifact_id, owner_id)
        references public.recipe_import_artifacts(id, owner_id)
        on delete cascade;

alter table public.recipe_import_jobs
    drop constraint if exists recipe_import_jobs_input_type_check;
alter table public.recipe_import_jobs
    add constraint recipe_import_jobs_input_type_check
        check (input_type in ('url', 'text', 'image', 'file'));
alter table public.recipe_import_jobs
    drop constraint if exists recipe_import_jobs_artifact_input_check;
alter table public.recipe_import_jobs
    add constraint recipe_import_jobs_artifact_input_check
        check (
            (input_type in ('url', 'text') and artifact_id is null)
            or (input_type in ('image', 'file') and artifact_id is not null)
        );

create index if not exists recipe_import_jobs_artifact_idx
    on public.recipe_import_jobs (artifact_id)
    where artifact_id is not null;

create or replace function public.submit_own_recipe_artifact_import(
    p_client_request_id uuid,
    p_input_type text,
    p_artifact_id uuid,
    p_platform_hint text default null,
    p_original_source_url text default null
)
returns setof public.recipe_import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_artifact public.recipe_import_artifacts%rowtype;
    v_job public.recipe_import_jobs%rowtype;
    v_message_id bigint;
    v_source text;
begin
    if v_owner is null or auth.jwt() ->> 'is_anonymous' = 'true' then
        raise exception 'AUTH_REQUIRED' using errcode = '42501';
    end if;
    if p_client_request_id is null
       or p_input_type not in ('image', 'file')
       or p_artifact_id is null
       or length(coalesce(p_platform_hint, '')) > 80 then
        raise exception 'INVALID_INPUT' using errcode = '22023';
    end if;

    v_source := p_artifact_id::text;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_owner::text));
    select * into v_job from public.recipe_import_jobs
    where owner_id = v_owner and client_request_id = p_client_request_id
    for update;
    if found then
        if v_job.input_type <> p_input_type
           or v_job.artifact_id <> p_artifact_id
           or v_job.platform_hint is distinct from p_platform_hint
           or v_job.original_source_url is distinct from p_original_source_url then
            raise exception 'CLIENT_REQUEST_ID_CONFLICT' using errcode = '23505';
        end if;
        return next v_job;
        return;
    end if;

    select * into v_artifact
    from public.recipe_import_artifacts
    where id = p_artifact_id and owner_id = v_owner
    for update;
    if not found
       or v_artifact.input_type <> p_input_type
       or v_artifact.state <> 'available'
       or v_artifact.expires_at <= now() then
        raise exception 'ARTIFACT_NOT_READY' using errcode = 'P0001';
    end if;

    if (select count(*) from public.recipe_import_jobs
        where owner_id = v_owner
          and created_at >= now() - interval '1 hour') >= 30 then
        raise exception 'RATE_LIMITED' using errcode = 'P0001';
    end if;

    insert into public.recipe_import_jobs (
        owner_id, client_request_id, input_type, source_value,
        source_fingerprint, platform_hint, original_source_url, artifact_id
    ) values (
        v_owner, p_client_request_id, p_input_type, v_source,
        md5(p_input_type || ':' || v_source), p_platform_hint,
        p_original_source_url, p_artifact_id
    ) returning * into v_job;

    select s.send into v_message_id
    from pgmq.send(
        'recipe_import_v1'::text,
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

revoke all on function public.submit_own_recipe_artifact_import(
    uuid, text, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.submit_own_recipe_artifact_import(
    uuid, text, uuid, text, text
) to authenticated;
