-- Legacy admin RPCs are not present in every local environment. Replace the
-- deployed bootstrap body only when its existing signature is available.
do $migration$
begin
  if to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is null then
    return;
  end if;

  execute $ddl$
    create or replace function public.admin_bootstrap_owner(
      p_username text,
      p_new_password text,
      p_current_password text default null
    )
    returns table(id uuid, username text, role text)
    language plpgsql
    security definer
    set search_path to 'public', 'extensions'
    as $function$
    declare
      seed public.admin_accounts%rowtype;
      uname text := lower(trim(p_username));
    begin
      if uname is null or char_length(uname) < 3 then
        raise exception 'invalid username' using errcode = '22023';
      end if;
      if not public.admin_password_is_strong(p_new_password) then
        raise exception 'new password does not meet strength policy'
          using errcode = '22023';
      end if;

      select * into seed
      from public.admin_accounts a
      where a.is_default_seed = true
      order by a.created_at
      limit 1;

      if found then
        if p_current_password is null
          or seed.password_hash is distinct from crypt(p_current_password, seed.password_hash) then
          raise exception 'current default password required'
            using errcode = '22023';
        end if;

        update public.admin_accounts as account
        set
          username = uname,
          password_hash = crypt(p_new_password, gen_salt('bf')),
          role = 'owner',
          is_default_seed = false,
          must_change_password = false,
          updated_at = now()
        where account.id = seed.id;

        update public.admin_sessions
        set revoked_at = now()
        where admin_id = seed.id
          and revoked_at is null;

        return query
        select account.id, account.username, account.role
        from public.admin_accounts account
        where account.id = seed.id;
        return;
      end if;

      if exists (select 1 from public.admin_accounts) then
        raise exception 'bootstrap not available' using errcode = '22023';
      end if;

      insert into public.admin_accounts (
        username, password_hash, role, is_default_seed, must_change_password
      ) values (
        uname, crypt(p_new_password, gen_salt('bf')), 'owner', false, false
      )
      returning
        public.admin_accounts.id,
        public.admin_accounts.username,
        public.admin_accounts.role
      into id, username, role;

      return next;
    end;
    $function$
  $ddl$;
end;
$migration$;
