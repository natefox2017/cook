-- Developer: gengyun
-- Purpose: DEV-438 phase-II server-internal metering increment. Extends the DEV-427 owner-scoped usage
--          ledger with the three frozen premium capabilities (recipe_question 100, recipe_translation 20,
--          media_import 20 per UTC month) through two service-role-only RPCs. The public V1 wire contract,
--          save origins and DTOs are deliberately unchanged: the three capabilities never enter the public
--          save routes and the public reserve/commit/finalize/ack surface is untouched.
--          Additive only; it never alters the import, draft, token-budget or subscription write paths.

-- ---------------------------------------------------------------------------
-- 1. Widen the three capability CHECKs to the five metered capabilities. Private
--    tables only; no public/API impact. The single-column CHECK names are the
--    deterministic Postgres defaults (<table>_capability_check).
-- ---------------------------------------------------------------------------
alter table public.recipe_usage_counters
    drop constraint if exists recipe_usage_counters_capability_check,
    add constraint recipe_usage_counters_capability_check
        check (capability in ('smart_import', 'ai_edit', 'recipe_question', 'recipe_translation', 'media_import'));

alter table public.recipe_usage_reservations
    drop constraint if exists recipe_usage_reservations_capability_check,
    add constraint recipe_usage_reservations_capability_check
        check (capability in ('smart_import', 'ai_edit', 'recipe_question', 'recipe_translation', 'media_import'));

alter table public.recipe_usage_finalizations
    drop constraint if exists recipe_usage_finalizations_capability_check,
    add constraint recipe_usage_finalizations_capability_check
        check (capability in ('smart_import', 'ai_edit', 'recipe_question', 'recipe_translation', 'media_import'));

-- ---------------------------------------------------------------------------
-- 2. Frozen period: add the three premium-only branches. Free/expired owners have
--    no branch and still resolve to null, so reserve refuses (no free bucket, no
--    loophole). Limits are the frozen POLICY values, not new invention.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_period(p_capability text, p_tier text, p_at timestamptz)
returns jsonb
language sql stable set search_path = ''
as $$
    select case
        when p_capability = 'smart_import' and p_tier = 'free' then jsonb_build_object(
            'period_type', 'iso_week',
            'period_start', to_char(date_trunc('week', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('week', p_at at time zone 'UTC') + interval '7 days', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 5
        )
        when p_capability = 'smart_import' and p_tier = 'premium' then jsonb_build_object(
            'period_type', 'utc_month',
            'period_start', to_char(date_trunc('month', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('month', p_at at time zone 'UTC') + interval '1 month', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 100
        )
        when p_capability = 'ai_edit' and p_tier = 'free' then jsonb_build_object(
            'period_type', 'lifetime',
            'period_start', null,
            'reset_at', null,
            'limit', 3
        )
        when p_capability = 'ai_edit' and p_tier = 'premium' then jsonb_build_object(
            'period_type', 'utc_month',
            'period_start', to_char(date_trunc('month', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('month', p_at at time zone 'UTC') + interval '1 month', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 30
        )
        when p_capability = 'recipe_question' and p_tier = 'premium' then jsonb_build_object(
            'period_type', 'utc_month',
            'period_start', to_char(date_trunc('month', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('month', p_at at time zone 'UTC') + interval '1 month', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 100
        )
        when p_capability = 'recipe_translation' and p_tier = 'premium' then jsonb_build_object(
            'period_type', 'utc_month',
            'period_start', to_char(date_trunc('month', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('month', p_at at time zone 'UTC') + interval '1 month', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 20
        )
        when p_capability = 'media_import' and p_tier = 'premium' then jsonb_build_object(
            'period_type', 'utc_month',
            'period_start', to_char(date_trunc('month', p_at at time zone 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'reset_at', to_char(date_trunc('month', p_at at time zone 'UTC') + interval '1 month', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'limit', 20
        )
        else null
    end
$$;

-- ---------------------------------------------------------------------------
-- 3. Settle: book a reservation's used unit into its OWN capability bucket. The
--    DEV-427 v1 settle hardcodes ai_edit in its non-smart_import branch, which
--    would mis-book the three phase-II capabilities; this additive replacement
--    keeps smart_import (week + month) and ai_edit identical and routes every
--    other capability to v_res.capability.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_settle(
    p_owner_id uuid, p_operation_id uuid, p_capability text, p_input_hash text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_res public.recipe_usage_reservations%rowtype;
    v_week_start timestamptz;
    v_month_start timestamptz;
begin
    select * into v_res from public.recipe_usage_reservations where operation_id = p_operation_id;
    if not found or v_res.owner_id <> p_owner_id then
        return jsonb_build_object('code', 'NOT_FOUND');
    end if;
    if v_res.input_hash <> p_input_hash or v_res.capability <> p_capability then
        return jsonb_build_object('code', 'IDEMPOTENCY_CONFLICT');
    end if;
    if v_res.status = 'committed' then
        return jsonb_build_object('code', 'COMMITTED', 'reservation', public.recipe_usage_reservation_json(v_res));
    end if;
    if v_res.status in ('released', 'expired') then
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;
    if v_res.status = 'reserved' and v_res.reserved_until < now() then
        update public.recipe_usage_counters
            set reserved = reserved - v_res.reserved_units
            where owner_id = p_owner_id and capability = v_res.capability
              and period_type = v_res.period_type
              and period_start is not distinct from v_res.period_start;
        update public.recipe_usage_reservations
            set status = 'expired', updated_at = now()
            where operation_id = p_operation_id;
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;

    update public.recipe_usage_counters
        set reserved = reserved - v_res.reserved_units
        where owner_id = p_owner_id and capability = v_res.capability
          and period_type = v_res.period_type
          and period_start is not distinct from v_res.period_start;

    if v_res.capability = 'smart_import' then
        v_week_start := date_trunc('week', v_res.reserved_at at time zone 'UTC') at time zone 'UTC';
        v_month_start := date_trunc('month', v_res.reserved_at at time zone 'UTC') at time zone 'UTC';
        insert into public.recipe_usage_counters(owner_id, capability, period_type, period_start, used, reserved)
        values (p_owner_id, 'smart_import', 'iso_week', v_week_start, 1, 0)
        on conflict on constraint recipe_usage_counters_unique_period
        do update set used = public.recipe_usage_counters.used + 1;
        insert into public.recipe_usage_counters(owner_id, capability, period_type, period_start, used, reserved)
        values (p_owner_id, 'smart_import', 'utc_month', v_month_start, 1, 0)
        on conflict on constraint recipe_usage_counters_unique_period
        do update set used = public.recipe_usage_counters.used + 1;
    else
        insert into public.recipe_usage_counters(owner_id, capability, period_type, period_start, used, reserved)
        values (p_owner_id, v_res.capability, v_res.period_type, v_res.period_start, 1, 0)
        on conflict on constraint recipe_usage_counters_unique_period
        do update set used = public.recipe_usage_counters.used + 1;
    end if;

    update public.recipe_usage_reservations
        set status = 'committed', committed_at = now(), updated_at = now()
        where operation_id = p_operation_id
        returning * into v_res;
    return jsonb_build_object('code', 'COMMITTED', 'reservation', public.recipe_usage_reservation_json(v_res));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Internal origin allowlist. Each capability carries exactly one binding UUID
--    that the calling handler has already verified for this owner; no other
--    internal origin field may be set. Keeps the public RecipeUsageOrigin enum
--    (import_job | draft_approval) untouched.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_internal_source_valid(p_capability text, p_source jsonb)
returns boolean
language sql immutable set search_path = ''
as $$
    select p_source is not null
        and jsonb_typeof(p_source) = 'object'
        and p_source ->> 'origin' = p_capability
        and case p_capability
            when 'recipe_question' then
                (p_source ->> 'recipe_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                and (p_source ->> 'turn_request_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                and not (p_source ? 'proposal_id') and not (p_source ? 'media_task_id')
            when 'recipe_translation' then
                (p_source ->> 'proposal_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                and not (p_source ? 'recipe_id') and not (p_source ? 'turn_request_id')
                and not (p_source ? 'media_task_id')
            when 'media_import' then
                (p_source ->> 'media_task_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                and not (p_source ? 'recipe_id') and not (p_source ? 'turn_request_id')
                and not (p_source ? 'proposal_id')
            else false
        end
$$;

-- ---------------------------------------------------------------------------
-- 5. Server-internal reserve. SECURITY DEFINER, empty search_path, service-role
--    only. Identical to recipe_usage_reserve except:
--      (a) the allowlist is the three phase-II capabilities (the public origin
--          pair must never reach here);
--      (b) entitlement must resolve to premium, else UPGRADE_REQUIRED;
--      (c) the source is validated against the internal origin allowlist above.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_reserve_internal(
    p_owner_id uuid, p_operation_id uuid, p_capability text, p_input_hash text, p_source jsonb
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_existing public.recipe_usage_reservations%rowtype;
    v_ent jsonb;
    v_tier text;
    v_period jsonb;
    v_counter public.recipe_usage_counters%rowtype;
    v_limit bigint;
    v_period_start timestamptz;
    v_reserved_until timestamptz;
begin
    if p_owner_id is null or p_operation_id is null
       or p_capability not in ('recipe_question', 'recipe_translation', 'media_import')
       or p_input_hash is null or p_input_hash !~ '^[0-9a-f]{64}$'
       or not public.recipe_usage_internal_source_valid(p_capability, p_source) then
        return jsonb_build_object('code', 'INVALID_INPUT');
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_owner_id::text || ':' || p_capability, 427)
    );

    select * into v_existing from public.recipe_usage_reservations where operation_id = p_operation_id;
    if found then
        if v_existing.owner_id <> p_owner_id then
            return jsonb_build_object('code', 'NOT_FOUND');
        end if;
        if v_existing.capability <> p_capability or v_existing.input_hash <> p_input_hash
           or v_existing.source is distinct from p_source then
            return jsonb_build_object('code', 'IDEMPOTENCY_CONFLICT');
        end if;
        return jsonb_build_object('code', 'REPLAY', 'reservation', public.recipe_usage_reservation_json(v_existing));
    end if;

    perform public.recipe_usage_expire_stale(p_owner_id, p_capability);

    v_ent := public.recipe_usage_entitlement(p_owner_id);
    v_tier := v_ent ->> 'tier';
    if v_tier <> 'premium' then
        return jsonb_build_object(
            'code', 'UPGRADE_REQUIRED',
            'status', v_ent ->> 'status',
            'period', public.recipe_usage_period(p_capability, v_tier, now())
        );
    end if;

    v_period := public.recipe_usage_period(p_capability, v_tier, now());
    if v_period is null then
        return jsonb_build_object('code', 'INVALID_INPUT');
    end if;
    v_limit := (v_period ->> 'limit')::bigint;
    v_period_start := case
        when v_period ->> 'period_start' is null then null
        else (v_period ->> 'period_start')::timestamptz
    end;

    select * into v_counter from public.recipe_usage_counters
        where owner_id = p_owner_id and capability = p_capability
          and period_type = v_period ->> 'period_type'
          and period_start is not distinct from v_period_start
        for update;
    if not found then
        insert into public.recipe_usage_counters(owner_id, capability, period_type, period_start, used, reserved)
        values (p_owner_id, p_capability, v_period ->> 'period_type', v_period_start, 0, 0)
        returning * into v_counter;
    end if;

    if v_counter.used + v_counter.reserved + 1 > v_limit then
        return jsonb_build_object(
            'code', 'QUOTA_EXCEEDED',
            'reset_at', v_period ->> 'reset_at'
        );
    end if;

    update public.recipe_usage_counters
        set reserved = reserved + 1
        where owner_id = p_owner_id and capability = p_capability
          and period_type = v_period ->> 'period_type'
          and period_start is not distinct from v_period_start;

    v_reserved_until := now() + interval '600 seconds';
    insert into public.recipe_usage_reservations(
        operation_id, owner_id, capability, input_hash, source, status,
        tier_at_reserve, policy_version, period_type, period_start, reserved_units,
        reserved_until, reserved_at
    ) values (
        p_operation_id, p_owner_id, p_capability, p_input_hash, p_source, 'reserved',
        v_tier, 1, v_period ->> 'period_type', v_period_start, 1,
        v_reserved_until, now()
    ) returning * into v_existing;

    return jsonb_build_object('code', 'RESERVED', 'reservation', public.recipe_usage_reservation_json(v_existing));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Finalizations binding (additive, keeps existing rows valid).
-- ---------------------------------------------------------------------------
alter table public.recipe_usage_finalizations
    alter column recipe_id drop not null;
alter table public.recipe_usage_finalizations
    add column if not exists result_id uuid;
alter table public.recipe_usage_finalizations
    add column if not exists result_kind text not null default 'recipe'
        check (result_kind in ('recipe', 'answer', 'translation', 'media_task'));
alter table public.recipe_usage_finalizations
    drop constraint if exists recipe_usage_finalizations_outcome;
alter table public.recipe_usage_finalizations
    add constraint recipe_usage_finalizations_outcome
        check ((result_kind = 'recipe') = (result_id is null));

-- ---------------------------------------------------------------------------
-- 7. Server-internal finalize. SECURITY DEFINER, empty search_path, service-role
--    only. Settles the reservation once via the existing recipe_usage_settle and
--    records the outcome bound to an already-persisted owned result row. A replay,
--    or a new operation for the same (owner, capability, input_hash), returns the
--    same durable outcome without a second charge.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_finalize_internal(
    p_owner_id uuid, p_operation_id uuid, p_capability text, p_input_hash text,
    p_source jsonb, p_recipe_id uuid, p_payload_hash text, p_payload jsonb,
    p_result_kind text, p_result_id uuid
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_final public.recipe_usage_finalizations%rowtype;
    v_res public.recipe_usage_reservations%rowtype;
    v_capability text;
    v_settle jsonb;
begin
    if p_owner_id is null or p_operation_id is null
       or p_capability not in ('recipe_question', 'recipe_translation', 'media_import')
       or p_input_hash is null or p_input_hash !~ '^[0-9a-f]{64}$'
       or not public.recipe_usage_internal_source_valid(p_capability, p_source)
       or p_payload_hash is null or p_payload_hash !~ '^[0-9a-f]{64}$'
       or p_payload is null or jsonb_typeof(p_payload) <> 'object'
       or p_result_kind not in ('answer', 'translation', 'media_task')
       or p_result_id is null then
        return jsonb_build_object('code', 'INVALID_INPUT');
    end if;

    select capability into v_capability from public.recipe_usage_reservations
        where operation_id = p_operation_id;
    if v_capability is null then
        return jsonb_build_object('code', 'NOT_FOUND');
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_owner_id::text || ':' || v_capability, 427)
    );

    select * into v_res from public.recipe_usage_reservations where operation_id = p_operation_id;
    if not found or v_res.owner_id <> p_owner_id then
        return jsonb_build_object('code', 'NOT_FOUND');
    end if;
    if v_res.capability <> p_capability or v_res.input_hash <> p_input_hash
       or v_res.source is distinct from p_source then
        return jsonb_build_object('code', 'IDEMPOTENCY_CONFLICT');
    end if;

    -- Idempotency: one (owner, capability, input_hash) maps to one stable outcome.
    select * into v_final from public.recipe_usage_finalizations
        where owner_id = p_owner_id and capability = p_capability and input_hash = p_input_hash;
    if found then
        if v_res.status = 'reserved' then
            update public.recipe_usage_counters
                set reserved = reserved - v_res.reserved_units
                where owner_id = p_owner_id and capability = v_res.capability
                  and period_type = v_res.period_type
                  and period_start is not distinct from v_res.period_start;
            update public.recipe_usage_reservations
                set status = 'released', released_at = now(), updated_at = now()
                where operation_id = p_operation_id;
        end if;
        select * into v_res from public.recipe_usage_reservations where operation_id = v_final.operation_id;
        return jsonb_build_object(
            'code', 'FINALIZED',
            'operation_id', p_operation_id::text,
            'result_id', v_final.result_id::text,
            'payload_hash', v_final.payload_hash,
            'period_start',
                case when v_res.period_start is null then null
                     else to_char(v_res.period_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end
        );
    end if;

    v_settle := public.recipe_usage_settle(p_owner_id, p_operation_id, p_capability, p_input_hash);
    if v_settle ->> 'code' <> 'COMMITTED' then
        return v_settle;
    end if;

    insert into public.recipe_usage_finalizations(
        owner_id, capability, input_hash, operation_id, recipe_id, result_id, result_kind,
        payload_hash, payload
    ) values (
        p_owner_id, p_capability, p_input_hash, p_operation_id, p_recipe_id, p_result_id, p_result_kind,
        p_payload_hash, p_payload
    ) returning * into v_final;

    return jsonb_build_object(
        'code', 'FINALIZED',
        'operation_id', p_operation_id::text,
        'result_id', v_final.result_id::text,
        'payload_hash', v_final.payload_hash,
        'period_start',
            case when v_res.period_start is null then null
                 else to_char(v_res.period_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Snapshot: report the three phase-II capabilities with real premium
--    entitlement and quota (same frozen key shape). The vocabulary stays exactly
--    ten capabilities; quota units are the frozen POLICY units.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_access_snapshot(p_owner_id uuid, p_policy_version integer, p_stage text)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
    v_ent jsonb;
    v_tier text;
    v_caps jsonb := '[]'::jsonb;
    v_quota jsonb;
begin
    if p_owner_id is null then
        return null;
    end if;
    v_ent := public.recipe_usage_entitlement(p_owner_id);
    v_tier := v_ent ->> 'tier';

    v_quota := (
        select jsonb_build_object(
            'units', 'successful_imports',
            'period_type', p ->> 'period_type',
            'period_start', p ->> 'period_start',
            'reset_at', p ->> 'reset_at',
            'limit', (p ->> 'limit')::bigint,
            'used', coalesce(c.used, 0),
            'reserved', coalesce(c.reserved, 0),
            'remaining', greatest(0, (p ->> 'limit')::bigint - coalesce(c.used, 0) - coalesce(c.reserved, 0))
        )
        from public.recipe_usage_period('smart_import', v_tier, now()) p
        left join public.recipe_usage_counters c
            on c.owner_id = p_owner_id and c.capability = 'smart_import'
           and c.period_type = p ->> 'period_type'
           and c.period_start is not distinct from
               (case when p ->> 'period_start' is null then null else (p ->> 'period_start')::timestamptz end)
    );
    v_caps := v_caps || jsonb_build_array(jsonb_build_object('id', 'smart_import', 'entitled', true, 'quota', v_quota));

    v_quota := (
        select jsonb_build_object(
            'units', 'successful_edits',
            'period_type', p ->> 'period_type',
            'period_start', p ->> 'period_start',
            'reset_at', p ->> 'reset_at',
            'limit', (p ->> 'limit')::bigint,
            'used', coalesce(c.used, 0),
            'reserved', coalesce(c.reserved, 0),
            'remaining', greatest(0, (p ->> 'limit')::bigint - coalesce(c.used, 0) - coalesce(c.reserved, 0))
        )
        from public.recipe_usage_period('ai_edit', v_tier, now()) p
        left join public.recipe_usage_counters c
            on c.owner_id = p_owner_id and c.capability = 'ai_edit'
           and c.period_type = p ->> 'period_type'
           and c.period_start is not distinct from
               (case when p ->> 'period_start' is null then null else (p ->> 'period_start')::timestamptz end)
    );
    v_caps := v_caps || jsonb_build_array(jsonb_build_object('id', 'ai_edit', 'entitled', true, 'quota', v_quota));

    v_quota := (
        select jsonb_build_object(
            'units', 'successful_answers',
            'period_type', p ->> 'period_type',
            'period_start', p ->> 'period_start',
            'reset_at', p ->> 'reset_at',
            'limit', (p ->> 'limit')::bigint,
            'used', coalesce(c.used, 0),
            'reserved', coalesce(c.reserved, 0),
            'remaining', greatest(0, (p ->> 'limit')::bigint - coalesce(c.used, 0) - coalesce(c.reserved, 0))
        )
        from public.recipe_usage_period('recipe_question', v_tier, now()) p
        left join public.recipe_usage_counters c
            on c.owner_id = p_owner_id and c.capability = 'recipe_question'
           and c.period_type = p ->> 'period_type'
           and c.period_start is not distinct from
               (case when p ->> 'period_start' is null then null else (p ->> 'period_start')::timestamptz end)
    );
    v_caps := v_caps || jsonb_build_array(jsonb_build_object('id', 'recipe_question', 'entitled', v_tier = 'premium', 'quota', v_quota));

    v_quota := (
        select jsonb_build_object(
            'units', 'successful_translations',
            'period_type', p ->> 'period_type',
            'period_start', p ->> 'period_start',
            'reset_at', p ->> 'reset_at',
            'limit', (p ->> 'limit')::bigint,
            'used', coalesce(c.used, 0),
            'reserved', coalesce(c.reserved, 0),
            'remaining', greatest(0, (p ->> 'limit')::bigint - coalesce(c.used, 0) - coalesce(c.reserved, 0))
        )
        from public.recipe_usage_period('recipe_translation', v_tier, now()) p
        left join public.recipe_usage_counters c
            on c.owner_id = p_owner_id and c.capability = 'recipe_translation'
           and c.period_type = p ->> 'period_type'
           and c.period_start is not distinct from
               (case when p ->> 'period_start' is null then null else (p ->> 'period_start')::timestamptz end)
    );
    v_caps := v_caps || jsonb_build_array(jsonb_build_object('id', 'recipe_translation', 'entitled', v_tier = 'premium', 'quota', v_quota));

    v_quota := (
        select jsonb_build_object(
            'units', 'media_tasks',
            'period_type', p ->> 'period_type',
            'period_start', p ->> 'period_start',
            'reset_at', p ->> 'reset_at',
            'limit', (p ->> 'limit')::bigint,
            'used', coalesce(c.used, 0),
            'reserved', coalesce(c.reserved, 0),
            'remaining', greatest(0, (p ->> 'limit')::bigint - coalesce(c.used, 0) - coalesce(c.reserved, 0))
        )
        from public.recipe_usage_period('media_import', v_tier, now()) p
        left join public.recipe_usage_counters c
            on c.owner_id = p_owner_id and c.capability = 'media_import'
           and c.period_type = p ->> 'period_type'
           and c.period_start is not distinct from
               (case when p ->> 'period_start' is null then null else (p ->> 'period_start')::timestamptz end)
    );
    v_caps := v_caps || jsonb_build_array(jsonb_build_object('id', 'media_import', 'entitled', v_tier = 'premium', 'quota', v_quota));

    -- Entitlement-only premium capabilities: unmetered (quota null); entitled only for premium owners.
    v_caps := v_caps || jsonb_build_array(
        jsonb_build_object('id', 'hands_free_cooking', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'weekly_templates', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'weekly_groceries', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'auto_plan', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'pdf_export', 'entitled', v_tier = 'premium', 'quota', null)
    );

    return jsonb_build_object(
        'owner_id', p_owner_id::text,
        'server_time', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'policy_version', p_policy_version,
        'stage', p_stage,
        'entitlement', jsonb_build_object('status', v_ent ->> 'status', 'valid_until', v_ent -> 'valid_until'),
        'capabilities', v_caps
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Grants. The two new entry points are unreachable by any client: revoke all
--    from public/anon/authenticated/service_role, then grant execute to
--    service_role only. The internal source validator is never granted.
-- ---------------------------------------------------------------------------
do $$ declare fn record; begin
    for fn in select oid::regprocedure as signature from pg_proc
        where pronamespace = 'public'::regnamespace
          and proname in ('recipe_usage_internal_source_valid', 'recipe_usage_reserve_internal', 'recipe_usage_finalize_internal')
        loop
        execute format('revoke all on function %s from public, anon, authenticated, service_role', fn.signature);
    end loop;
    grant execute on function public.recipe_usage_reserve_internal(uuid, uuid, text, text, jsonb) to service_role;
    grant execute on function public.recipe_usage_finalize_internal(uuid, uuid, text, text, jsonb, uuid, text, jsonb, text, uuid) to service_role;
end $$;
