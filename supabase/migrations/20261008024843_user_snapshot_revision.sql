-- Developer: gengyun
-- Purpose: Add an optimistic-concurrency revision to owner-scoped user snapshots.

alter table public.user_snapshots
    add column if not exists revision bigint not null default 1
    check (revision > 0);
