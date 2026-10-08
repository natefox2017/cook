-- Developer: gengyun
-- Purpose: Keep snapshot revisions monotonic for every stored mutation.

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

revoke all on function public.set_user_snapshot_revision()
    from public, anon, authenticated;

drop trigger if exists user_snapshots_set_revision
    on public.user_snapshots;

create trigger user_snapshots_set_revision
before insert or update on public.user_snapshots
for each row execute function public.set_user_snapshot_revision();
