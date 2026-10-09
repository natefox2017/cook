-- The live admin schema predates the checked-in privilege hardening migration.
-- Keep bootstrap callable only by the trusted Edge Function service role.
do $migration$
begin
  if to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is not null then
    execute 'revoke execute on function public.admin_bootstrap_owner(text,text,text) from public, anon, authenticated';
    execute 'grant execute on function public.admin_bootstrap_owner(text,text,text) to service_role';
  end if;
end;
$migration$;
