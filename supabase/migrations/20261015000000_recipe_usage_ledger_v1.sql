-- Developer: gengyun
-- Purpose: DEV-427 owner-scoped commercial usage ledger: atomic reserve/commit/release/finalize with
--          server-owned week/month/lifetime quota counters, a durable dispatch fence, and stable
--          finalization idempotency. Canonical wire contract: docs/RECIPE_PALS_COMMERCIAL_CONTRACT.md.
--          Additive only; it never alters the import, draft, token-budget or subscription write paths.
--          Every settlement RPC is SECURITY DEFINER with an empty search_path and an explicit verified
--          owner; PUBLIC/anon/authenticated execution is revoked so no client can mint/release quota.

-- ---------------------------------------------------------------------------
-- Counters: used/reserved observation per (owner, capability, period_type, period_start).
-- smart_import observes BOTH the UTC ISO week and the UTC calendar month; the owner's current tier
-- decides which period enforces the limit. ai_edit free tier uses the lifetime bucket (null start).
-- ---------------------------------------------------------------------------
create table if not exists public.recipe_usage_counters (
    id bigint generated always as identity primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    capability text not null check (capability in ('smart_import', 'ai_edit')),
    period_type text not null check (period_type in ('iso_week', 'utc_month', 'lifetime')),
    period_start timestamptz,
    used bigint not null default 0 check (used >= 0 and used <= 9007199254740991),
    reserved bigint not null default 0 check (reserved >= 0 and reserved <= 9007199254740991),
    constraint recipe_usage_counters_period
        check ((period_type = 'lifetime') = (period_start is null)),
    constraint recipe_usage_counters_unique_period
        unique nulls not distinct (owner_id, capability, period_type, period_start)
);

create index if not exists recipe_usage_counters_owner_idx
    on public.recipe_usage_counters(owner_id, capability);

-- ---------------------------------------------------------------------------
-- Reservations: one unit per operation, frozen tier/period/policy at reserve time. A dispatched_unknown
-- reservation is a durable dispatch fence and is never auto-released.
-- ---------------------------------------------------------------------------
create table if not exists public.recipe_usage_reservations (
    operation_id uuid primary key,
    owner_id uuid not null references auth.users(id) on delete cascade,
    capability text not null check (capability in ('smart_import', 'ai_edit')),
    input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
    source jsonb not null check (jsonb_typeof(source) = 'object'),
    status text not null default 'reserved'
        check (status in ('reserved', 'dispatched_unknown', 'committed', 'released', 'expired')),
    tier_at_reserve text not null check (tier_at_reserve in ('free', 'premium')),
    policy_version integer not null default 1 check (policy_version = 1),
    period_type text not null check (period_type in ('iso_week', 'utc_month', 'lifetime')),
    period_start timestamptz,
    reserved_units integer not null default 1 check (reserved_units = 1),
    reserved_until timestamptz not null,
    reserved_at timestamptz not null default now(),
    dispatched_at timestamptz,
    committed_at timestamptz,
    released_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint recipe_usage_reservations_period
        check ((period_type = 'lifetime') = (period_start is null))
);

create index if not exists recipe_usage_reservations_owner_idx
    on public.recipe_usage_reservations(owner_id, created_at desc);
create index if not exists recipe_usage_reservations_pending_idx
    on public.recipe_usage_reservations(status, reserved_until)
    where status in ('reserved', 'dispatched_unknown');

-- ---------------------------------------------------------------------------
-- Finalizations: one stable recipe_id + payload_hash per (owner, capability, source). A replay, or a
-- new operation for the same candidate, returns the same durable outcome without a second charge.
-- ---------------------------------------------------------------------------
create table if not exists public.recipe_usage_finalizations (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    capability text not null check (capability in ('smart_import', 'ai_edit')),
    input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
    operation_id uuid not null,
    recipe_id uuid not null,
    payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
    payload jsonb not null check (jsonb_typeof(payload) = 'object'),
    finalized_at timestamptz not null default now(),
    constraint recipe_usage_finalizations_unique_source
        unique (owner_id, capability, input_hash)
);

create index if not exists recipe_usage_finalizations_owner_idx
    on public.recipe_usage_finalizations(owner_id, finalized_at desc);

-- Defense in depth: the ledger is server-owned. No client may read or write quota rows; service_role
-- alone backs the verified-owner Edge handlers.
alter table public.recipe_usage_counters enable row level security;
alter table public.recipe_usage_reservations enable row level security;
alter table public.recipe_usage_finalizations enable row level security;

revoke all on public.recipe_usage_counters from public, anon, authenticated;
revoke all on public.recipe_usage_reservations from public, anon, authenticated;
revoke all on public.recipe_usage_finalizations from public, anon, authenticated;
grant all on public.recipe_usage_counters to service_role;
grant all on public.recipe_usage_reservations to service_role;
grant all on public.recipe_usage_finalizations to service_role;

-- ---------------------------------------------------------------------------
-- Server-owned entitlement resolution. Tier comes only from the trusted subscriptions lifecycle.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_entitlement(p_owner_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
    select coalesce(
        (
            select jsonb_build_object(
                'status',
                case
                    when s.status in ('active', 'trialing', 'cancelled', 'billing_issue')
                         and (s.expires_at is null or s.expires_at > now()) then 'premium'
                    when s.status = 'expired'
                         or (s.expires_at is not null and s.expires_at <= now()) then 'expired'
                    else 'free'
                end,
                'tier',
                case
                    when s.status in ('active', 'trialing', 'cancelled', 'billing_issue')
                         and (s.expires_at is null or s.expires_at > now()) then 'premium'
                    else 'free'
                end,
                'valid_until',
                case
                    when s.expires_at is null then null
                    else to_char(
                        s.expires_at at time zone 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                    )
                end
            )
            from public.subscriptions s
            where s.user_id = p_owner_id
        ),
        jsonb_build_object('status', 'free', 'tier', 'free', 'valid_until', null)
    )
$$;

-- ---------------------------------------------------------------------------
-- Frozen policy period: capability + tier -> period bucket + limit + reset boundary.
-- Iso-week starts Monday 00:00 UTC; utc-month starts the 1st 00:00 UTC; lifetime has null boundaries.
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
        else null
    end
$$;

-- Wire-shaped Reservation projection (period_start null for lifetime).
create or replace function public.recipe_usage_reservation_json(r public.recipe_usage_reservations)
returns jsonb
language sql stable set search_path = ''
as $$
    select jsonb_build_object(
        'operation_id', r.operation_id::text,
        'owner_id', r.owner_id::text,
        'capability', r.capability,
        'period_start',
            case when r.period_start is null then null
                 else to_char(r.period_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
        'policy_version', r.policy_version,
        'tier_at_reserve', r.tier_at_reserve,
        'reserved_units', r.reserved_units,
        'status', r.status,
        'reserved_until', to_char(r.reserved_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    )
$$;

-- ---------------------------------------------------------------------------
-- Lazy reclamation of expired, undispatched reservations under the (owner, capability) lock. Stale
-- 10-minute holds must never block quota forever; dispatched_unknown reservations are never reclaimed.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_expire_stale(p_owner_id uuid, p_capability text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_stale public.recipe_usage_reservations%rowtype;
begin
    for v_stale in
        select * from public.recipe_usage_reservations
        where owner_id = p_owner_id and capability = p_capability
          and status = 'reserved' and reserved_until < now()
        order by reserved_at
        for update
    loop
        update public.recipe_usage_counters
            set reserved = reserved - v_stale.reserved_units
            where owner_id = p_owner_id and capability = p_capability
              and period_type = v_stale.period_type
              and period_start is not distinct from v_stale.period_start;
        update public.recipe_usage_reservations
            set status = 'expired', updated_at = now()
            where operation_id = v_stale.operation_id;
    end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settle a reservation's single unit: return its reserved unit to its own bucket, then record the used
-- unit in the observation period(s) derived from reserved_at (a boundary-crossing commit never charges a
-- new period). Idempotent. Internal only: callers hold the (owner, capability) advisory lock.
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

    -- Return the reserved unit to the reservation's own bucket.
    update public.recipe_usage_counters
        set reserved = reserved - v_res.reserved_units
        where owner_id = p_owner_id and capability = v_res.capability
          and period_type = v_res.period_type
          and period_start is not distinct from v_res.period_start;

    -- Record the used unit. smart_import observes both week and month of reserved_at; ai_edit only
    -- settles its own bucket (lifetime for free, month for premium).
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
        values (p_owner_id, 'ai_edit', v_res.period_type, v_res.period_start, 1, 0)
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
-- Reserve one unit. The lock key is (owner, capability); stale undispatched holds are reclaimed first,
-- then the counter for the owner's current tier period is read inside the lock so used+reserved never
-- exceeds the frozen limit. Policy version is server-pinned to 1; a client never authors it.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_reserve(
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
       or p_capability not in ('smart_import', 'ai_edit')
       or p_input_hash is null or p_input_hash !~ '^[0-9a-f]{64}$'
       or p_source is null or jsonb_typeof(p_source) <> 'object' then
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

    -- Reclaim stale undispatched holds before judging quota.
    perform public.recipe_usage_expire_stale(p_owner_id, p_capability);

    v_ent := public.recipe_usage_entitlement(p_owner_id);
    v_tier := v_ent ->> 'tier';
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
-- Durable dispatch fence: transition a still-reserved unit to dispatched_unknown BEFORE any provider
-- side effect, so a crash can never auto-release and re-dispatch it. Internal entry for the draft
-- composition (DEV-428); no client route exposes it.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_mark_dispatched(p_owner_id uuid, p_operation_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_res public.recipe_usage_reservations%rowtype;
    v_capability text;
begin
    if p_owner_id is null or p_operation_id is null then
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
    if v_res.status <> 'reserved' then
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;
    update public.recipe_usage_reservations
        set status = 'dispatched_unknown', dispatched_at = now(), updated_at = now()
        where operation_id = p_operation_id
        returning * into v_res;
    return jsonb_build_object('code', 'DISPATCHED', 'reservation', public.recipe_usage_reservation_json(v_res));
end;
$$;

-- ---------------------------------------------------------------------------
-- Settle a dispatched reservation (commit). Same durable outcome replays; never double charges.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_commit(
    p_owner_id uuid, p_operation_id uuid, p_capability text, p_input_hash text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_res public.recipe_usage_reservations%rowtype;
    v_capability text;
    v_settle jsonb;
begin
    if p_owner_id is null or p_operation_id is null
       or p_capability not in ('smart_import', 'ai_edit')
       or p_input_hash is null or p_input_hash !~ '^[0-9a-f]{64}$' then
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

    v_settle := public.recipe_usage_settle(p_owner_id, p_operation_id, p_capability, p_input_hash);
    if v_settle ->> 'code' = 'COMMITTED' then
        select * into v_res from public.recipe_usage_reservations where operation_id = p_operation_id;
        return jsonb_build_object(
            'code', 'COMMITTED',
            'operation_id', p_operation_id::text,
            'period_start',
                case when v_res.period_start is null then null
                     else to_char(v_res.period_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end
        );
    end if;
    return v_settle;
end;
$$;

-- ---------------------------------------------------------------------------
-- Release a reservation confirmed not dispatched or not committed. Units return to the original bucket.
-- A committed reservation cannot be released; a dispatched_unknown reservation is releasable only after
-- the 24-hour generated-proposal hold elapses (its uncommitted unit is then safe to reclaim).
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_release(p_owner_id uuid, p_operation_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_res public.recipe_usage_reservations%rowtype;
    v_capability text;
begin
    if p_owner_id is null or p_operation_id is null then
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
    if v_res.status = 'committed' then
        return jsonb_build_object('code', 'COMMITTED', 'reservation', public.recipe_usage_reservation_json(v_res));
    end if;
    if v_res.status = 'released' then
        return jsonb_build_object('code', 'RELEASED', 'reservation', public.recipe_usage_reservation_json(v_res));
    end if;
    if v_res.status = 'expired' then
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;
    if v_res.status = 'dispatched_unknown' then
        -- A generated-but-unapproved proposal is held 24h; only then is its uncommitted unit releasable.
        if v_res.dispatched_at is null or v_res.dispatched_at + interval '24 hours' > now() then
            return jsonb_build_object('code', 'RESERVATION_EXPIRED');
        end if;
    end if;

    -- Only a still-held unit is released; a repeated release never goes negative.
    update public.recipe_usage_counters
        set reserved = reserved - v_res.reserved_units
        where owner_id = p_owner_id and capability = v_res.capability
          and period_type = v_res.period_type
          and period_start is not distinct from v_res.period_start;
    update public.recipe_usage_reservations
        set status = 'released', released_at = now(), updated_at = now()
        where operation_id = p_operation_id
        returning * into v_res;
    return jsonb_build_object('code', 'RELEASED', 'reservation', public.recipe_usage_reservation_json(v_res));
end;
$$;

-- ---------------------------------------------------------------------------
-- Finalize: atomically settle usage AND persist the server-produced stable recipe_id + payload_hash +
-- recoverable approved payload. Idempotent by (owner, capability, source). The supplied operation is
-- validated first; if the source was already finalized, a still-held new reservation is released and the
-- canonical outcome is returned without a second charge. recipe_id is server-generated (never supplied).
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_finalize(
    p_owner_id uuid, p_operation_id uuid, p_capability text, p_input_hash text,
    p_source jsonb, p_payload_hash text, p_payload jsonb
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
       or p_capability not in ('smart_import', 'ai_edit')
       or p_input_hash is null or p_input_hash !~ '^[0-9a-f]{64}$'
       or p_payload_hash is null or p_payload_hash !~ '^[0-9a-f]{64}$'
       or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
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

    -- Validate the supplied operation BEFORE consulting the prior finalization.
    select * into v_res from public.recipe_usage_reservations where operation_id = p_operation_id;
    if not found or v_res.owner_id <> p_owner_id then
        return jsonb_build_object('code', 'NOT_FOUND');
    end if;
    if v_res.capability <> p_capability or v_res.input_hash <> p_input_hash
       or v_res.source is distinct from p_source then
        return jsonb_build_object('code', 'IDEMPOTENCY_CONFLICT');
    end if;

    -- Idempotency: one candidate maps to one stable recipe_id.
    select * into v_final from public.recipe_usage_finalizations
        where owner_id = p_owner_id and capability = p_capability and input_hash = p_input_hash;
    if found then
        -- A new operation for an already-finalized source must not leave a second reserved unit held.
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
            'recipe_id', v_final.recipe_id::text,
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
        owner_id, capability, input_hash, operation_id, recipe_id, payload_hash, payload
    ) values (
        p_owner_id, p_capability, p_input_hash, p_operation_id, gen_random_uuid(), p_payload_hash, p_payload
    ) returning * into v_final;

    return jsonb_build_object(
        'code', 'FINALIZED',
        'operation_id', p_operation_id::text,
        'recipe_id', v_final.recipe_id::text,
        'payload_hash', v_final.payload_hash,
        'period_start',
            case when v_res.period_start is null then null
                 else to_char(v_res.period_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- Ack: confirms the device durably persisted a finalized save. It grants no quota and requires the
-- reservation to already be committed; recovery reuses the same operation and never re-invokes a model.
-- ---------------------------------------------------------------------------
create or replace function public.recipe_usage_ack(p_owner_id uuid, p_operation_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    v_res public.recipe_usage_reservations%rowtype;
begin
    if p_owner_id is null or p_operation_id is null then
        return jsonb_build_object('code', 'INVALID_INPUT');
    end if;
    select * into v_res from public.recipe_usage_reservations where operation_id = p_operation_id;
    if not found or v_res.owner_id <> p_owner_id then
        return jsonb_build_object('code', 'NOT_FOUND');
    end if;
    if v_res.status <> 'committed' then
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;
    return jsonb_build_object('code', 'ACKED', 'operation_id', p_operation_id::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Snapshot: server-owned entitlement + quota for the authenticated owner. stage/policy_version are
-- injected by the handler from server configuration; a client never authors them.
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

    -- Entitlement-only premium capabilities: unmetered (quota null); entitled only for premium owners.
    v_caps := v_caps || jsonb_build_array(
        jsonb_build_object('id', 'hands_free_cooking', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'weekly_templates', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'weekly_groceries', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'auto_plan', 'entitled', v_tier = 'premium', 'quota', null),
        jsonb_build_object('id', 'pdf_export', 'entitled', v_tier = 'premium', 'quota', null)
    );

    -- Phase II vocabulary is present but disabled until its period switch enables settlement.
    v_caps := v_caps || jsonb_build_array(
        jsonb_build_object('id', 'recipe_question', 'entitled', false, 'quota', null),
        jsonb_build_object('id', 'recipe_translation', 'entitled', false, 'quota', null),
        jsonb_build_object('id', 'media_import', 'entitled', false, 'quota', null)
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

-- SECURITY DEFINER is never an invitation to PUBLIC execution. Internal helpers have no execute grant;
-- only the settlement/snapshot entry points are callable by service_role (the trusted Edge handler).
do $$ declare fn record; begin
    for fn in select oid::regprocedure as signature from pg_proc
        where pronamespace = 'public'::regnamespace
          and proname in (
              'recipe_usage_entitlement', 'recipe_usage_period', 'recipe_usage_reservation_json',
              'recipe_usage_expire_stale', 'recipe_usage_settle', 'recipe_usage_reserve',
              'recipe_usage_mark_dispatched', 'recipe_usage_commit', 'recipe_usage_release',
              'recipe_usage_finalize', 'recipe_usage_ack', 'recipe_access_snapshot'
          ) loop
        execute format('revoke all on function %s from public, anon, authenticated, service_role', fn.signature);
        if fn.signature::text like '%recipe_usage_reserve(%'
           or fn.signature::text like '%recipe_usage_mark_dispatched(%'
           or fn.signature::text like '%recipe_usage_commit(%'
           or fn.signature::text like '%recipe_usage_release(%'
           or fn.signature::text like '%recipe_usage_finalize(%'
           or fn.signature::text like '%recipe_usage_ack(%'
           or fn.signature::text like '%recipe_access_snapshot(%' then
            execute format('grant execute on function %s to service_role', fn.signature);
        end if;
    end loop;
end $$;
