-- Developer: gengyun
-- Purpose: Store encrypted TOTP factors, WebAuthn credentials, and one-time auth challenges for dashboard admins.

create table if not exists public.admin_auth_factors (
    admin_id uuid primary key references public.admin_accounts(id) on delete cascade,
    totp_secret_ciphertext text,
    totp_enabled_at timestamptz,
    totp_last_counter bigint not null default -1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint admin_auth_factors_totp_state check (
        (totp_enabled_at is null) or (totp_secret_ciphertext is not null)
    )
);

create table if not exists public.admin_passkeys (
    credential_id text primary key,
    admin_id uuid not null references public.admin_accounts(id) on delete cascade,
    public_key text not null,
    sign_count bigint not null default 0 check (sign_count >= 0),
    transports text[] not null default '{}',
    name text not null default 'Passkey',
    created_at timestamptz not null default now(),
    last_used_at timestamptz
);

create index if not exists admin_passkeys_admin_id_idx
    on public.admin_passkeys(admin_id);

create table if not exists public.admin_auth_login_challenges (
    id uuid primary key default gen_random_uuid(),
    admin_id uuid not null references public.admin_accounts(id) on delete cascade,
    challenge_hash text not null unique,
    attempts smallint not null default 0 check (attempts between 0 and 5),
    expires_at timestamptz not null,
    consumed_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.admin_auth_webauthn_challenges (
    id uuid primary key default gen_random_uuid(),
    admin_id uuid not null references public.admin_accounts(id) on delete cascade,
    purpose text not null check (purpose in ('register', 'login')),
    challenge text not null,
    session_id uuid references public.admin_sessions(id) on delete cascade,
    login_challenge_id uuid references public.admin_auth_login_challenges(id) on delete cascade,
    expires_at timestamptz not null,
    consumed_at timestamptz,
    created_at timestamptz not null default now(),
    constraint admin_auth_webauthn_challenge_owner check (
        (purpose = 'register' and session_id is not null and login_challenge_id is null)
        or (purpose = 'login' and session_id is null)
    )
);

create index if not exists admin_auth_login_challenges_expiry_idx
    on public.admin_auth_login_challenges(expires_at) where consumed_at is null;
create index if not exists admin_auth_webauthn_challenges_expiry_idx
    on public.admin_auth_webauthn_challenges(expires_at) where consumed_at is null;

alter table public.admin_auth_factors enable row level security;
alter table public.admin_passkeys enable row level security;
alter table public.admin_auth_login_challenges enable row level security;
alter table public.admin_auth_webauthn_challenges enable row level security;

revoke all on public.admin_auth_factors from anon, authenticated;
revoke all on public.admin_passkeys from anon, authenticated;
revoke all on public.admin_auth_login_challenges from anon, authenticated;
revoke all on public.admin_auth_webauthn_challenges from anon, authenticated;
grant all on public.admin_auth_factors to service_role;
grant all on public.admin_passkeys to service_role;
grant all on public.admin_auth_login_challenges to service_role;
grant all on public.admin_auth_webauthn_challenges to service_role;

-- A single account-level counter spans password, TOTP, and passkey failures.
create table if not exists public.admin_auth_login_state (
    identity_key text primary key,
    admin_id uuid references public.admin_accounts(id) on delete cascade,
    failed_attempts smallint not null default 0 check (failed_attempts between 0 and 5),
    locked_until timestamptz,
    updated_at timestamptz not null default now()
);

create table if not exists public.admin_auth_login_events (
    id uuid primary key default gen_random_uuid(),
    admin_id uuid references public.admin_accounts(id) on delete set null,
    method text not null check (method in ('password', 'totp', 'passkey', 'bootstrap')),
    success boolean not null,
    ip_address text,
    user_agent text,
    failure_reason text,
    created_at timestamptz not null default now(),
    constraint admin_auth_login_events_safe_reason check (
        failure_reason is null or failure_reason in
        ('invalid_credentials', 'invalid_totp', 'invalid_passkey', 'account_locked', 'bootstrap_failed')
    )
);

create index if not exists admin_auth_login_events_admin_created_idx
    on public.admin_auth_login_events(admin_id, created_at desc);
alter table public.admin_auth_login_state enable row level security;
alter table public.admin_auth_login_events enable row level security;
revoke all on public.admin_auth_login_state from public, anon, authenticated;
revoke all on public.admin_auth_login_events from public, anon, authenticated;
grant all on public.admin_auth_login_state to service_role;
grant all on public.admin_auth_login_events to service_role;

create or replace function public.admin_record_login_event(
    p_identity_key text,
    p_admin_id uuid,
    p_method text,
    p_success boolean,
    p_reset_failures boolean,
    p_ip_address text,
    p_user_agent text,
    p_failure_reason text
) returns table(allowed boolean, failed_attempts integer, locked_until timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
    state public.admin_auth_login_state%rowtype;
    event_success boolean := p_success;
    event_reason text := p_failure_reason;
    v_now timestamptz := pg_catalog.clock_timestamp();
begin
    if p_method not in ('password', 'totp', 'passkey', 'bootstrap') then
        raise exception 'invalid login event method';
    end if;
    if p_failure_reason is not null and p_failure_reason not in
        ('invalid_credentials', 'invalid_totp', 'invalid_passkey', 'account_locked', 'bootstrap_failed') then
        raise exception 'invalid login event reason';
    end if;

    if p_identity_key is null then
        event_success := false;
        event_reason := coalesce(event_reason, 'invalid_passkey');
        insert into public.admin_auth_login_events(admin_id, method, success, ip_address, user_agent, failure_reason)
        values (p_admin_id, p_method, false, left(p_ip_address, 64), left(p_user_agent, 512), event_reason);
        return query select false, 0, null::timestamptz;
        return;
    end if;

    insert into public.admin_auth_login_state(identity_key, admin_id)
    values (p_identity_key, p_admin_id)
    on conflict (identity_key) do update
      set admin_id = coalesce(public.admin_auth_login_state.admin_id, excluded.admin_id),
          updated_at = v_now;
    select * into state from public.admin_auth_login_state s
    where s.identity_key = p_identity_key for update;

    if state.locked_until is not null and state.locked_until > v_now then
        event_success := false;
        event_reason := 'account_locked';
    elsif p_success and p_reset_failures then
        update public.admin_auth_login_state s
        set failed_attempts = 0, locked_until = null, updated_at = v_now
        where s.identity_key = p_identity_key;
        state.failed_attempts := 0;
        state.locked_until := null;
    elsif p_success then
        null;
    else
        state.failed_attempts := case
          when state.locked_until is not null and state.locked_until <= v_now then 1
          else least(state.failed_attempts + 1, 5)
        end;
        state.locked_until := case when state.failed_attempts >= 5
          then v_now + interval '24 hours' else null end;
        update public.admin_auth_login_state s
        set failed_attempts = state.failed_attempts, locked_until = state.locked_until, updated_at = v_now
        where s.identity_key = p_identity_key;
    end if;

    insert into public.admin_auth_login_events(admin_id, method, success, ip_address, user_agent, failure_reason)
    values (p_admin_id, p_method, event_success, left(p_ip_address, 64), left(p_user_agent, 512),
      case when event_success then null else coalesce(event_reason, 'invalid_credentials') end);
    return query select event_success, state.failed_attempts::integer, state.locked_until;
end;
$function$;

revoke all on function public.admin_record_login_event(text, uuid, text, boolean, boolean, text, text, text)
    from public, anon, authenticated;
grant execute on function public.admin_record_login_event(text, uuid, text, boolean, boolean, text, text, text)
    to service_role;
