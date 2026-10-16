-- Developer: gengyun
-- Purpose: DEV-78 additive SOURCE (not applied): atomically reserve the premium
--          media_import quota plus one smart_import unit per selected candidate
--          under ONE media-import business operation, reusing the existing
--          DEV-427/438 ledger functions, (owner,capability) advisory locks and
--          operation identity. No PK rewrite, no new table/queue, no reserved_units
--          change. Whole transaction rolls back if any item is blocked.

-- Stable child operation id for a candidate of one media job. Deterministic so a
-- replay derives the same operation id and the existing reserve returns REPLAY.
create or replace function public.recipe_usage_candidate_operation_id(
    p_job_id uuid, p_candidate_id text
)
returns uuid
language sql immutable set search_path = ''
as $$
    select md5(p_job_id::text || ':' || p_candidate_id)::uuid
$$;

-- p_candidates = [{candidate_id text, input_hash text(64hex), source jsonb}, ...]
--   source = {origin:'import_job', job_id, candidate_ids:[candidate], session_id, turn_request_id}
create or replace function public.recipe_usage_reserve_media_bundle(
    p_owner_id uuid,
    p_job_id uuid,
    p_media_source jsonb,
    p_media_input_hash text,
    p_candidates jsonb
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_media_result jsonb;
    v_candidate_source jsonb;
    v_candidate_id text;
    v_candidate_hash text;
    v_candidate_operation_id uuid;
    v_candidate_result jsonb;
    v_code text;
begin
    if p_owner_id is null or p_job_id is null
       or p_media_source is null or jsonb_typeof(p_media_source) <> 'object'
       or p_media_input_hash is null or p_media_input_hash !~ '^[0-9a-f]{64}$'
       or p_candidates is null or jsonb_typeof(p_candidates) <> 'array'
       or jsonb_array_length(p_candidates) = 0
       or jsonb_array_length(p_candidates) > 8 then
        return jsonb_build_object('code', 'INVALID_INPUT');
    end if;

    -- Deterministic lock order: media_import first, then smart_import. Both
    -- reserve functions take the (owner, capability) advisory xact lock, so this
    -- fixed order plus the existing single-capability paths cannot deadlock.
    v_media_result := public.recipe_usage_reserve_internal(
        p_owner_id, p_job_id, 'media_import', p_media_input_hash, p_media_source
    );
    v_code := v_media_result ->> 'code';
    if v_code not in ('RESERVED', 'REPLAY') then
        raise exception 'MEDIA_BUNDLE_BLOCKED:%', v_code using errcode = 'P0001';
    end if;

    for v_candidate_source in select value from jsonb_array_elements(p_candidates) loop
        v_candidate_id := v_candidate_source ->> 'candidate_id';
        v_candidate_hash := v_candidate_source ->> 'input_hash';
        if v_candidate_id is null or v_candidate_hash is null
           or v_candidate_hash !~ '^[0-9a-f]{64}$'
           or v_candidate_source -> 'source' is null
           or jsonb_typeof(v_candidate_source -> 'source') <> 'object' then
            raise exception 'MEDIA_BUNDLE_INVALID_CANDIDATE' using errcode = 'P0001';
        end if;
        v_candidate_operation_id := public.recipe_usage_candidate_operation_id(
            p_job_id, v_candidate_id
        );
        v_candidate_result := public.recipe_usage_reserve(
            p_owner_id, v_candidate_operation_id, 'smart_import',
            v_candidate_hash, v_candidate_source -> 'source'
        );
        v_code := v_candidate_result ->> 'code';
        if v_code not in ('RESERVED', 'REPLAY') then
            raise exception 'MEDIA_BUNDLE_BLOCKED:%', v_code using errcode = 'P0001';
        end if;
    end loop;

    return jsonb_build_object(
        'code', 'RESERVED',
        'operation_id', p_job_id::text,
        'reserved_candidates', jsonb_array_length(p_candidates)
    );
end;
$$;

revoke all on function public.recipe_usage_candidate_operation_id(uuid, text)
    from public, anon, authenticated;
revoke all on function public.recipe_usage_reserve_media_bundle(uuid, uuid, jsonb, text, jsonb)
    from public, anon, authenticated;
grant execute on function public.recipe_usage_reserve_media_bundle(uuid, uuid, jsonb, text, jsonb)
    to service_role;
