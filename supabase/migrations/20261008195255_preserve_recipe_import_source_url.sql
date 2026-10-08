-- Developer: gengyun
-- Purpose: Preserve optional source URL metadata accepted by the frozen import API.

alter table public.recipe_import_jobs
    add column if not exists original_source_url text;

-- The four-argument RPC is retained only as the wrapper's internal primitive.
-- Clients use the five-argument RPC so every frozen request field participates
-- in authenticated idempotency checks.
revoke all on function public.submit_own_recipe_import(
    uuid, text, text, text
) from public, anon, authenticated;

create or replace function public.submit_own_recipe_import(
    p_client_request_id uuid,
    p_input_type text,
    p_source_value text,
    p_platform_hint text,
    p_original_source_url text
)
returns setof public.recipe_import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_existing public.recipe_import_jobs%rowtype;
    v_job public.recipe_import_jobs%rowtype;
    v_job_id uuid;
    v_authority text;
    v_host text;
begin
    if v_owner is null
       or auth.jwt() ->> 'is_anonymous' = 'true' then
        raise exception 'AUTH_REQUIRED' using errcode = '42501';
    end if;

    if p_original_source_url is not null then
        v_authority := substring(
            p_original_source_url from '^https://([^/?#]+)'
        );
        v_host := lower(split_part(v_authority, ':', 1));
        if length(p_original_source_url) > 8192
           or v_authority is null
           or v_authority !~ '^[A-Za-z0-9.-]+(:443)?$'
           or v_host !~ '^([a-z0-9-]+[.])+[a-z0-9-]+$'
           or v_host ~ '^([0-9]+[.]){3}[0-9]+$'
           or v_host ~ '[.](local|internal|lan|test|invalid|onion)$'
        then
            raise exception 'INVALID_INPUT' using errcode = '22023';
        end if;
    end if;

    -- Serialize metadata comparison with the same per-owner request lock used
    -- by the base RPC, so a replay cannot replace immutable source metadata.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext(v_owner::text)
    );

    select * into v_existing
    from public.recipe_import_jobs
    where owner_id = v_owner
      and client_request_id = p_client_request_id
    for update;

    if found
       and (
           v_existing.original_source_url is distinct from p_original_source_url
           or v_existing.platform_hint is distinct from p_platform_hint
       )
    then
        raise exception 'CLIENT_REQUEST_ID_CONFLICT' using errcode = '23505';
    end if;

    select * into v_job
    from public.submit_own_recipe_import(
        p_client_request_id,
        p_input_type,
        p_source_value,
        p_platform_hint
    );
    v_job_id := v_job.id;

    update public.recipe_import_jobs
    set original_source_url = p_original_source_url,
        updated_at = now()
    where id = v_job_id
      and owner_id = v_owner
      and original_source_url is distinct from p_original_source_url
    returning * into v_job;

    if not found then
        select * into v_job
        from public.recipe_import_jobs
        where id = v_job_id and owner_id = v_owner;
    end if;

    return next v_job;
end;
$$;

revoke all on function public.submit_own_recipe_import(
    uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.submit_own_recipe_import(
    uuid, text, text, text, text
) to authenticated;
