-- Keep SECURITY DEFINER entry points behind their intended auth boundary.
-- These routines are legacy production objects not defined by repository migrations,
-- so fresh environments safely skip grants for signatures that do not exist.
do $migration$
begin
  if to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is not null then
    execute 'revoke execute on function public.admin_bootstrap_owner(text,text,text) from public, anon, authenticated';
    execute 'grant execute on function public.admin_bootstrap_owner(text,text,text) to service_role';
  end if;

  if to_regprocedure('public.admin_change_password(uuid,text,text)') is not null then
    execute 'revoke execute on function public.admin_change_password(uuid,text,text) from public, anon, authenticated';
    execute 'grant execute on function public.admin_change_password(uuid,text,text) to service_role';
  end if;

  if to_regprocedure('public.admin_verify_credentials(text,text)') is not null then
    execute 'revoke execute on function public.admin_verify_credentials(text,text) from public, anon, authenticated';
    execute 'grant execute on function public.admin_verify_credentials(text,text) to service_role';
  end if;

  if to_regprocedure('public.capture_registration_meta(text,text)') is not null then
    -- This function requires auth.uid() and only updates that user's profile.
    execute 'revoke execute on function public.capture_registration_meta(text,text) from public, anon, service_role';
    execute 'grant execute on function public.capture_registration_meta(text,text) to authenticated';
  end if;

  if to_regprocedure('public.get_runtime_config_number(text,numeric)') is not null then
    -- No current trusted caller was verified; grant access with a future caller change.
    execute 'revoke execute on function public.get_runtime_config_number(text,numeric) from public, anon, authenticated, service_role';
  end if;
end;
$migration$;
