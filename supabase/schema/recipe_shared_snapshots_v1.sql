-- Developer: Recipe Pals
-- Purpose: DEV-241 isolated, owner-scoped public recipe share storage (source SQL).
-- IMPORTANT: Not a migration until a developer with Supabase CLI runs
--   supabase migration new recipe_shared_snapshots_v1
-- and copies this reviewed SQL to the CLI-generated file. Never apply on production.
-- This source exists because Supabase CLI is unavailable in this execution runtime.

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
-- Rollback in a disposable local environment only:
--   DROP TABLE public.recipe_shared_snapshots;
-- Production rollout/rollback requires separate DEV-50 owner authorization.
