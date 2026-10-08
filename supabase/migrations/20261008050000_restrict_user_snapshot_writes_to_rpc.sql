-- Developer: gengyun
-- Purpose: Require authenticated snapshot mutations to use the revision-checked RPC.

-- RLS does not protect TRUNCATE, and direct UPDATE/DELETE would bypass the
-- expected-revision contract. End-user clients therefore get read-only table
-- access and mutate snapshots exclusively through the owner-checked RPC.
revoke insert, update, delete, truncate, references, trigger
    on table public.user_snapshots
    from authenticated;

grant select on table public.user_snapshots to authenticated;
revoke all on table public.user_snapshots from anon;

create or replace function public.save_own_user_snapshot(
    target_user_id uuid,
    expected_revision bigint,
    snapshot_schema_version integer,
    snapshot_payload jsonb,
    snapshot_client_updated_at timestamptz
)
returns setof public.user_snapshots
language plpgsql
security definer
set search_path = ''
as $$
declare
    owner_id uuid := auth.uid();
begin
    if owner_id is null
        or target_user_id is null
        or owner_id <> target_user_id then
        raise exception
            'The active account changed before this snapshot could be saved.'
            using errcode = '42501';
    end if;

    if expected_revision is null
        or snapshot_schema_version is null
        or snapshot_payload is null
        or snapshot_client_updated_at is null
        or expected_revision < 0
        or snapshot_schema_version <= 0
        or jsonb_typeof(snapshot_payload) is distinct from 'object' then
        raise exception 'Invalid snapshot.' using errcode = '22023';
    end if;

    if expected_revision = 0 then
        return query
        insert into public.user_snapshots (
            user_id,
            schema_version,
            payload,
            client_updated_at
        ) values (
            owner_id,
            snapshot_schema_version,
            snapshot_payload,
            snapshot_client_updated_at
        )
        on conflict (user_id) do nothing
        returning *;
    else
        return query
        update public.user_snapshots as snapshot
        set schema_version = snapshot_schema_version,
            payload = snapshot_payload,
            client_updated_at = snapshot_client_updated_at
        where snapshot.user_id = owner_id
          and snapshot.revision = expected_revision
        returning snapshot.*;
    end if;
end;
$$;

revoke all on function public.save_own_user_snapshot(
    uuid,
    bigint,
    integer,
    jsonb,
    timestamptz
) from public, anon;

grant execute on function public.save_own_user_snapshot(
    uuid,
    bigint,
    integer,
    jsonb,
    timestamptz
) to authenticated;
