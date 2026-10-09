-- Developer: gengyun
-- Purpose: Keep privileged recipe import queue operations server-only.
-- These legacy SECURITY DEFINER wrappers bypass RLS and must not be exposed through
-- PostgREST to app clients. Their definitions are managed outside this repository,
-- so clean installs skip absent functions while upgraded projects still harden them.
-- Do not change queue data; present functions retain service_role EXECUTE only.
do $migration$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.recipe_import_enqueue(uuid,text,text)',
    'public.recipe_import_enqueue_many(uuid[],text,text)',
    'public.recipe_import_queue_read(integer,integer)',
    'public.recipe_import_queue_archive(bigint)',
    'public.recipe_import_queue_delete(bigint)',
    'public.recipe_import_requeue_stale_pending(integer,integer,text)'
  ] loop
    if to_regprocedure(v_signature) is not null then
      execute format(
        'revoke execute on function %s from public, anon, authenticated',
        v_signature
      );
      execute format(
        'grant execute on function %s to service_role',
        v_signature
      );
    end if;
  end loop;
end;
$migration$;
