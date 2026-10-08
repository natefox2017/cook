-- Developer: gengyun
-- Purpose: Keep privileged recipe import queue operations server-only.
-- These SECURITY DEFINER wrappers bypass RLS and must not be exposed through PostgREST to app clients.
-- Do not change queue data; approved service-role workers retain EXECUTE.

revoke execute on function public.recipe_import_enqueue(uuid,text,text) from public, anon, authenticated;
grant execute on function public.recipe_import_enqueue(uuid,text,text) to service_role;
revoke execute on function public.recipe_import_enqueue_many(uuid[],text,text) from public, anon, authenticated;
grant execute on function public.recipe_import_enqueue_many(uuid[],text,text) to service_role;
revoke execute on function public.recipe_import_queue_read(integer,integer) from public, anon, authenticated;
grant execute on function public.recipe_import_queue_read(integer,integer) to service_role;
revoke execute on function public.recipe_import_queue_archive(bigint) from public, anon, authenticated;
grant execute on function public.recipe_import_queue_archive(bigint) to service_role;
revoke execute on function public.recipe_import_queue_delete(bigint) from public, anon, authenticated;
grant execute on function public.recipe_import_queue_delete(bigint) to service_role;
revoke execute on function public.recipe_import_requeue_stale_pending(integer,integer,text) from public, anon, authenticated;
grant execute on function public.recipe_import_requeue_stale_pending(integer,integer,text) to service_role;
