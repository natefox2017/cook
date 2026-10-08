-- Developer: gengyun
-- Purpose: Keep revisions monotonic for every allowed snapshot row mutation.

create or replace function public.set_user_snapshot_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        new.revision := 1;
    else
        new.revision := old.revision + 1;
    end if;
    new.updated_at := now();
    return new;
end;
$$;

revoke all on function public.set_user_snapshot_revision() from public, anon, authenticated;

create trigger user_snapshots_set_revision
before insert or update on public.user_snapshots
for each row execute function public.set_user_snapshot_revision();

create or replace function public.save_own_user_snapshot(
    expected_revision bigint,
    snapshot_schema_version integer,
    snapshot_payload jsonb,
    snapshot_client_updated_at timestamptz
)
returns setof public.user_snapshots
language plpgsql
security invoker
set search_path = ''
as $$
declare
    owner_id uuid := auth.uid();
begin
    if expected_revision is null
        or snapshot_schema_version is null
        or snapshot_payload is null
        or snapshot_client_updated_at is null
        or expected_revision < 0
        or snapshot_schema_version <= 0
        or jsonb_typeof(snapshot_payload) is distinct from 'object' then
        raise exception 'Invalid snapshot.' using errcode = '22023';
    end if;

    if owner_id is null then
        raise exception 'Authentication is required.' using errcode = '42501';
    end if;

    if expected_revision = 0 then
        return query
        insert into public.user_snapshots (
            user_id, schema_version, payload, client_updated_at
        ) values (
            owner_id, snapshot_schema_version, snapshot_payload, snapshot_client_updated_at
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

revoke all on function public.save_own_user_snapshot(bigint, integer, jsonb, timestamptz)
    from public, anon;
grant execute on function public.save_own_user_snapshot(bigint, integer, jsonb, timestamptz)
    to authenticated;
