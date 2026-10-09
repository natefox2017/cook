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

-- Legacy function source is not present in this public repository. These
-- deliberately nonfunctional signatures test only the migration's ACL effects.
-- Never claim their business logic or the private backend has been tested.
create function public.admin_bootstrap_owner(text,text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.admin_change_password(uuid,text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.admin_verify_credentials(text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.capture_registration_meta(text,text) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
create function public.get_runtime_config_number(text,numeric) returns void
language plpgsql security definer as $$ begin raise exception 'fixture only'; end $$;
