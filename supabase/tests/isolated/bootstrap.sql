-- Developer: gengyun
-- Purpose: Supply synthetic Supabase platform objects to an ephemeral PostgreSQL fixture.
-- This is not a production schema or an implementation of Auth or Storage.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create schema storage;
create table auth.users (
    id uuid primary key,
    aud text,
    role text,
    email text,
    encrypted_password text,
    email_confirmed_at timestamptz,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    created_at timestamptz,
    updated_at timestamptz
);
create function auth.uid() returns uuid language sql stable as $$
    select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
    )::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
create table storage.buckets (
    id text primary key,
    name text not null,
    public boolean not null default false,
    file_size_limit bigint,
    allowed_mime_types text[]
);

-- Synthetic admin objects let the isolated SQL suite exercise the real
-- bootstrap RPC migration without connecting to a Supabase project.
create table public.admin_accounts (
    id uuid primary key default gen_random_uuid(),
    username text not null unique,
    password_hash text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    role text not null,
    is_default_seed boolean not null default false,
    must_change_password boolean not null default false
);
create table public.admin_sessions (
    id uuid primary key default gen_random_uuid(),
    admin_id uuid not null references public.admin_accounts(id),
    token_hash text not null,
    expires_at timestamptz not null default now() + interval '1 hour',
    created_at timestamptz not null default now(),
    revoked_at timestamptz
);
create function public.crypt(password text, salt text) returns text
language sql immutable as $$ select 'fixture-hash:' || password $$;
create function public.gen_salt(kind text) returns text
language sql immutable as $$ select 'fixture-salt' $$;
create function public.admin_password_is_strong(password text) returns boolean
language sql immutable as $$
    select char_length(password) >= 12
       and password ~ '[A-Z]'
       and password ~ '[a-z]'
       and password ~ '[0-9]'
       and lower(password) not in ('admin', 'password', 'password123', 'cookappadmin', 'adminadmin')
$$;

-- Legacy function source is not present in this public repository. These
-- deliberately nonfunctional signatures test only the migration's ACL effects.
-- Never claim their business logic or the private backend has been tested.
create function public.admin_bootstrap_owner(p_username text,p_new_password text,p_current_password text default null)
returns table(id uuid, username text, role text)
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.admin_change_password(uuid,text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.admin_verify_credentials(text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.capture_registration_meta(text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.get_runtime_config_number(text,numeric) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
