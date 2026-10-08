-- Developer: gengyun
-- Purpose: Create Cook's owner-scoped JSON snapshot table with row-level access control.
-- Cook V1 private sync schema; the matching migration is already present on cookapp.
create table if not exists public.user_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version > 0),
  payload jsonb not null,
  client_updated_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.user_snapshots enable row level security;

create policy "read own cook snapshot" on public.user_snapshots
for select to authenticated
using ((select auth.uid()) = user_id);

create policy "insert own cook snapshot" on public.user_snapshots
for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "update own cook snapshot" on public.user_snapshots
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "delete own cook snapshot" on public.user_snapshots
for delete to authenticated
using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.user_snapshots to authenticated;
revoke all on public.user_snapshots from anon;
