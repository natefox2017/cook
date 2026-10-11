-- Developer: gengyun
-- Purpose: DEV-282 versions the frozen DEV-241 owner-scoped public recipe share schema.
-- Frozen source: PR332@62a485a13319858494938522bfb3c3d9b023af4a.
-- Local database verification only; staging/production require separate DEV-50 authorization.

create table if not exists public.recipe_shared_snapshots (
    share_id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    source_recipe_id uuid not null,
    source_client_updated_at timestamptz not null,
    opaque_slug text not null unique
        check (opaque_slug ~ '^[A-Za-z0-9_-]{43}$'),
    share_version bigint not null default 1 check (share_version > 0),
    scope text not null
        check (scope in ('summaryAndSource', 'fullInstructions')),
    has_distribution_rights boolean not null default false,
    sanitized_snapshot jsonb,
    idempotency_key uuid not null,
    request_hash text not null
        check (request_hash ~ '^[0-9a-f]{64}$'),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    revoked_at timestamptz,
    constraint recipe_shares_unique_retry
        unique (owner_id, idempotency_key),
    constraint recipe_shares_full_rights
        check (scope <> 'fullInstructions' or has_distribution_rights),
    constraint recipe_shares_revocation_erases_snapshot
        check (
            (revoked_at is null and sanitized_snapshot is not null)
            or (revoked_at is not null and sanitized_snapshot is null)
        ),
    constraint recipe_shares_snapshot_object
        check (
            sanitized_snapshot is null or
            jsonb_typeof(sanitized_snapshot) = 'object'
        ),
    constraint recipe_shares_summary_no_directions
        check (
            sanitized_snapshot is null or scope <> 'summaryAndSource'
            or (
                sanitized_snapshot -> 'ingredients' = '[]'::jsonb and
                sanitized_snapshot -> 'steps' = '[]'::jsonb
            )
        )
);

comment on table public.recipe_shared_snapshots is
    'Opt-in V1 sanitized public sharing registry, not a private recipe library or API table.';

create index if not exists recipe_shared_snapshots_owner_created
    on public.recipe_shared_snapshots(owner_id, created_at desc);

create index if not exists recipe_shared_snapshots_owner_active
    on public.recipe_shared_snapshots(owner_id, updated_at desc)
    where revoked_at is null;

alter table public.recipe_shared_snapshots enable row level security;

-- Direct browser/mobile REST access may only read its own registry; every
-- write goes through an authenticated Edge handler. Guests cannot select rows.
drop policy if exists recipe_shared_snapshots_read_own
    on public.recipe_shared_snapshots;
create policy recipe_shared_snapshots_read_own
    on public.recipe_shared_snapshots for select to authenticated
    using (owner_id = (select auth.uid()));

-- Defense in depth: guarded write policies exist, but table DML is not
-- granted to authenticated clients. Service-only Edge writes must still check
-- owner_id in *every* WHERE predicate after requireUser() has verified JWT.
drop policy if exists recipe_shared_snapshots_insert_own
    on public.recipe_shared_snapshots;
create policy recipe_shared_snapshots_insert_own
    on public.recipe_shared_snapshots for insert to authenticated
    with check (owner_id = (select auth.uid()));

drop policy if exists recipe_shared_snapshots_update_own
    on public.recipe_shared_snapshots;
create policy recipe_shared_snapshots_update_own
    on public.recipe_shared_snapshots for update to authenticated
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

revoke all on public.recipe_shared_snapshots from public, anon, authenticated;
grant select on public.recipe_shared_snapshots to authenticated;
grant all on public.recipe_shared_snapshots to service_role;

-- The auth.users cascade invalidates public reads at account deletion.
-- Disposable test rollback: tests/isolated/recipe-share-rollback.sql removes
-- the creation RPC before its table. Never run that fixture against a hosted DB.


-- Serialize create admission by owner across database sessions. Hash collisions
-- only serialize unrelated owners; owner predicates still govern all row access.
create or replace function public.create_recipe_share_once(
    p_owner_id uuid, p_payload jsonb, p_slug text, p_request_hash text
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    existing public.recipe_shared_snapshots%rowtype;
    created public.recipe_shared_snapshots%rowtype;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_owner_id::text, 241)
    );
    select * into existing from public.recipe_shared_snapshots
    where owner_id = p_owner_id
      and idempotency_key = (p_payload ->> 'idempotencyKey')::uuid;
    if found then
        if existing.revoked_at is not null or existing.request_hash <> p_request_hash then
            return pg_catalog.jsonb_build_object('status', 409);
        end if;
        return pg_catalog.jsonb_build_object('status', 200, 'share', pg_catalog.to_jsonb(existing));
    end if;
    if (select count(*) from public.recipe_shared_snapshots
        where owner_id = p_owner_id
          and created_at >= pg_catalog.now() - interval '24 hours') >= 200 then
        return pg_catalog.jsonb_build_object('status', 429);
    end if;
    insert into public.recipe_shared_snapshots (
        owner_id, source_recipe_id, source_client_updated_at, opaque_slug,
        scope, has_distribution_rights, sanitized_snapshot,
        idempotency_key, request_hash
    ) values (
        p_owner_id, (p_payload ->> 'sourceRecipeID')::uuid,
        (p_payload ->> 'sourceRecipeUpdatedAt')::timestamptz, p_slug,
        p_payload ->> 'scope', (p_payload ->> 'hasDistributionRights')::boolean,
        p_payload -> 'snapshot', (p_payload ->> 'idempotencyKey')::uuid,
        p_request_hash
    ) returning * into created;
    return pg_catalog.jsonb_build_object('status', 201, 'share', pg_catalog.to_jsonb(created));
end;
$$;
revoke all on function public.create_recipe_share_once(uuid,jsonb,text,text)
    from public, anon, authenticated;
grant execute on function public.create_recipe_share_once(uuid,jsonb,text,text)
    to service_role;
