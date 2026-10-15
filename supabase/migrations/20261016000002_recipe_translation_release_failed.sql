-- Developer: gengyun
-- Purpose: DEV-439 translation metering correction. Adds a service-role-only release for a
--          dispatched reservation whose provider outcome the caller has definitively determined is
--          failed and non-recoverable (for example, the provider returned output that failed the
--          deterministic numeric/structural validation). The existing recipe_usage_release keeps its
--          unknown-outcome fence for dispatched_unknown (generated_at null) reservations; this
--          targeted entry point lets a KNOWN-invalid dispatch release its held unit immediately so a
--          failed translation never permanently consumes the monthly 20-unit quota. It never touches
--          the reserved/committed/released/expired transitions or any other capability.

create or replace function public.recipe_usage_release_failed(
    p_owner_id uuid,
    p_operation_id uuid
)
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

    -- Only a still-dispatched outcome with a KNOWN (non-recoverable) result is releasable here.
    -- reserved/committed/released/expired reservations keep their existing semantics.
    if v_res.status <> 'dispatched_unknown' then
        return jsonb_build_object('code', 'RESERVATION_EXPIRED');
    end if;

    update public.recipe_usage_counters
        set reserved = reserved - v_res.reserved_units
        where owner_id = p_owner_id and capability = v_res.capability
          and period_type = v_res.period_type
          and period_start is not distinct from v_res.period_start;

    update public.recipe_usage_reservations
        set status = 'released', released_at = now(), updated_at = now()
        where operation_id = p_operation_id
        returning * into v_res;

    return jsonb_build_object(
        'code', 'RELEASED',
        'reservation', public.recipe_usage_reservation_json(v_res)
    );
end;
$$;

-- Service-role only, like the other phase-II internal settle entry points. No client role may call it.
revoke all on function public.recipe_usage_release_failed(uuid, uuid)
    from public, anon, authenticated, service_role;
grant execute on function public.recipe_usage_release_failed(uuid, uuid) to service_role;
