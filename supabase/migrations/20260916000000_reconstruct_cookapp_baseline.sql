-- Developer: gengyun
-- Purpose: Restore the versioned public schema baseline omitted from the repository migrations.
-- Captured from production PostgreSQL catalogs on 2026-10-09; schema only, no row data.
-- Every object is created only when absent; existing deployed table/function/view definitions are preserved.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm with schema extensions;

do $baseline_table_001$
begin
  if to_regclass('public.admin_accounts') is null then
    execute $ddl$create table public."admin_accounts" (
    "id" uuid default gen_random_uuid() not null,
    "username" text not null,
    "password_hash" text not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    "role" text default 'owner'::text not null,
    "is_default_seed" boolean default false not null,
    "must_change_password" boolean default false not null,
    constraint "admin_accounts_pkey" PRIMARY KEY (id),
    constraint "admin_accounts_role_check" CHECK (role = ANY (ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'readonly'::text])),
    constraint "admin_accounts_username_key" UNIQUE (username),
    constraint "admin_accounts_username_nonempty" CHECK (char_length(TRIM(BOTH FROM username)) > 0)
);$ddl$;
    execute 'alter table public."admin_accounts" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."admin_accounts" to "service_role"';
  end if;
end;
$baseline_table_001$;

do $baseline_table_002$
begin
  if to_regclass('public.admin_audit_logs') is null then
    execute $ddl$create table public."admin_audit_logs" (
    "id" uuid default gen_random_uuid() not null,
    "actor_admin_id" uuid,
    "actor_username" text,
    "action" text not null,
    "object_type" text not null,
    "object_id" text,
    "before_diff" jsonb,
    "after_diff" jsonb,
    "request_id" text,
    "correlation_id" text,
    "job_id" text,
    "ip" text,
    "user_agent" text,
    "created_at" timestamp with time zone default now() not null,
    constraint "admin_audit_logs_action_nonempty" CHECK (char_length(TRIM(BOTH FROM action)) > 0),
    constraint "admin_audit_logs_actor_admin_id_fkey" FOREIGN KEY (actor_admin_id) REFERENCES public."admin_accounts"(id) ON DELETE SET NULL,
    constraint "admin_audit_logs_object_type_nonempty" CHECK (char_length(TRIM(BOTH FROM object_type)) > 0),
    constraint "admin_audit_logs_pkey" PRIMARY KEY (id)
);$ddl$;
    execute 'alter table public."admin_audit_logs" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."admin_audit_logs" to "service_role"';
  end if;
end;
$baseline_table_002$;

do $baseline_table_003$
begin
  if to_regclass('public.admin_sessions') is null then
    execute $ddl$create table public."admin_sessions" (
    "id" uuid default gen_random_uuid() not null,
    "admin_id" uuid not null,
    "token_hash" text not null,
    "expires_at" timestamp with time zone not null,
    "created_at" timestamp with time zone default now() not null,
    "revoked_at" timestamp with time zone,
    constraint "admin_sessions_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES public."admin_accounts"(id) ON DELETE CASCADE,
    constraint "admin_sessions_expires_after_created" CHECK (expires_at > created_at),
    constraint "admin_sessions_pkey" PRIMARY KEY (id),
    constraint "admin_sessions_token_hash_key" UNIQUE (token_hash)
);$ddl$;
    execute 'alter table public."admin_sessions" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."admin_sessions" to "service_role"';
  end if;
end;
$baseline_table_003$;

do $baseline_table_004$
begin
  if to_regclass('public.ai_secrets') is null then
    execute $ddl$create table public."ai_secrets" (
    "id" uuid default gen_random_uuid() not null,
    "secret_ref" text not null,
    "ciphertext" text not null,
    "nonce" text not null,
    "key_version" integer default 1 not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ai_secrets_ciphertext_nonempty" CHECK (char_length(ciphertext) > 0),
    constraint "ai_secrets_pkey" PRIMARY KEY (id),
    constraint "ai_secrets_ref_nonempty" CHECK (char_length(TRIM(BOTH FROM secret_ref)) > 0),
    constraint "ai_secrets_secret_ref_key" UNIQUE (secret_ref)
);$ddl$;
    execute 'alter table public."ai_secrets" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_secrets" to "service_role"';
  end if;
end;
$baseline_table_004$;

do $baseline_table_005$
begin
  if to_regclass('public.ai_providers') is null then
    execute $ddl$create table public."ai_providers" (
    "id" uuid default gen_random_uuid() not null,
    "name" text not null,
    "protocol" text default 'openai_compatible'::text not null,
    "base_url" text not null,
    "secret_ref" text,
    "enabled" boolean default true not null,
    "request_timeout_ms" integer default 30000 not null,
    "max_retries" integer default 1 not null,
    "status" text default 'unknown'::text not null,
    "last_health_check_at" timestamp with time zone,
    "environment" text default 'production'::text not null,
    "metadata" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ai_providers_base_url_nonempty" CHECK (char_length(TRIM(BOTH FROM base_url)) > 0),
    constraint "ai_providers_environment_check" CHECK (environment = ANY (ARRAY['development'::text, 'production'::text])),
    constraint "ai_providers_max_retries_check" CHECK (max_retries >= 0 AND max_retries <= 5),
    constraint "ai_providers_name_nonempty" CHECK (char_length(TRIM(BOTH FROM name)) > 0),
    constraint "ai_providers_pkey" PRIMARY KEY (id),
    constraint "ai_providers_protocol_check" CHECK (protocol = 'openai_compatible'::text),
    constraint "ai_providers_request_timeout_ms_check" CHECK (request_timeout_ms >= 1000 AND request_timeout_ms <= 300000),
    constraint "ai_providers_secret_ref_fkey" FOREIGN KEY (secret_ref) REFERENCES public."ai_secrets"(secret_ref) ON DELETE SET NULL,
    constraint "ai_providers_status_check" CHECK (status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'degraded'::text, 'unhealthy'::text]))
);$ddl$;
    execute 'alter table public."ai_providers" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_providers" to "service_role"';
  end if;
end;
$baseline_table_005$;

do $baseline_table_006$
begin
  if to_regclass('public.ai_models') is null then
    execute $ddl$create table public."ai_models" (
    "id" uuid default gen_random_uuid() not null,
    "provider_id" uuid not null,
    "display_name" text not null,
    "upstream_model_id" text not null,
    "enabled" boolean default true not null,
    "capabilities" jsonb default '{"text": true}'::jsonb not null,
    "context_window" integer,
    "max_output_tokens" integer,
    "cost_input_per_1m" numeric(18,6),
    "cost_output_per_1m" numeric(18,6),
    "metadata" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ai_models_display_name_nonempty" CHECK (char_length(TRIM(BOTH FROM display_name)) > 0),
    constraint "ai_models_pkey" PRIMARY KEY (id),
    constraint "ai_models_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES public."ai_providers"(id) ON DELETE CASCADE,
    constraint "ai_models_provider_upstream_unique" UNIQUE (provider_id, upstream_model_id),
    constraint "ai_models_upstream_nonempty" CHECK (char_length(TRIM(BOTH FROM upstream_model_id)) > 0)
);$ddl$;
    execute 'alter table public."ai_models" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_models" to "service_role"';
  end if;
end;
$baseline_table_006$;

do $baseline_table_007$
begin
  if to_regclass('public.ai_provider_health') is null then
    execute $ddl$create table public."ai_provider_health" (
    "provider_id" uuid not null,
    "status" text default 'unknown'::text not null,
    "last_success_at" timestamp with time zone,
    "last_error_at" timestamp with time zone,
    "last_error" text,
    "consecutive_failures" integer default 0 not null,
    "circuit_open_until" timestamp with time zone,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ai_provider_health_consecutive_failures_check" CHECK (consecutive_failures >= 0),
    constraint "ai_provider_health_pkey" PRIMARY KEY (provider_id),
    constraint "ai_provider_health_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES public."ai_providers"(id) ON DELETE CASCADE,
    constraint "ai_provider_health_status_check" CHECK (status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'degraded'::text, 'unhealthy'::text]))
);$ddl$;
    execute 'alter table public."ai_provider_health" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_provider_health" to "service_role"';
  end if;
end;
$baseline_table_007$;

do $baseline_table_008$
begin
  if to_regclass('public.ai_routes') is null then
    execute $ddl$create table public."ai_routes" (
    "id" uuid default gen_random_uuid() not null,
    "route_key" text not null,
    "primary_model_id" uuid,
    "fallback_model_ids" uuid[] default '{}'::uuid[] not null,
    "timeout_ms" integer default 60000 not null,
    "max_retries" integer default 1 not null,
    "temperature" numeric(4,3),
    "max_output_tokens" integer,
    "structured_schema_key" text,
    "enabled" boolean default true not null,
    "reserved" boolean default false not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ai_routes_fallback_limit" CHECK (cardinality(fallback_model_ids) <= 3),
    constraint "ai_routes_key_nonempty" CHECK (char_length(TRIM(BOTH FROM route_key)) > 0),
    constraint "ai_routes_max_retries_check" CHECK (max_retries >= 0 AND max_retries <= 3),
    constraint "ai_routes_pkey" PRIMARY KEY (id),
    constraint "ai_routes_primary_model_id_fkey" FOREIGN KEY (primary_model_id) REFERENCES public."ai_models"(id) ON DELETE SET NULL,
    constraint "ai_routes_route_key_key" UNIQUE (route_key),
    constraint "ai_routes_timeout_ms_check" CHECK (timeout_ms >= 1000 AND timeout_ms <= 300000)
);$ddl$;
    execute 'alter table public."ai_routes" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_routes" to "service_role"';
  end if;
end;
$baseline_table_008$;

do $baseline_table_009$
begin
  if to_regclass('public.ai_usage_events') is null then
    execute $ddl$create table public."ai_usage_events" (
    "id" uuid default gen_random_uuid() not null,
    "request_id" text not null,
    "route_key" text not null,
    "provider_id" uuid,
    "model_id" uuid,
    "final_model_id" uuid,
    "status" text not null,
    "latency_ms" integer,
    "input_tokens" integer,
    "output_tokens" integer,
    "estimated_cost" numeric(18,8),
    "retry_count" integer default 0 not null,
    "error_code" text,
    "attempted_models" jsonb default '[]'::jsonb not null,
    "user_id" uuid,
    "admin_id" uuid,
    "source_job_id" text,
    "created_at" timestamp with time zone default now() not null,
    constraint "ai_usage_events_final_model_id_fkey" FOREIGN KEY (final_model_id) REFERENCES public."ai_models"(id) ON DELETE SET NULL,
    constraint "ai_usage_events_model_id_fkey" FOREIGN KEY (model_id) REFERENCES public."ai_models"(id) ON DELETE SET NULL,
    constraint "ai_usage_events_pkey" PRIMARY KEY (id),
    constraint "ai_usage_events_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES public."ai_providers"(id) ON DELETE SET NULL,
    constraint "ai_usage_events_request_id_nonempty" CHECK (char_length(TRIM(BOTH FROM request_id)) > 0),
    constraint "ai_usage_events_status_check" CHECK (status = ANY (ARRAY['success'::text, 'error'::text, 'timeout'::text, 'fallback_exhausted'::text, 'circuit_open'::text]))
);$ddl$;
    execute 'alter table public."ai_usage_events" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ai_usage_events" to "service_role"';
  end if;
end;
$baseline_table_009$;

do $baseline_table_010$
begin
  if to_regclass('public.app_download_stats') is null then
    execute $ddl$create table public."app_download_stats" (
    "id" uuid default gen_random_uuid() not null,
    "platform" text not null,
    "year_month" date not null,
    "downloads" integer not null,
    "source" text default 'manual'::text not null,
    "notes" text,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "app_download_stats_downloads_check" CHECK (downloads >= 0),
    constraint "app_download_stats_month_first_day" CHECK (EXTRACT(day FROM year_month) = 1::numeric),
    constraint "app_download_stats_pkey" PRIMARY KEY (id),
    constraint "app_download_stats_platform_check" CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text])),
    constraint "app_download_stats_platform_month_unique" UNIQUE (platform, year_month),
    constraint "app_download_stats_source_check" CHECK (source = ANY (ARRAY['manual'::text, 'app_store_connect'::text, 'play_console'::text, 'seed'::text]))
);$ddl$;
    execute 'alter table public."app_download_stats" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."app_download_stats" to "service_role"';
  end if;
end;
$baseline_table_010$;

do $baseline_table_011$
begin
  if to_regclass('public.cuisines') is null then
    execute $ddl$create table public."cuisines" (
    "id" text not null,
    "name" text not null,
    "sort_order" integer default 0 not null,
    constraint "cuisines_pkey" PRIMARY KEY (id)
);$ddl$;
    execute 'alter table public."cuisines" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."cuisines" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."cuisines" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."cuisines" to "service_role"';
  end if;
end;
$baseline_table_011$;

do $baseline_table_012$
begin
  if to_regclass('public.meal_categories') is null then
    execute $ddl$create table public."meal_categories" (
    "id" text not null,
    "name" text not null,
    "sort_order" integer default 0 not null,
    constraint "meal_categories_pkey" PRIMARY KEY (id)
);$ddl$;
    execute 'alter table public."meal_categories" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_categories" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_categories" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_categories" to "service_role"';
  end if;
end;
$baseline_table_012$;

do $baseline_table_013$
begin
  if to_regclass('public.collections') is null then
    execute $ddl$create table public."collections" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid not null,
    "name" text not null,
    "cover" text,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "collections_name_nonempty" CHECK (char_length(TRIM(BOTH FROM name)) > 0),
    constraint "collections_pkey" PRIMARY KEY (id),
    constraint "collections_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."collections" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collections" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collections" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collections" to "service_role"';
  end if;
end;
$baseline_table_013$;

do $baseline_table_014$
begin
  if to_regclass('public.profiles') is null then
    execute $ddl$create table public."profiles" (
    "id" uuid not null,
    "display_name" text,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    "email" text,
    "avatar" text,
    "locale" text,
    "timezone" text,
    "device_type" text,
    "registration_ip" text,
    "account_status" text default 'active'::text not null,
    "registration_provider" text,
    constraint "profiles_account_status_check" CHECK (account_status = ANY (ARRAY['active'::text, 'suspended'::text, 'deleted'::text])),
    constraint "profiles_device_type_check" CHECK (device_type IS NULL OR (device_type = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text, 'unknown'::text]))),
    constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
    constraint "profiles_pkey" PRIMARY KEY (id),
    constraint "profiles_registration_provider_check" CHECK (registration_provider IS NULL OR (registration_provider = ANY (ARRAY['apple'::text, 'google'::text, 'email'::text, 'unknown'::text])))
);$ddl$;
    execute 'alter table public."profiles" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE on table public."profiles" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE on table public."profiles" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."profiles" to "service_role"';
  end if;
end;
$baseline_table_014$;

do $baseline_table_015$
begin
  if to_regclass('public.purchase_events') is null then
    execute $ddl$create table public."purchase_events" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid,
    "rc_event_id" text,
    "event_type" text not null,
    "product_id" text,
    "store" text,
    "environment" text,
    "raw_event" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    constraint "purchase_events_pkey" PRIMARY KEY (id),
    constraint "purchase_events_rc_event_id_unique" UNIQUE (rc_event_id),
    constraint "purchase_events_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);$ddl$;
    execute 'alter table public."purchase_events" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."purchase_events" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."purchase_events" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."purchase_events" to "service_role"';
  end if;
end;
$baseline_table_015$;

do $baseline_table_016$
begin
  if to_regclass('public.recipes') is null then
    execute $ddl$create table public."recipes" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid not null,
    "title" text not null,
    "description" text,
    "cover_image" text,
    "cuisine" text,
    "category" text,
    "tags" text[] default '{}'::text[] not null,
    "ingredients" jsonb default '[]'::jsonb not null,
    "steps" jsonb default '[]'::jsonb not null,
    "nutrition" jsonb default '{}'::jsonb not null,
    "cooking_time" integer,
    "servings" integer,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "recipes_category_fkey" FOREIGN KEY (category) REFERENCES public."meal_categories"(id) ON DELETE SET NULL,
    constraint "recipes_cooking_time_nonneg" CHECK (cooking_time IS NULL OR cooking_time >= 0),
    constraint "recipes_cuisine_fkey" FOREIGN KEY (cuisine) REFERENCES public."cuisines"(id) ON DELETE SET NULL,
    constraint "recipes_ingredients_is_array" CHECK (jsonb_typeof(ingredients) = 'array'::text),
    constraint "recipes_nutrition_is_object" CHECK (jsonb_typeof(nutrition) = 'object'::text),
    constraint "recipes_pkey" PRIMARY KEY (id),
    constraint "recipes_servings_positive" CHECK (servings IS NULL OR servings > 0),
    constraint "recipes_steps_is_array" CHECK (jsonb_typeof(steps) = 'array'::text),
    constraint "recipes_title_nonempty" CHECK (char_length(TRIM(BOTH FROM title)) > 0),
    constraint "recipes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."recipes" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."recipes" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."recipes" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."recipes" to "service_role"';
  end if;
end;
$baseline_table_016$;

do $baseline_table_017$
begin
  if to_regclass('public.collection_recipes') is null then
    execute $ddl$create table public."collection_recipes" (
    "collection_id" uuid not null,
    "recipe_id" uuid not null,
    "added_at" timestamp with time zone default now() not null,
    constraint "collection_recipes_collection_id_fkey" FOREIGN KEY (collection_id) REFERENCES public."collections"(id) ON DELETE CASCADE,
    constraint "collection_recipes_pkey" PRIMARY KEY (collection_id, recipe_id),
    constraint "collection_recipes_recipe_id_fkey" FOREIGN KEY (recipe_id) REFERENCES public."recipes"(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."collection_recipes" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collection_recipes" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collection_recipes" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."collection_recipes" to "service_role"';
  end if;
end;
$baseline_table_017$;

do $baseline_table_018$
begin
  if to_regclass('public.grocery_lists') is null then
    execute $ddl$create table public."grocery_lists" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid not null,
    "name" text not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "grocery_lists_name_nonempty" CHECK (char_length(TRIM(BOTH FROM name)) > 0),
    constraint "grocery_lists_pkey" PRIMARY KEY (id),
    constraint "grocery_lists_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."grocery_lists" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_lists" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_lists" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_lists" to "service_role"';
  end if;
end;
$baseline_table_018$;

do $baseline_table_019$
begin
  if to_regclass('public.grocery_items') is null then
    execute $ddl$create table public."grocery_items" (
    "id" uuid default gen_random_uuid() not null,
    "list_id" uuid not null,
    "ingredient" text not null,
    "quantity" numeric,
    "unit" text,
    "category" text,
    "completed" boolean default false not null,
    "sort_order" integer default 0 not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "grocery_items_ingredient_nonempty" CHECK (char_length(TRIM(BOTH FROM ingredient)) > 0),
    constraint "grocery_items_list_id_fkey" FOREIGN KEY (list_id) REFERENCES public."grocery_lists"(id) ON DELETE CASCADE,
    constraint "grocery_items_pkey" PRIMARY KEY (id)
);$ddl$;
    execute 'alter table public."grocery_items" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_items" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_items" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."grocery_items" to "service_role"';
  end if;
end;
$baseline_table_019$;

do $baseline_table_020$
begin
  if to_regclass('public.ingredients') is null then
    execute $ddl$create table public."ingredients" (
    "id" uuid default gen_random_uuid() not null,
    "name" text not null,
    "category" text,
    "unit" text,
    "alternative_name" text,
    "user_id" uuid,
    "is_system" boolean default false not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "ingredients_name_nonempty" CHECK (char_length(TRIM(BOTH FROM name)) > 0),
    constraint "ingredients_pkey" PRIMARY KEY (id),
    constraint "ingredients_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."ingredients" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ingredients" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ingredients" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."ingredients" to "service_role"';
  end if;
end;
$baseline_table_020$;

do $baseline_table_021$
begin
  if to_regclass('public.meal_plans') is null then
    execute $ddl$create table public."meal_plans" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid not null,
    "plan_date" date not null,
    "meal_type" text not null,
    "recipe_id" uuid not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "meal_plans_meal_type_check" CHECK (meal_type = ANY (ARRAY['breakfast'::text, 'lunch'::text, 'dinner'::text])),
    constraint "meal_plans_pkey" PRIMARY KEY (id),
    constraint "meal_plans_recipe_id_fkey" FOREIGN KEY (recipe_id) REFERENCES public."recipes"(id) ON DELETE CASCADE,
    constraint "meal_plans_unique_slot" UNIQUE (user_id, plan_date, meal_type, recipe_id),
    constraint "meal_plans_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."meal_plans" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_plans" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_plans" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."meal_plans" to "service_role"';
  end if;
end;
$baseline_table_021$;

do $baseline_table_022$
begin
  if to_regclass('public.pantry_items') is null then
    execute $ddl$create table public."pantry_items" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid not null,
    "ingredient" text not null,
    "quantity" numeric,
    "unit" text,
    "expiration_date" date,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "pantry_items_ingredient_nonempty" CHECK (char_length(TRIM(BOTH FROM ingredient)) > 0),
    constraint "pantry_items_pkey" PRIMARY KEY (id),
    constraint "pantry_items_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."pantry_items" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."pantry_items" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."pantry_items" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."pantry_items" to "service_role"';
  end if;
end;
$baseline_table_022$;

do $baseline_table_023$
begin
  if to_regclass('public.payment_transactions') is null then
    execute $ddl$create table public."payment_transactions" (
    "id" uuid default gen_random_uuid() not null,
    "user_id" uuid,
    "platform" text,
    "store" text,
    "environment" text,
    "product_id" text,
    "entitlement_id" text,
    "transaction_id" text,
    "original_transaction_id" text,
    "order_id" text,
    "purchase_token" text,
    "event_type" text not null,
    "status" text default 'unknown'::text not null,
    "purchase_at" timestamp with time zone,
    "renewal_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "cancel_at" timestamp with time zone,
    "refund_at" timestamp with time zone,
    "currency" text,
    "gross_amount" numeric(14,4),
    "refund_amount" numeric(14,4),
    "estimated_proceeds" numeric(14,4),
    "final_proceeds" numeric(14,4),
    "estimated_gross_usd" numeric(14,4),
    "territory" text,
    "provider_source" text default 'revenuecat'::text not null,
    "provider_event_id" text,
    "purchase_event_id" uuid,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "payment_transactions_environment_check" CHECK (environment IS NULL OR (environment = ANY (ARRAY['sandbox'::text, 'production'::text]))),
    constraint "payment_transactions_pkey" PRIMARY KEY (id),
    constraint "payment_transactions_platform_check" CHECK (platform IS NULL OR (platform = ANY (ARRAY['ios'::text, 'android'::text]))),
    constraint "payment_transactions_provider_event_unique" UNIQUE (provider_source, provider_event_id),
    constraint "payment_transactions_provider_source_check" CHECK (provider_source = ANY (ARRAY['revenuecat'::text, 'app_store'::text, 'google_play'::text, 'apple_financial'::text, 'manual'::text])),
    constraint "payment_transactions_purchase_event_id_fkey" FOREIGN KEY (purchase_event_id) REFERENCES public."purchase_events"(id) ON DELETE SET NULL,
    constraint "payment_transactions_status_check" CHECK (status = ANY (ARRAY['active'::text, 'trialing'::text, 'cancelled'::text, 'expired'::text, 'billing_issue'::text, 'refunded'::text, 'unknown'::text])),
    constraint "payment_transactions_store_check" CHECK (store IS NULL OR (store = ANY (ARRAY['app_store'::text, 'google_play'::text, 'stripe'::text, 'promotional'::text, 'rc_billing'::text, 'unknown'::text]))),
    constraint "payment_transactions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);$ddl$;
    execute 'alter table public."payment_transactions" enable row level security';
    execute 'grant MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE on table public."payment_transactions" to "anon"';
    execute 'grant MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE on table public."payment_transactions" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."payment_transactions" to "service_role"';
  end if;
end;
$baseline_table_023$;

do $baseline_table_024$
begin
  if to_regclass('public.runtime_config') is null then
    execute $ddl$create table public."runtime_config" (
    "key" text not null,
    "value" jsonb not null,
    "description" text,
    "updated_at" timestamp with time zone default now() not null,
    constraint "runtime_config_pkey" PRIMARY KEY (key),
    constraint "runtime_config_value_object_or_scalar" CHECK (jsonb_typeof(value) = ANY (ARRAY['number'::text, 'string'::text, 'boolean'::text, 'object'::text, 'array'::text]))
);$ddl$;
    execute 'alter table public."runtime_config" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."runtime_config" to "service_role"';
  end if;
end;
$baseline_table_024$;

do $baseline_table_025$
begin
  if to_regclass('public.store_secrets') is null then
    execute $ddl$create table public."store_secrets" (
    "id" uuid default gen_random_uuid() not null,
    "secret_ref" text not null,
    "ciphertext" text not null,
    "nonce" text not null,
    "key_version" integer default 1 not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "store_secrets_ciphertext_nonempty" CHECK (char_length(ciphertext) > 0),
    constraint "store_secrets_pkey" PRIMARY KEY (id),
    constraint "store_secrets_ref_nonempty" CHECK (char_length(TRIM(BOTH FROM secret_ref)) > 0),
    constraint "store_secrets_secret_ref_key" UNIQUE (secret_ref)
);$ddl$;
    execute 'alter table public."store_secrets" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."store_secrets" to "service_role"';
  end if;
end;
$baseline_table_025$;

do $baseline_table_026$
begin
  if to_regclass('public.store_integrations') is null then
    execute $ddl$create table public."store_integrations" (
    "id" uuid default gen_random_uuid() not null,
    "provider" text not null,
    "display_name" text not null,
    "platform" text not null,
    "store" text not null,
    "status" text default 'not_configured'::text not null,
    "issuer_id" text,
    "key_id" text,
    "vendor_number" text,
    "app_apple_id" text,
    "secret_ref" text,
    "last_success_at" timestamp with time zone,
    "last_error_at" timestamp with time zone,
    "last_error" text,
    "metadata" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "store_integrations_display_name_nonempty" CHECK (char_length(TRIM(BOTH FROM display_name)) > 0),
    constraint "store_integrations_pkey" PRIMARY KEY (id),
    constraint "store_integrations_platform_check" CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text])),
    constraint "store_integrations_provider_check" CHECK (provider = ANY (ARRAY['apple_app_store'::text, 'google_play'::text])),
    constraint "store_integrations_provider_key" UNIQUE (provider),
    constraint "store_integrations_secret_ref_fkey" FOREIGN KEY (secret_ref) REFERENCES public."store_secrets"(secret_ref) ON DELETE SET NULL,
    constraint "store_integrations_status_check" CHECK (status = ANY (ARRAY['not_configured'::text, 'configured'::text, 'degraded'::text, 'error'::text, 'future_reserved'::text])),
    constraint "store_integrations_store_check" CHECK (store = ANY (ARRAY['app_store'::text, 'google_play'::text]))
);$ddl$;
    execute 'alter table public."store_integrations" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."store_integrations" to "service_role"';
  end if;
end;
$baseline_table_026$;

do $baseline_table_027$
begin
  if to_regclass('public.store_sync_runs') is null then
    execute $ddl$create table public."store_sync_runs" (
    "id" uuid default gen_random_uuid() not null,
    "job_type" text not null,
    "provider" text not null,
    "status" text default 'pending'::text not null,
    "triggered_by" text default 'manual'::text not null,
    "actor_admin_id" uuid,
    "started_at" timestamp with time zone default now() not null,
    "completed_at" timestamp with time zone,
    "rows_upserted" integer default 0 not null,
    "error_code" text,
    "error_message" text,
    "cursor_token" text,
    "range_start" date,
    "range_end" date,
    "request_id" text,
    "correlation_id" text,
    "metadata" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    constraint "store_sync_runs_job_type_check" CHECK (job_type = ANY (ARRAY['store_analytics_sync'::text, 'financial_report_sync'::text])),
    constraint "store_sync_runs_pkey" PRIMARY KEY (id),
    constraint "store_sync_runs_provider_check" CHECK (provider = ANY (ARRAY['apple_app_store'::text, 'google_play'::text])),
    constraint "store_sync_runs_rows_upserted_check" CHECK (rows_upserted >= 0),
    constraint "store_sync_runs_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'skipped_not_configured'::text, 'skipped_reserved'::text])),
    constraint "store_sync_runs_triggered_by_check" CHECK (triggered_by = ANY (ARRAY['manual'::text, 'cron'::text, 'worker'::text]))
);$ddl$;
    execute 'alter table public."store_sync_runs" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."store_sync_runs" to "service_role"';
  end if;
end;
$baseline_table_027$;

do $baseline_table_028$
begin
  if to_regclass('public.financial_report_rows') is null then
    execute $ddl$create table public."financial_report_rows" (
    "id" uuid default gen_random_uuid() not null,
    "platform" text not null,
    "store" text not null,
    "fiscal_period" text not null,
    "report_date" date,
    "territory" text,
    "currency" text,
    "product_id" text,
    "units" integer,
    "gross_amount" numeric(20,4),
    "developer_proceeds" numeric(20,4),
    "taxes" numeric(20,4),
    "adjustments" numeric(20,4),
    "exchange_rate" numeric(20,8),
    "report_status" text default 'final'::text not null,
    "provider_source" text not null,
    "provider_row_key" text not null,
    "sync_run_id" uuid,
    "synced_at" timestamp with time zone default now() not null,
    "dimensions" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "financial_report_rows_fiscal_period_nonempty" CHECK (char_length(TRIM(BOTH FROM fiscal_period)) > 0),
    constraint "financial_report_rows_pkey" PRIMARY KEY (id),
    constraint "financial_report_rows_platform_check" CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text])),
    constraint "financial_report_rows_provider_key_unique" UNIQUE (provider_source, provider_row_key),
    constraint "financial_report_rows_provider_source_check" CHECK (provider_source = ANY (ARRAY['apple_financial_reports'::text, 'google_play_financial_reports'::text, 'manual'::text])),
    constraint "financial_report_rows_report_status_check" CHECK (report_status = ANY (ARRAY['preliminary'::text, 'final'::text, 'adjusted'::text, 'unavailable'::text])),
    constraint "financial_report_rows_store_check" CHECK (store = ANY (ARRAY['app_store'::text, 'google_play'::text])),
    constraint "financial_report_rows_sync_run_id_fkey" FOREIGN KEY (sync_run_id) REFERENCES public."store_sync_runs"(id) ON DELETE SET NULL
);$ddl$;
    execute 'alter table public."financial_report_rows" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."financial_report_rows" to "service_role"';
  end if;
end;
$baseline_table_028$;

do $baseline_table_029$
begin
  if to_regclass('public.store_analytics_daily') is null then
    execute $ddl$create table public."store_analytics_daily" (
    "id" uuid default gen_random_uuid() not null,
    "metric_date" date not null,
    "platform" text not null,
    "store" text not null,
    "territory" text default ''::text not null,
    "acquisition_source" text default ''::text not null,
    "metric_key" text not null,
    "metric_value" numeric(20,4),
    "data_status" text default 'available'::text not null,
    "provider_source" text not null,
    "estimated" boolean default true not null,
    "sync_run_id" uuid,
    "synced_at" timestamp with time zone default now() not null,
    "dimensions" jsonb default '{}'::jsonb not null,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "store_analytics_daily_data_status_check" CHECK (data_status = ANY (ARRAY['available'::text, 'insufficient'::text, 'not_returned'::text, 'not_configured'::text])),
    constraint "store_analytics_daily_grain_unique" UNIQUE (metric_date, platform, store, territory, acquisition_source, metric_key, provider_source),
    constraint "store_analytics_daily_metric_key_check" CHECK (metric_key = ANY (ARRAY['first_time_downloads'::text, 'redownloads'::text, 'total_downloads'::text, 'units'::text, 'product_page_views'::text, 'impressions'::text, 'paying_users'::text, 'purchases'::text, 'sessions'::text, 'installs'::text, 'deletions'::text, 'other'::text])),
    constraint "store_analytics_daily_pkey" PRIMARY KEY (id),
    constraint "store_analytics_daily_platform_check" CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text])),
    constraint "store_analytics_daily_provider_source_check" CHECK (provider_source = ANY (ARRAY['app_store_connect_analytics'::text, 'sales_and_trends'::text, 'google_play_console'::text, 'manual'::text])),
    constraint "store_analytics_daily_store_check" CHECK (store = ANY (ARRAY['app_store'::text, 'google_play'::text])),
    constraint "store_analytics_daily_sync_run_id_fkey" FOREIGN KEY (sync_run_id) REFERENCES public."store_sync_runs"(id) ON DELETE SET NULL
);$ddl$;
    execute 'alter table public."store_analytics_daily" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."store_analytics_daily" to "service_role"';
  end if;
end;
$baseline_table_029$;

do $baseline_table_030$
begin
  if to_regclass('public.subscription_plans') is null then
    execute $ddl$create table public."subscription_plans" (
    "id" uuid default gen_random_uuid() not null,
    "plan_key" text not null,
    "display_name" text not null,
    "platform" text not null,
    "product_id" text not null,
    "price" numeric(12,2) not null,
    "currency" text default 'USD'::text not null,
    "billing_period" text not null,
    "active" boolean default true not null,
    "description" text,
    "created_at" timestamp with time zone default now() not null,
    "updated_at" timestamp with time zone default now() not null,
    constraint "subscription_plans_billing_period_check" CHECK (billing_period = ANY (ARRAY['monthly'::text, 'yearly'::text, 'lifetime'::text])),
    constraint "subscription_plans_key_nonempty" CHECK (char_length(TRIM(BOTH FROM plan_key)) > 0),
    constraint "subscription_plans_name_nonempty" CHECK (char_length(TRIM(BOTH FROM display_name)) > 0),
    constraint "subscription_plans_pkey" PRIMARY KEY (id),
    constraint "subscription_plans_platform_check" CHECK (platform = ANY (ARRAY['app_store'::text, 'play_store'::text])),
    constraint "subscription_plans_platform_product_unique" UNIQUE (platform, product_id),
    constraint "subscription_plans_price_check" CHECK (price >= 0::numeric),
    constraint "subscription_plans_product_nonempty" CHECK (char_length(TRIM(BOTH FROM product_id)) > 0)
);$ddl$;
    execute 'alter table public."subscription_plans" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscription_plans" to "service_role"';
  end if;
end;
$baseline_table_030$;

do $baseline_table_031$
begin
  if to_regclass('public.subscriptions') is null then
    execute $ddl$create table public."subscriptions" (
    "user_id" uuid not null,
    "entitlement_id" text,
    "product_id" text,
    "status" text default 'none'::text not null,
    "store" text,
    "environment" text,
    "expires_at" timestamp with time zone,
    "will_renew" boolean,
    "revenuecat_app_user_id" text,
    "latest_event_type" text,
    "updated_at" timestamp with time zone default now() not null,
    "created_at" timestamp with time zone default now() not null,
    "plan" text,
    "latest_event_timestamp_ms" bigint,
    constraint "subscriptions_environment_check" CHECK (environment = ANY (ARRAY['sandbox'::text, 'production'::text, NULL::text])),
    constraint "subscriptions_pkey" PRIMARY KEY (user_id),
    constraint "subscriptions_status_check" CHECK (status = ANY (ARRAY['active'::text, 'trialing'::text, 'cancelled'::text, 'expired'::text, 'billing_issue'::text, 'none'::text])),
    constraint "subscriptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);$ddl$;
    execute 'alter table public."subscriptions" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscriptions" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscriptions" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscriptions" to "service_role"';
  end if;
end;
$baseline_table_031$;

do $baseline_table_032$
begin
  if to_regclass('public.recipe_import_artifact_objects') is null then
    execute $ddl$create table public."recipe_import_artifact_objects" (
    "id" uuid default gen_random_uuid() not null,
    "job_id" uuid not null,
    "artifact_kind" text not null,
    "storage_provider" text default 'supabase'::text not null,
    "bucket" text default 'recipe-import-artifacts'::text not null,
    "object_key" text not null,
    "mime_type" text not null,
    "size_bytes" bigint not null,
    "width" integer,
    "height" integer,
    "duration_ms" integer,
    "checksum" text,
    "source_url" text,
    "expires_at" timestamp with time zone not null,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone default now() not null,
    constraint "recipe_import_artifact_objects_bucket_chk" CHECK (bucket = 'recipe-import-artifacts'::text),
    constraint "recipe_import_artifact_objects_duration_ms_check" CHECK (duration_ms IS NULL OR duration_ms >= 0),
    constraint "recipe_import_artifact_objects_height_check" CHECK (height IS NULL OR height > 0),
    constraint "recipe_import_artifact_objects_key_unique" UNIQUE (bucket, object_key),
    constraint "recipe_import_artifact_objects_pkey" PRIMARY KEY (id),
    constraint "recipe_import_artifact_objects_size_bytes_check" CHECK (size_bytes > 0),
    constraint "recipe_import_artifact_objects_width_check" CHECK (width IS NULL OR width > 0)
);$ddl$;
    execute 'alter table public."recipe_import_artifact_objects" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."recipe_import_artifact_objects" to "service_role"';
  end if;
end;
$baseline_table_032$;

do $baseline_table_033$
begin
  if to_regclass('public.operational_job_type_registry') is null then
    execute $ddl$create table public."operational_job_type_registry" (
    "job_type" text not null,
    "description" text not null,
    "created_at" timestamp with time zone default now() not null,
    constraint "operational_job_type_registry_pkey" PRIMARY KEY (job_type)
);$ddl$;
    execute 'alter table public."operational_job_type_registry" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."operational_job_type_registry" to "service_role"';
  end if;
end;
$baseline_table_033$;

do $baseline_table_034$
begin
  if to_regclass('public.tags') is null then
    execute $ddl$create table public."tags" (
    "id" text not null,
    "name" text not null,
    "sort_order" integer default 0 not null,
    constraint "tags_pkey" PRIMARY KEY (id)
);$ddl$;
    execute 'alter table public."tags" enable row level security';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."tags" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."tags" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."tags" to "service_role"';
  end if;
end;
$baseline_table_034$;

-- Existing baseline indexes; security-performance indexes are added by the later hardening migration.
CREATE INDEX IF NOT EXISTS admin_audit_logs_action_idx ON public.admin_audit_logs USING btree (action);
CREATE INDEX IF NOT EXISTS admin_audit_logs_actor_admin_id_idx ON public.admin_audit_logs USING btree (actor_admin_id);
CREATE INDEX IF NOT EXISTS admin_audit_logs_correlation_id_idx ON public.admin_audit_logs USING btree (correlation_id) WHERE (correlation_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS admin_audit_logs_created_at_idx ON public.admin_audit_logs USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS admin_audit_logs_job_id_idx ON public.admin_audit_logs USING btree (job_id) WHERE (job_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS admin_audit_logs_object_idx ON public.admin_audit_logs USING btree (object_type, object_id);
CREATE INDEX IF NOT EXISTS admin_audit_logs_request_id_idx ON public.admin_audit_logs USING btree (request_id) WHERE (request_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS admin_sessions_admin_id_idx ON public.admin_sessions USING btree (admin_id);
CREATE INDEX IF NOT EXISTS admin_sessions_expires_at_idx ON public.admin_sessions USING btree (expires_at);
CREATE INDEX IF NOT EXISTS ai_models_enabled_idx ON public.ai_models USING btree (enabled);
CREATE INDEX IF NOT EXISTS ai_models_provider_id_idx ON public.ai_models USING btree (provider_id);
CREATE INDEX IF NOT EXISTS ai_providers_enabled_idx ON public.ai_providers USING btree (enabled);
CREATE INDEX IF NOT EXISTS ai_providers_secret_ref_idx ON public.ai_providers USING btree (secret_ref);
CREATE INDEX IF NOT EXISTS ai_routes_enabled_idx ON public.ai_routes USING btree (enabled);
CREATE INDEX IF NOT EXISTS ai_usage_events_created_at_idx ON public.ai_usage_events USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_events_provider_id_idx ON public.ai_usage_events USING btree (provider_id);
CREATE INDEX IF NOT EXISTS ai_usage_events_request_id_idx ON public.ai_usage_events USING btree (request_id);
CREATE INDEX IF NOT EXISTS ai_usage_events_route_key_idx ON public.ai_usage_events USING btree (route_key);
CREATE INDEX IF NOT EXISTS app_download_stats_platform_idx ON public.app_download_stats USING btree (platform);
CREATE INDEX IF NOT EXISTS app_download_stats_year_month_idx ON public.app_download_stats USING btree (year_month DESC);
CREATE INDEX IF NOT EXISTS collection_recipes_recipe_id_idx ON public.collection_recipes USING btree (recipe_id);
CREATE INDEX IF NOT EXISTS collections_user_id_idx ON public.collections USING btree (user_id);
CREATE INDEX IF NOT EXISTS financial_report_rows_fiscal_idx ON public.financial_report_rows USING btree (fiscal_period DESC);
CREATE INDEX IF NOT EXISTS financial_report_rows_platform_store_idx ON public.financial_report_rows USING btree (platform, store);
CREATE INDEX IF NOT EXISTS financial_report_rows_sync_run_idx ON public.financial_report_rows USING btree (sync_run_id);
CREATE INDEX IF NOT EXISTS grocery_items_completed_idx ON public.grocery_items USING btree (list_id, completed);
CREATE INDEX IF NOT EXISTS grocery_items_list_id_idx ON public.grocery_items USING btree (list_id);
CREATE INDEX IF NOT EXISTS grocery_lists_user_id_idx ON public.grocery_lists USING btree (user_id);
CREATE INDEX IF NOT EXISTS ingredients_category_idx ON public.ingredients USING btree (category);
CREATE INDEX IF NOT EXISTS ingredients_name_idx ON public.ingredients USING btree (lower(name));
CREATE INDEX IF NOT EXISTS ingredients_user_id_idx ON public.ingredients USING btree (user_id);
CREATE INDEX IF NOT EXISTS meal_plans_recipe_id_idx ON public.meal_plans USING btree (recipe_id);
CREATE INDEX IF NOT EXISTS meal_plans_user_date_idx ON public.meal_plans USING btree (user_id, plan_date);
CREATE INDEX IF NOT EXISTS pantry_items_expiration_idx ON public.pantry_items USING btree (user_id, expiration_date);
CREATE INDEX IF NOT EXISTS pantry_items_user_id_idx ON public.pantry_items USING btree (user_id);
CREATE INDEX IF NOT EXISTS payment_transactions_event_type_idx ON public.payment_transactions USING btree (event_type);
CREATE INDEX IF NOT EXISTS payment_transactions_order_id_idx ON public.payment_transactions USING btree (order_id) WHERE (order_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS payment_transactions_purchase_at_idx ON public.payment_transactions USING btree (purchase_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS payment_transactions_status_idx ON public.payment_transactions USING btree (status);
CREATE INDEX IF NOT EXISTS payment_transactions_store_idx ON public.payment_transactions USING btree (store);
CREATE INDEX IF NOT EXISTS payment_transactions_transaction_id_idx ON public.payment_transactions USING btree (transaction_id) WHERE (transaction_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS payment_transactions_user_id_idx ON public.payment_transactions USING btree (user_id);
CREATE INDEX IF NOT EXISTS profiles_account_status_idx ON public.profiles USING btree (account_status);
CREATE INDEX IF NOT EXISTS profiles_device_type_idx ON public.profiles USING btree (device_type);
CREATE INDEX IF NOT EXISTS profiles_registration_provider_idx ON public.profiles USING btree (registration_provider);
CREATE INDEX IF NOT EXISTS purchase_events_created_at_idx ON public.purchase_events USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS purchase_events_user_id_idx ON public.purchase_events USING btree (user_id);
CREATE INDEX IF NOT EXISTS recipe_import_artifact_objects_expires_idx ON public.recipe_import_artifact_objects USING btree (expires_at) WHERE (deleted_at IS NULL);
CREATE INDEX IF NOT EXISTS recipe_import_artifact_objects_job_idx ON public.recipe_import_artifact_objects USING btree (job_id) WHERE (deleted_at IS NULL);
CREATE INDEX IF NOT EXISTS recipes_category_idx ON public.recipes USING btree (category);
CREATE INDEX IF NOT EXISTS recipes_created_at_idx ON public.recipes USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS recipes_cuisine_idx ON public.recipes USING btree (cuisine);
CREATE INDEX IF NOT EXISTS recipes_tags_gin_idx ON public.recipes USING gin (tags);
CREATE INDEX IF NOT EXISTS recipes_title_trgm_idx ON public.recipes USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS recipes_user_id_idx ON public.recipes USING btree (user_id);
CREATE INDEX IF NOT EXISTS store_analytics_daily_date_idx ON public.store_analytics_daily USING btree (metric_date DESC);
CREATE INDEX IF NOT EXISTS store_analytics_daily_metric_key_idx ON public.store_analytics_daily USING btree (metric_key);
CREATE INDEX IF NOT EXISTS store_analytics_daily_platform_store_idx ON public.store_analytics_daily USING btree (platform, store);
CREATE INDEX IF NOT EXISTS store_analytics_daily_sync_run_idx ON public.store_analytics_daily USING btree (sync_run_id);
CREATE INDEX IF NOT EXISTS store_integrations_status_idx ON public.store_integrations USING btree (status);
CREATE INDEX IF NOT EXISTS store_sync_runs_job_type_started_idx ON public.store_sync_runs USING btree (job_type, started_at DESC);
CREATE INDEX IF NOT EXISTS store_sync_runs_provider_started_idx ON public.store_sync_runs USING btree (provider, started_at DESC);
CREATE INDEX IF NOT EXISTS store_sync_runs_status_idx ON public.store_sync_runs USING btree (status);
CREATE INDEX IF NOT EXISTS subscription_plans_plan_key_idx ON public.subscription_plans USING btree (plan_key);
CREATE INDEX IF NOT EXISTS subscription_plans_platform_idx ON public.subscription_plans USING btree (platform);

do $baseline_view_subscription_status$
begin
  if to_regclass('public.subscription_status') is null then
    execute $ddl$create view public."subscription_status" with (security_invoker = true) as
 SELECT user_id,
    COALESCE(plan, entitlement_id, product_id) AS plan,
    status,
    expires_at AS expire_date,
    updated_at
   FROM subscriptions;;$ddl$;
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscription_status" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscription_status" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."subscription_status" to "service_role"';
  end if;
end;
$baseline_view_subscription_status$;

do $baseline_view_user_commerce_summary$
begin
  if to_regclass('public.user_commerce_summary') is null then
    execute $ddl$create view public."user_commerce_summary" with (security_invoker = true) as
 SELECT p.id AS user_id,
    s.plan AS subscription_plan,
    s.status AS subscription_status,
    s.expires_at AS subscription_expires_at,
    s.product_id AS subscription_product_id,
    s.entitlement_id,
    s.store AS subscription_store,
    agg.first_purchase_at,
    agg.last_purchase_at,
    COALESCE(agg.purchase_count, 0::bigint)::integer AS purchase_count,
    COALESCE(agg.refund_count, 0::bigint)::integer AS refund_count,
    COALESCE(agg.gross_spend, 0::numeric)::numeric(14,4) AS gross_spend,
    COALESCE(agg.refunded_amount, 0::numeric)::numeric(14,4) AS refunded_amount,
    (COALESCE(agg.gross_spend, 0::numeric) - COALESCE(agg.refunded_amount, 0::numeric))::numeric(14,4) AS net_spend,
    COALESCE(agg.estimated_gross_usd, 0::numeric)::numeric(14,4) AS estimated_ltv_usd,
    agg.primary_currency,
    agg.store_territory,
    now() AS computed_at
   FROM profiles p
     LEFT JOIN subscriptions s ON s.user_id = p.id
     LEFT JOIN LATERAL ( SELECT min(pt.purchase_at) FILTER (WHERE upper(pt.event_type) = ANY (ARRAY['INITIAL_PURCHASE'::text, 'RENEWAL'::text, 'NON_RENEWING_PURCHASE'::text, 'PRODUCT_CHANGE'::text, 'UNCANCELLATION'::text])) AS first_purchase_at,
            max(pt.purchase_at) AS last_purchase_at,
            count(*) FILTER (WHERE upper(pt.event_type) = ANY (ARRAY['INITIAL_PURCHASE'::text, 'RENEWAL'::text, 'NON_RENEWING_PURCHASE'::text, 'PRODUCT_CHANGE'::text])) AS purchase_count,
            count(*) FILTER (WHERE pt.refund_at IS NOT NULL OR pt.status = 'refunded'::text) AS refund_count,
            sum(pt.gross_amount) FILTER (WHERE (upper(pt.event_type) = ANY (ARRAY['INITIAL_PURCHASE'::text, 'RENEWAL'::text, 'NON_RENEWING_PURCHASE'::text, 'PRODUCT_CHANGE'::text])) AND pt.gross_amount IS NOT NULL) AS gross_spend,
            sum(pt.refund_amount) FILTER (WHERE pt.refund_amount IS NOT NULL) AS refunded_amount,
            sum(pt.estimated_gross_usd) FILTER (WHERE (upper(pt.event_type) = ANY (ARRAY['INITIAL_PURCHASE'::text, 'RENEWAL'::text, 'NON_RENEWING_PURCHASE'::text, 'PRODUCT_CHANGE'::text])) AND pt.estimated_gross_usd IS NOT NULL) AS estimated_gross_usd,
            (array_agg(pt.currency ORDER BY pt.purchase_at DESC NULLS LAST) FILTER (WHERE pt.currency IS NOT NULL))[1] AS primary_currency,
            (array_agg(pt.territory ORDER BY pt.purchase_at DESC NULLS LAST) FILTER (WHERE pt.territory IS NOT NULL))[1] AS store_territory
           FROM payment_transactions pt
          WHERE pt.user_id = p.id) agg ON true;;$ddl$;
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_commerce_summary" to "anon"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_commerce_summary" to "authenticated"';
    execute 'grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_commerce_summary" to "service_role"';
  end if;
end;
$baseline_view_user_commerce_summary$;

-- Public API and trigger helpers absent from the tracked migrations.
do $baseline_fn_001$
begin
  if to_regprocedure('public.admin_change_password(uuid,text,text)') is null then
    execute $baseline_fn_ddl_001$CREATE OR REPLACE FUNCTION public.admin_change_password(p_admin_id uuid, p_current_password text, p_new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  ok boolean;
begin
  if not public.admin_password_is_strong(p_new_password) then
    raise exception 'new password does not meet strength policy' using errcode = '22023';
  end if;

  select exists (
    select 1
    from public.admin_accounts a
    where a.id = p_admin_id
      and a.password_hash = crypt(p_current_password, a.password_hash)
  ) into ok;

  if not ok then
    return false;
  end if;

  update public.admin_accounts
  set
    password_hash = crypt(p_new_password, gen_salt('bf')),
    is_default_seed = false,
    must_change_password = false,
    updated_at = now()
  where id = p_admin_id;

  update public.admin_sessions
  set revoked_at = now()
  where admin_id = p_admin_id
    and revoked_at is null
    and expires_at > now();

  return true;
end;
$function$
;$baseline_fn_ddl_001$;
    execute 'revoke all on function public.admin_change_password(uuid,text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.admin_change_password(uuid,text,text) to "service_role"';
  end if;
end;
$baseline_fn_001$;

do $baseline_fn_002$
begin
  if to_regprocedure('public.admin_password_is_strong(text)') is null then
    execute $baseline_fn_ddl_002$CREATE OR REPLACE FUNCTION public.admin_password_is_strong(p_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
begin
  if p_password is null or char_length(p_password) < 12 then
    return false;
  end if;
  if p_password !~ '[A-Z]' then
    return false;
  end if;
  if p_password !~ '[a-z]' then
    return false;
  end if;
  if p_password !~ '[0-9]' then
    return false;
  end if;
  if lower(p_password) in ('admin', 'password', 'password123', 'cookappadmin') then
    return false;
  end if;
  return true;
end;
$function$
;$baseline_fn_ddl_002$;
    execute 'revoke all on function public.admin_password_is_strong(text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.admin_password_is_strong(text) to "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_002$;

do $baseline_fn_003$
begin
  if to_regprocedure('public.admin_verify_credentials(text,text)') is null then
    execute $baseline_fn_ddl_003$CREATE OR REPLACE FUNCTION public.admin_verify_credentials(p_username text, p_password text)
 RETURNS TABLE(id uuid, username text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  return query
  select a.id, a.username
  from public.admin_accounts a
  where a.username = lower(trim(p_username))
    and a.password_hash = crypt(p_password, a.password_hash);
end;
$function$
;$baseline_fn_ddl_003$;
    execute 'revoke all on function public.admin_verify_credentials(text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.admin_verify_credentials(text,text) to "service_role"';
  end if;
end;
$baseline_fn_003$;

do $baseline_fn_004$
begin
  if to_regprocedure('public.capture_registration_meta(text,text)') is null then
    execute $baseline_fn_ddl_004$CREATE OR REPLACE FUNCTION public.capture_registration_meta(p_device_type text DEFAULT NULL::text, p_registration_ip text DEFAULT NULL::text)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_device text;
  v_row public.profiles;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_device := lower(nullif(trim(coalesce(p_device_type, '')), ''));
  if v_device is not null and v_device not in ('ios', 'android', 'web', 'unknown') then
    raise exception 'invalid device_type';
  end if;

  update public.profiles
  set
    device_type = coalesce(device_type, v_device, device_type),
    registration_ip = coalesce(registration_ip, nullif(trim(coalesce(p_registration_ip, '')), '')),
    updated_at = now()
  where id = v_uid
  returning * into v_row;

  if v_row.id is null then
    raise exception 'profile not found';
  end if;

  return v_row;
end;
$function$
;$baseline_fn_ddl_004$;
    execute 'revoke all on function public.capture_registration_meta(text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.capture_registration_meta(text,text) to "authenticated"';
  end if;
end;
$baseline_fn_004$;

do $baseline_fn_005$
begin
  if to_regprocedure('public.collections_set_owner()') is null then
    execute $baseline_fn_ddl_005$CREATE OR REPLACE FUNCTION public.collections_set_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.user_id = auth.uid(); return new; end; $function$
;$baseline_fn_ddl_005$;
    execute 'revoke all on function public.collections_set_owner() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.collections_set_owner() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_005$;

do $baseline_fn_006$
begin
  if to_regprocedure('public.get_runtime_config_number(text,numeric)') is null then
    execute $baseline_fn_ddl_006$CREATE OR REPLACE FUNCTION public.get_runtime_config_number(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb;
begin
  select value into v from public.runtime_config where key = p_key;
  if v is null then
    return p_default;
  end if;
  if jsonb_typeof(v) = 'number' then
    return (v #>> '{}')::numeric;
  end if;
  if jsonb_typeof(v) = 'string' then
    begin
      return trim(both '"' from v::text)::numeric;
    exception when others then
      return p_default;
    end;
  end if;
  return p_default;
end;
$function$
;$baseline_fn_ddl_006$;
    execute 'revoke all on function public.get_runtime_config_number(text,numeric) from PUBLIC, anon, authenticated, service_role';
  end if;
end;
$baseline_fn_006$;

do $baseline_fn_007$
begin
  if to_regprocedure('public.grocery_lists_set_owner()') is null then
    execute $baseline_fn_ddl_007$CREATE OR REPLACE FUNCTION public.grocery_lists_set_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.user_id = auth.uid(); return new; end; $function$
;$baseline_fn_ddl_007$;
    execute 'revoke all on function public.grocery_lists_set_owner() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.grocery_lists_set_owner() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_007$;

do $baseline_fn_008$
begin
  if to_regprocedure('public.handle_new_user()') is null then
    execute $baseline_fn_ddl_008$CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_provider text;
  v_device text;
begin
  v_provider := lower(coalesce(new.raw_app_meta_data ->> 'provider', ''));
  if v_provider not in ('apple', 'google', 'email') then
    v_provider := 'unknown';
  end if;

  v_device := lower(coalesce(new.raw_user_meta_data ->> 'device_type', ''));
  if v_device not in ('ios', 'android', 'web') then
    v_device := 'unknown';
  end if;

  insert into public.profiles (
    id,
    email,
    display_name,
    avatar,
    registration_provider,
    device_type
  )
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    coalesce(
      new.raw_user_meta_data ->> 'avatar_url',
      new.raw_user_meta_data ->> 'picture'
    ),
    v_provider,
    v_device
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    avatar = coalesce(public.profiles.avatar, excluded.avatar),
    registration_provider = coalesce(
      public.profiles.registration_provider,
      excluded.registration_provider
    ),
    device_type = coalesce(public.profiles.device_type, excluded.device_type),
    updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_008$;
    execute 'revoke all on function public.handle_new_user() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.handle_new_user() to "service_role"';
  end if;
end;
$baseline_fn_008$;

do $baseline_fn_009$
begin
  if to_regprocedure('public.handle_user_email_updated()') is null then
    execute $baseline_fn_ddl_009$CREATE OR REPLACE FUNCTION public.handle_user_email_updated()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.email is distinct from old.email then
    update public.profiles
    set email = new.email, updated_at = now()
    where id = new.id;
  end if;
  return new;
end;
$function$
;$baseline_fn_ddl_009$;
    execute 'revoke all on function public.handle_user_email_updated() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.handle_user_email_updated() to "service_role"';
  end if;
end;
$baseline_fn_009$;

do $baseline_fn_011$
begin
  if to_regprocedure('public.map_commerce_store(text)') is null then
    execute $baseline_fn_ddl_011$CREATE OR REPLACE FUNCTION public.map_commerce_store(p_store text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case lower(coalesce(p_store, ''))
    when 'app_store' then 'app_store'
    when 'mac_app_store' then 'app_store'
    when 'play_store' then 'google_play'
    when 'google_play' then 'google_play'
    when 'stripe' then 'stripe'
    when 'promotional' then 'promotional'
    when 'rc_billing' then 'rc_billing'
    when 'unknown' then 'unknown'
    else nullif(lower(coalesce(p_store, '')), '')
  end;
$function$
;$baseline_fn_ddl_011$;
    execute 'revoke all on function public.map_commerce_store(text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.map_commerce_store(text) to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_011$;

do $baseline_fn_010$
begin
  if to_regprocedure('public.map_commerce_platform(text)') is null then
    execute $baseline_fn_ddl_010$CREATE OR REPLACE FUNCTION public.map_commerce_platform(p_store text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case public.map_commerce_store(p_store)
    when 'app_store' then 'ios'
    when 'google_play' then 'android'
    else null
  end;
$function$
;$baseline_fn_ddl_010$;
    execute 'revoke all on function public.map_commerce_platform(text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.map_commerce_platform(text) to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_010$;

do $baseline_fn_012$
begin
  if to_regprocedure('public.meal_plans_set_owner()') is null then
    execute $baseline_fn_ddl_012$CREATE OR REPLACE FUNCTION public.meal_plans_set_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.user_id = auth.uid(); return new; end; $function$
;$baseline_fn_ddl_012$;
    execute 'revoke all on function public.meal_plans_set_owner() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.meal_plans_set_owner() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_012$;

do $baseline_fn_013$
begin
  if to_regprocedure('public.pantry_items_set_owner()') is null then
    execute $baseline_fn_ddl_013$CREATE OR REPLACE FUNCTION public.pantry_items_set_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.user_id = auth.uid(); return new; end; $function$
;$baseline_fn_ddl_013$;
    execute 'revoke all on function public.pantry_items_set_owner() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.pantry_items_set_owner() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_013$;

do $baseline_fn_014$
begin
  if to_regprocedure('public.profiles_protect_email()') is null then
    execute $baseline_fn_ddl_014$CREATE OR REPLACE FUNCTION public.profiles_protect_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'UPDATE'
     and new.email is distinct from old.email
     and coalesce(auth.role(), '') = 'authenticated' then
    new.email := old.email;
  end if;
  return new;
end;
$function$
;$baseline_fn_ddl_014$;
    execute 'revoke all on function public.profiles_protect_email() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.profiles_protect_email() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_014$;

do $baseline_fn_015$
begin
  if to_regprocedure('public.recipe_import_enqueue_many(uuid[],text,text)') is null then
    execute $baseline_fn_ddl_015$CREATE OR REPLACE FUNCTION public.recipe_import_enqueue_many(p_job_ids uuid[], p_from_stage text DEFAULT 'resolve'::text, p_correlation_id text DEFAULT NULL::text)
 RETURNS bigint[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
declare
  v_id uuid;
  v_msg_id bigint;
  v_out bigint[] := array[]::bigint[];
begin
  if p_job_ids is null or cardinality(p_job_ids) = 0 then
    return v_out;
  end if;

  foreach v_id in array p_job_ids
  loop
    v_msg_id := public.recipe_import_enqueue(v_id, p_from_stage, p_correlation_id);
    if v_msg_id is not null then
      v_out := array_append(v_out, v_msg_id);
    end if;
  end loop;

  return v_out;
end;
$function$
;$baseline_fn_ddl_015$;
    execute 'revoke all on function public.recipe_import_enqueue_many(uuid[],text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_enqueue_many(uuid[],text,text) to "service_role"';
  end if;
end;
$baseline_fn_015$;

do $baseline_fn_016$
begin
  if to_regprocedure('public.recipe_import_enqueue(uuid,text,text)') is null then
    execute $baseline_fn_ddl_016$CREATE OR REPLACE FUNCTION public.recipe_import_enqueue(p_job_id uuid, p_from_stage text DEFAULT 'resolve'::text, p_correlation_id text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
declare
  v_status text;
  v_msg_id bigint;
begin
  if p_job_id is null then
    raise exception 'job_id required';
  end if;

  if p_from_stage is null
     or p_from_stage not in (
       'resolve', 'extract', 'normalize', 'parse', 'validate',
       'quality', 'duplicate', 'import', 'done'
     )
  then
    raise exception 'invalid from_stage: %', p_from_stage;
  end if;

  select status into v_status
  from public.recipe_import_jobs
  where id = p_job_id
  for update;

  if v_status is null then
    raise exception 'import job not found: %', p_job_id;
  end if;

  if v_status in ('imported', 'rejected', 'duplicate') then
    return null;
  end if;

  if v_status = 'running' then
    return null;
  end if;

  update public.recipe_import_jobs
  set
    status = 'pending',
    error_code = null,
    error_message = null,
    completed_at = null,
    stage = case
      when p_from_stage = 'done' then stage
      else p_from_stage
    end
  where id = p_job_id;

  select s.send into v_msg_id
  from pgmq.send(
    'recipe_import',
    jsonb_build_object(
      'job_id', p_job_id,
      'from_stage', p_from_stage,
      'correlation_id', p_correlation_id
    )
  ) as s(send);

  return v_msg_id;
end;
$function$
;$baseline_fn_ddl_016$;
    execute 'revoke all on function public.recipe_import_enqueue(uuid,text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_enqueue(uuid,text,text) to "service_role"';
  end if;
end;
$baseline_fn_016$;

do $baseline_fn_017$
begin
  if to_regprocedure('public.recipe_import_queue_archive(bigint)') is null then
    execute $baseline_fn_ddl_017$CREATE OR REPLACE FUNCTION public.recipe_import_queue_archive(p_msg_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
begin
  return pgmq.archive('recipe_import', p_msg_id);
end;
$function$
;$baseline_fn_ddl_017$;
    execute 'revoke all on function public.recipe_import_queue_archive(bigint) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_queue_archive(bigint) to "service_role"';
  end if;
end;
$baseline_fn_017$;

do $baseline_fn_018$
begin
  if to_regprocedure('public.recipe_import_queue_delete(bigint)') is null then
    execute $baseline_fn_ddl_018$CREATE OR REPLACE FUNCTION public.recipe_import_queue_delete(p_msg_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
begin
  return pgmq.delete('recipe_import', p_msg_id);
end;
$function$
;$baseline_fn_ddl_018$;
    execute 'revoke all on function public.recipe_import_queue_delete(bigint) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_queue_delete(bigint) to "service_role"';
  end if;
end;
$baseline_fn_018$;

do $baseline_fn_019$
begin
  if to_regprocedure('public.recipe_import_queue_read(integer,integer)') is null then
    execute $baseline_fn_ddl_019$CREATE OR REPLACE FUNCTION public.recipe_import_queue_read(p_vt integer, p_qty integer)
 RETURNS TABLE(msg_id bigint, read_ct bigint, enqueued_at timestamp with time zone, vt timestamp with time zone, message jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
begin
  if p_vt is null or p_vt < 1 then
    raise exception 'vt must be >= 1';
  end if;
  if p_qty is null or p_qty < 1 then
    raise exception 'qty must be >= 1';
  end if;

  return query
  select r.msg_id, r.read_ct, r.enqueued_at, r.vt, r.message
  from pgmq.read('recipe_import', p_vt, p_qty) as r;
end;
$function$
;$baseline_fn_ddl_019$;
    execute 'revoke all on function public.recipe_import_queue_read(integer,integer) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_queue_read(integer,integer) to "service_role"';
  end if;
end;
$baseline_fn_019$;

do $baseline_fn_020$
begin
  if to_regprocedure('public.recipe_import_requeue_stale_pending(integer,integer,text)') is null then
    execute $baseline_fn_ddl_020$CREATE OR REPLACE FUNCTION public.recipe_import_requeue_stale_pending(p_limit integer DEFAULT 50, p_older_than_seconds integer DEFAULT 60, p_correlation_id text DEFAULT NULL::text)
 RETURNS bigint[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pgmq'
AS $function$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), array[]::uuid[])
  into v_ids
  from (
    select j.id
    from public.recipe_import_jobs j
    where j.status = 'pending'
      and j.updated_at < now() - make_interval(secs => greatest(p_older_than_seconds, 0))
    order by j.created_at asc
    limit greatest(coalesce(p_limit, 50), 1)
  ) s;

  return public.recipe_import_enqueue_many(v_ids, 'resolve', p_correlation_id);
end;
$function$
;$baseline_fn_ddl_020$;
    execute 'revoke all on function public.recipe_import_requeue_stale_pending(integer,integer,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipe_import_requeue_stale_pending(integer,integer,text) to "service_role"';
  end if;
end;
$baseline_fn_020$;

do $baseline_fn_021$
begin
  if to_regprocedure('public.recipes_set_owner()') is null then
    execute $baseline_fn_ddl_021$CREATE OR REPLACE FUNCTION public.recipes_set_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.user_id = auth.uid(); return new; end; $function$
;$baseline_fn_ddl_021$;
    execute 'revoke all on function public.recipes_set_owner() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.recipes_set_owner() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_021$;

do $baseline_fn_022$
begin
  if to_regprocedure('public.storage_object_belongs_to_user(text)') is null then
    execute $baseline_fn_ddl_022$CREATE OR REPLACE FUNCTION public.storage_object_belongs_to_user(object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select split_part(object_name, '/', 1) = auth.uid()::text;
$function$
;$baseline_fn_ddl_022$;
    execute 'revoke all on function public.storage_object_belongs_to_user(text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.storage_object_belongs_to_user(text) to "authenticated", "service_role"';
  end if;
end;
$baseline_fn_022$;

do $baseline_fn_023$
begin
  if to_regprocedure('public.touch_app_download_stats_updated_at()') is null then
    execute $baseline_fn_ddl_023$CREATE OR REPLACE FUNCTION public.touch_app_download_stats_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_023$;
    execute 'revoke all on function public.touch_app_download_stats_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_app_download_stats_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_023$;

do $baseline_fn_024$
begin
  if to_regprocedure('public.touch_collections_updated_at()') is null then
    execute $baseline_fn_ddl_024$CREATE OR REPLACE FUNCTION public.touch_collections_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_024$;
    execute 'revoke all on function public.touch_collections_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_collections_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_024$;

do $baseline_fn_025$
begin
  if to_regprocedure('public.touch_financial_report_rows_updated_at()') is null then
    execute $baseline_fn_ddl_025$CREATE OR REPLACE FUNCTION public.touch_financial_report_rows_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_025$;
    execute 'revoke all on function public.touch_financial_report_rows_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_financial_report_rows_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_025$;

do $baseline_fn_026$
begin
  if to_regprocedure('public.touch_grocery_items_updated_at()') is null then
    execute $baseline_fn_ddl_026$CREATE OR REPLACE FUNCTION public.touch_grocery_items_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_026$;
    execute 'revoke all on function public.touch_grocery_items_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_grocery_items_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_026$;

do $baseline_fn_027$
begin
  if to_regprocedure('public.touch_grocery_lists_updated_at()') is null then
    execute $baseline_fn_ddl_027$CREATE OR REPLACE FUNCTION public.touch_grocery_lists_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_027$;
    execute 'revoke all on function public.touch_grocery_lists_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_grocery_lists_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_027$;

do $baseline_fn_028$
begin
  if to_regprocedure('public.touch_ingredients_updated_at()') is null then
    execute $baseline_fn_ddl_028$CREATE OR REPLACE FUNCTION public.touch_ingredients_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_028$;
    execute 'revoke all on function public.touch_ingredients_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_ingredients_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_028$;

do $baseline_fn_029$
begin
  if to_regprocedure('public.touch_meal_plans_updated_at()') is null then
    execute $baseline_fn_ddl_029$CREATE OR REPLACE FUNCTION public.touch_meal_plans_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_029$;
    execute 'revoke all on function public.touch_meal_plans_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_meal_plans_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_029$;

do $baseline_fn_030$
begin
  if to_regprocedure('public.touch_pantry_items_updated_at()') is null then
    execute $baseline_fn_ddl_030$CREATE OR REPLACE FUNCTION public.touch_pantry_items_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_030$;
    execute 'revoke all on function public.touch_pantry_items_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_pantry_items_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_030$;

do $baseline_fn_031$
begin
  if to_regprocedure('public.touch_payment_transactions_updated_at()') is null then
    execute $baseline_fn_ddl_031$CREATE OR REPLACE FUNCTION public.touch_payment_transactions_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_031$;
    execute 'revoke all on function public.touch_payment_transactions_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_payment_transactions_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_031$;

do $baseline_fn_032$
begin
  if to_regprocedure('public.touch_profiles_updated_at()') is null then
    execute $baseline_fn_ddl_032$CREATE OR REPLACE FUNCTION public.touch_profiles_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_032$;
    execute 'revoke all on function public.touch_profiles_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_profiles_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_032$;

do $baseline_fn_033$
begin
  if to_regprocedure('public.touch_recipes_updated_at()') is null then
    execute $baseline_fn_ddl_033$CREATE OR REPLACE FUNCTION public.touch_recipes_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_033$;
    execute 'revoke all on function public.touch_recipes_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_recipes_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_033$;

do $baseline_fn_034$
begin
  if to_regprocedure('public.touch_runtime_config_updated_at()') is null then
    execute $baseline_fn_ddl_034$CREATE OR REPLACE FUNCTION public.touch_runtime_config_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_034$;
    execute 'revoke all on function public.touch_runtime_config_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_runtime_config_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_034$;

do $baseline_fn_035$
begin
  if to_regprocedure('public.touch_store_analytics_daily_updated_at()') is null then
    execute $baseline_fn_ddl_035$CREATE OR REPLACE FUNCTION public.touch_store_analytics_daily_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_035$;
    execute 'revoke all on function public.touch_store_analytics_daily_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_store_analytics_daily_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_035$;

do $baseline_fn_036$
begin
  if to_regprocedure('public.touch_subscription_plans_updated_at()') is null then
    execute $baseline_fn_ddl_036$CREATE OR REPLACE FUNCTION public.touch_subscription_plans_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;$baseline_fn_ddl_036$;
    execute 'revoke all on function public.touch_subscription_plans_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_subscription_plans_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_036$;

do $baseline_fn_037$
begin
  if to_regprocedure('public.touch_subscription_updated_at()') is null then
    execute $baseline_fn_ddl_037$CREATE OR REPLACE FUNCTION public.touch_subscription_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end; $function$
;$baseline_fn_ddl_037$;
    execute 'revoke all on function public.touch_subscription_updated_at() from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.touch_subscription_updated_at() to PUBLIC, "anon", "authenticated", "service_role"';
  end if;
end;
$baseline_fn_037$;

do $baseline_fn_038$
begin
  if to_regprocedure('public.user_owns_collection(uuid)') is null then
    execute $baseline_fn_ddl_038$CREATE OR REPLACE FUNCTION public.user_owns_collection(p_collection_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.collections c
    where c.id = p_collection_id and c.user_id = auth.uid()
  );
$function$
;$baseline_fn_ddl_038$;
    execute 'revoke all on function public.user_owns_collection(uuid) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.user_owns_collection(uuid) to "authenticated", "service_role"';
  end if;
end;
$baseline_fn_038$;

do $baseline_fn_039$
begin
  if to_regprocedure('public.user_owns_grocery_list(uuid)') is null then
    execute $baseline_fn_ddl_039$CREATE OR REPLACE FUNCTION public.user_owns_grocery_list(p_list_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.grocery_lists g
    where g.id = p_list_id and g.user_id = auth.uid()
  );
$function$
;$baseline_fn_ddl_039$;
    execute 'revoke all on function public.user_owns_grocery_list(uuid) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.user_owns_grocery_list(uuid) to "authenticated", "service_role"';
  end if;
end;
$baseline_fn_039$;

do $baseline_fn_040$
begin
  if to_regprocedure('public.user_owns_recipe(uuid)') is null then
    execute $baseline_fn_ddl_040$CREATE OR REPLACE FUNCTION public.user_owns_recipe(p_recipe_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.recipes r
    where r.id = p_recipe_id and r.user_id = auth.uid()
  );
$function$
;$baseline_fn_ddl_040$;
    execute 'revoke all on function public.user_owns_recipe(uuid) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.user_owns_recipe(uuid) to "authenticated", "service_role"';
  end if;
end;
$baseline_fn_040$;

do $baseline_fn_041$
begin
  if to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is null then
    execute $baseline_fn_ddl_041$CREATE OR REPLACE FUNCTION public.admin_bootstrap_owner(p_username text, p_new_password text, p_current_password text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, username text, role text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
;$baseline_fn_ddl_041$;
    execute 'revoke all on function public.admin_bootstrap_owner(text,text,text) from PUBLIC, anon, authenticated, service_role';
    execute 'grant execute on function public.admin_bootstrap_owner(text,text,text) to "service_role"';
  end if;
end;
$baseline_fn_041$;

-- Restore existing owner-scoped policies only when they are absent.
do $baseline_policy_001$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collection_recipes' and policyname = 'collection_recipes_delete_own'
  ) then
    execute $baseline_policy_ddl_001$create policy "collection_recipes_delete_own" on public."collection_recipes" as permissive for delete to "authenticated" using (user_owns_collection(collection_id));$baseline_policy_ddl_001$;
  end if;
end;
$baseline_policy_001$;

do $baseline_policy_002$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collection_recipes' and policyname = 'collection_recipes_insert_own'
  ) then
    execute $baseline_policy_ddl_002$create policy "collection_recipes_insert_own" on public."collection_recipes" as permissive for insert to "authenticated" with check ((user_owns_collection(collection_id) AND user_owns_recipe(recipe_id)));$baseline_policy_ddl_002$;
  end if;
end;
$baseline_policy_002$;

do $baseline_policy_003$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collection_recipes' and policyname = 'collection_recipes_select_own'
  ) then
    execute $baseline_policy_ddl_003$create policy "collection_recipes_select_own" on public."collection_recipes" as permissive for select to "authenticated" using (user_owns_collection(collection_id));$baseline_policy_ddl_003$;
  end if;
end;
$baseline_policy_003$;

do $baseline_policy_004$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collections' and policyname = 'collections_delete_own'
  ) then
    execute $baseline_policy_ddl_004$create policy "collections_delete_own" on public."collections" as permissive for delete to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_004$;
  end if;
end;
$baseline_policy_004$;

do $baseline_policy_005$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collections' and policyname = 'collections_insert_own'
  ) then
    execute $baseline_policy_ddl_005$create policy "collections_insert_own" on public."collections" as permissive for insert to "authenticated" with check ((auth.uid() = user_id));$baseline_policy_ddl_005$;
  end if;
end;
$baseline_policy_005$;

do $baseline_policy_006$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collections' and policyname = 'collections_select_own'
  ) then
    execute $baseline_policy_ddl_006$create policy "collections_select_own" on public."collections" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_006$;
  end if;
end;
$baseline_policy_006$;

do $baseline_policy_007$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'collections' and policyname = 'collections_update_own'
  ) then
    execute $baseline_policy_ddl_007$create policy "collections_update_own" on public."collections" as permissive for update to "authenticated" using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));$baseline_policy_ddl_007$;
  end if;
end;
$baseline_policy_007$;

do $baseline_policy_008$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'cuisines' and policyname = 'cuisines_select_authenticated'
  ) then
    execute $baseline_policy_ddl_008$create policy "cuisines_select_authenticated" on public."cuisines" as permissive for select to "authenticated" using (true);$baseline_policy_ddl_008$;
  end if;
end;
$baseline_policy_008$;

do $baseline_policy_009$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_items' and policyname = 'grocery_items_delete_own'
  ) then
    execute $baseline_policy_ddl_009$create policy "grocery_items_delete_own" on public."grocery_items" as permissive for delete to "authenticated" using (user_owns_grocery_list(list_id));$baseline_policy_ddl_009$;
  end if;
end;
$baseline_policy_009$;

do $baseline_policy_010$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_items' and policyname = 'grocery_items_insert_own'
  ) then
    execute $baseline_policy_ddl_010$create policy "grocery_items_insert_own" on public."grocery_items" as permissive for insert to "authenticated" with check (user_owns_grocery_list(list_id));$baseline_policy_ddl_010$;
  end if;
end;
$baseline_policy_010$;

do $baseline_policy_011$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_items' and policyname = 'grocery_items_select_own'
  ) then
    execute $baseline_policy_ddl_011$create policy "grocery_items_select_own" on public."grocery_items" as permissive for select to "authenticated" using (user_owns_grocery_list(list_id));$baseline_policy_ddl_011$;
  end if;
end;
$baseline_policy_011$;

do $baseline_policy_012$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_items' and policyname = 'grocery_items_update_own'
  ) then
    execute $baseline_policy_ddl_012$create policy "grocery_items_update_own" on public."grocery_items" as permissive for update to "authenticated" using (user_owns_grocery_list(list_id)) with check (user_owns_grocery_list(list_id));$baseline_policy_ddl_012$;
  end if;
end;
$baseline_policy_012$;

do $baseline_policy_013$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_lists' and policyname = 'grocery_lists_delete_own'
  ) then
    execute $baseline_policy_ddl_013$create policy "grocery_lists_delete_own" on public."grocery_lists" as permissive for delete to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_013$;
  end if;
end;
$baseline_policy_013$;

do $baseline_policy_014$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_lists' and policyname = 'grocery_lists_insert_own'
  ) then
    execute $baseline_policy_ddl_014$create policy "grocery_lists_insert_own" on public."grocery_lists" as permissive for insert to "authenticated" with check ((auth.uid() = user_id));$baseline_policy_ddl_014$;
  end if;
end;
$baseline_policy_014$;

do $baseline_policy_015$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_lists' and policyname = 'grocery_lists_select_own'
  ) then
    execute $baseline_policy_ddl_015$create policy "grocery_lists_select_own" on public."grocery_lists" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_015$;
  end if;
end;
$baseline_policy_015$;

do $baseline_policy_016$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'grocery_lists' and policyname = 'grocery_lists_update_own'
  ) then
    execute $baseline_policy_ddl_016$create policy "grocery_lists_update_own" on public."grocery_lists" as permissive for update to "authenticated" using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));$baseline_policy_ddl_016$;
  end if;
end;
$baseline_policy_016$;

do $baseline_policy_017$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredients' and policyname = 'ingredients_delete_own'
  ) then
    execute $baseline_policy_ddl_017$create policy "ingredients_delete_own" on public."ingredients" as permissive for delete to "authenticated" using (((user_id = auth.uid()) AND (is_system = false)));$baseline_policy_ddl_017$;
  end if;
end;
$baseline_policy_017$;

do $baseline_policy_018$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredients' and policyname = 'ingredients_insert_own'
  ) then
    execute $baseline_policy_ddl_018$create policy "ingredients_insert_own" on public."ingredients" as permissive for insert to "authenticated" with check (((user_id = auth.uid()) AND (is_system = false)));$baseline_policy_ddl_018$;
  end if;
end;
$baseline_policy_018$;

do $baseline_policy_019$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredients' and policyname = 'ingredients_select_visible'
  ) then
    execute $baseline_policy_ddl_019$create policy "ingredients_select_visible" on public."ingredients" as permissive for select to "authenticated" using (((is_system = true) OR (user_id = auth.uid())));$baseline_policy_ddl_019$;
  end if;
end;
$baseline_policy_019$;

do $baseline_policy_020$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ingredients' and policyname = 'ingredients_update_own'
  ) then
    execute $baseline_policy_ddl_020$create policy "ingredients_update_own" on public."ingredients" as permissive for update to "authenticated" using (((user_id = auth.uid()) AND (is_system = false))) with check (((user_id = auth.uid()) AND (is_system = false)));$baseline_policy_ddl_020$;
  end if;
end;
$baseline_policy_020$;

do $baseline_policy_021$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'meal_categories' and policyname = 'meal_categories_select_authenticated'
  ) then
    execute $baseline_policy_ddl_021$create policy "meal_categories_select_authenticated" on public."meal_categories" as permissive for select to "authenticated" using (true);$baseline_policy_ddl_021$;
  end if;
end;
$baseline_policy_021$;

do $baseline_policy_022$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'meal_plans' and policyname = 'meal_plans_delete_own'
  ) then
    execute $baseline_policy_ddl_022$create policy "meal_plans_delete_own" on public."meal_plans" as permissive for delete to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_022$;
  end if;
end;
$baseline_policy_022$;

do $baseline_policy_023$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'meal_plans' and policyname = 'meal_plans_insert_own'
  ) then
    execute $baseline_policy_ddl_023$create policy "meal_plans_insert_own" on public."meal_plans" as permissive for insert to "authenticated" with check (((auth.uid() = user_id) AND user_owns_recipe(recipe_id)));$baseline_policy_ddl_023$;
  end if;
end;
$baseline_policy_023$;

do $baseline_policy_024$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'meal_plans' and policyname = 'meal_plans_select_own'
  ) then
    execute $baseline_policy_ddl_024$create policy "meal_plans_select_own" on public."meal_plans" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_024$;
  end if;
end;
$baseline_policy_024$;

do $baseline_policy_025$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'meal_plans' and policyname = 'meal_plans_update_own'
  ) then
    execute $baseline_policy_ddl_025$create policy "meal_plans_update_own" on public."meal_plans" as permissive for update to "authenticated" using ((auth.uid() = user_id)) with check (((auth.uid() = user_id) AND user_owns_recipe(recipe_id)));$baseline_policy_ddl_025$;
  end if;
end;
$baseline_policy_025$;

do $baseline_policy_026$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pantry_items' and policyname = 'pantry_items_delete_own'
  ) then
    execute $baseline_policy_ddl_026$create policy "pantry_items_delete_own" on public."pantry_items" as permissive for delete to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_026$;
  end if;
end;
$baseline_policy_026$;

do $baseline_policy_027$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pantry_items' and policyname = 'pantry_items_insert_own'
  ) then
    execute $baseline_policy_ddl_027$create policy "pantry_items_insert_own" on public."pantry_items" as permissive for insert to "authenticated" with check ((auth.uid() = user_id));$baseline_policy_ddl_027$;
  end if;
end;
$baseline_policy_027$;

do $baseline_policy_028$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pantry_items' and policyname = 'pantry_items_select_own'
  ) then
    execute $baseline_policy_ddl_028$create policy "pantry_items_select_own" on public."pantry_items" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_028$;
  end if;
end;
$baseline_policy_028$;

do $baseline_policy_029$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pantry_items' and policyname = 'pantry_items_update_own'
  ) then
    execute $baseline_policy_ddl_029$create policy "pantry_items_update_own" on public."pantry_items" as permissive for update to "authenticated" using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));$baseline_policy_ddl_029$;
  end if;
end;
$baseline_policy_029$;

do $baseline_policy_030$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'payment_transactions' and policyname = 'payment_transactions_select_own'
  ) then
    execute $baseline_policy_ddl_030$create policy "payment_transactions_select_own" on public."payment_transactions" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_030$;
  end if;
end;
$baseline_policy_030$;

do $baseline_policy_031$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_insert_own'
  ) then
    execute $baseline_policy_ddl_031$create policy "profiles_insert_own" on public."profiles" as permissive for insert to "authenticated" with check ((auth.uid() = id));$baseline_policy_ddl_031$;
  end if;
end;
$baseline_policy_031$;

do $baseline_policy_032$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_select_own'
  ) then
    execute $baseline_policy_ddl_032$create policy "profiles_select_own" on public."profiles" as permissive for select to "authenticated" using ((auth.uid() = id));$baseline_policy_ddl_032$;
  end if;
end;
$baseline_policy_032$;

do $baseline_policy_033$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and policyname = 'profiles_update_own'
  ) then
    execute $baseline_policy_ddl_033$create policy "profiles_update_own" on public."profiles" as permissive for update to "authenticated" using ((auth.uid() = id)) with check ((auth.uid() = id));$baseline_policy_ddl_033$;
  end if;
end;
$baseline_policy_033$;

do $baseline_policy_034$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'purchase_events' and policyname = 'purchase_events_select_own'
  ) then
    execute $baseline_policy_ddl_034$create policy "purchase_events_select_own" on public."purchase_events" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_034$;
  end if;
end;
$baseline_policy_034$;

do $baseline_policy_035$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'recipes' and policyname = 'recipes_delete_own'
  ) then
    execute $baseline_policy_ddl_035$create policy "recipes_delete_own" on public."recipes" as permissive for delete to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_035$;
  end if;
end;
$baseline_policy_035$;

do $baseline_policy_036$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'recipes' and policyname = 'recipes_insert_own'
  ) then
    execute $baseline_policy_ddl_036$create policy "recipes_insert_own" on public."recipes" as permissive for insert to "authenticated" with check ((auth.uid() = user_id));$baseline_policy_ddl_036$;
  end if;
end;
$baseline_policy_036$;

do $baseline_policy_037$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'recipes' and policyname = 'recipes_select_own'
  ) then
    execute $baseline_policy_ddl_037$create policy "recipes_select_own" on public."recipes" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_037$;
  end if;
end;
$baseline_policy_037$;

do $baseline_policy_038$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'recipes' and policyname = 'recipes_update_own'
  ) then
    execute $baseline_policy_ddl_038$create policy "recipes_update_own" on public."recipes" as permissive for update to "authenticated" using ((auth.uid() = user_id)) with check ((auth.uid() = user_id));$baseline_policy_ddl_038$;
  end if;
end;
$baseline_policy_038$;

do $baseline_policy_039$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'subscriptions' and policyname = 'subscriptions_select_own'
  ) then
    execute $baseline_policy_ddl_039$create policy "subscriptions_select_own" on public."subscriptions" as permissive for select to "authenticated" using ((auth.uid() = user_id));$baseline_policy_ddl_039$;
  end if;
end;
$baseline_policy_039$;

do $baseline_policy_040$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'tags' and policyname = 'tags_select_authenticated'
  ) then
    execute $baseline_policy_ddl_040$create policy "tags_select_authenticated" on public."tags" as permissive for select to "authenticated" using (true);$baseline_policy_ddl_040$;
  end if;
end;
$baseline_policy_040$;

-- Restore owner and updated-at triggers on baseline tables when absent.
do $baseline_trigger_001$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.app_download_stats'::regclass and tgname = 'app_download_stats_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_001$CREATE TRIGGER app_download_stats_set_updated_at BEFORE UPDATE ON public."app_download_stats" FOR EACH ROW EXECUTE FUNCTION public."touch_app_download_stats_updated_at"();$baseline_trigger_ddl_001$;
  end if;
end;
$baseline_trigger_001$;

do $baseline_trigger_002$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.collections'::regclass and tgname = 'collections_enforce_owner' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_002$CREATE TRIGGER collections_enforce_owner BEFORE INSERT ON public."collections" FOR EACH ROW EXECUTE FUNCTION public."collections_set_owner"();$baseline_trigger_ddl_002$;
  end if;
end;
$baseline_trigger_002$;

do $baseline_trigger_003$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.collections'::regclass and tgname = 'collections_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_003$CREATE TRIGGER collections_set_updated_at BEFORE UPDATE ON public."collections" FOR EACH ROW EXECUTE FUNCTION public."touch_collections_updated_at"();$baseline_trigger_ddl_003$;
  end if;
end;
$baseline_trigger_003$;

do $baseline_trigger_004$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.financial_report_rows'::regclass and tgname = 'financial_report_rows_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_004$CREATE TRIGGER financial_report_rows_set_updated_at BEFORE UPDATE ON public."financial_report_rows" FOR EACH ROW EXECUTE FUNCTION public."touch_financial_report_rows_updated_at"();$baseline_trigger_ddl_004$;
  end if;
end;
$baseline_trigger_004$;

do $baseline_trigger_005$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.grocery_items'::regclass and tgname = 'grocery_items_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_005$CREATE TRIGGER grocery_items_set_updated_at BEFORE UPDATE ON public."grocery_items" FOR EACH ROW EXECUTE FUNCTION public."touch_grocery_items_updated_at"();$baseline_trigger_ddl_005$;
  end if;
end;
$baseline_trigger_005$;

do $baseline_trigger_006$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.grocery_lists'::regclass and tgname = 'grocery_lists_enforce_owner' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_006$CREATE TRIGGER grocery_lists_enforce_owner BEFORE INSERT ON public."grocery_lists" FOR EACH ROW EXECUTE FUNCTION public."grocery_lists_set_owner"();$baseline_trigger_ddl_006$;
  end if;
end;
$baseline_trigger_006$;

do $baseline_trigger_007$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.grocery_lists'::regclass and tgname = 'grocery_lists_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_007$CREATE TRIGGER grocery_lists_set_updated_at BEFORE UPDATE ON public."grocery_lists" FOR EACH ROW EXECUTE FUNCTION public."touch_grocery_lists_updated_at"();$baseline_trigger_ddl_007$;
  end if;
end;
$baseline_trigger_007$;

do $baseline_trigger_008$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.ingredients'::regclass and tgname = 'ingredients_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_008$CREATE TRIGGER ingredients_set_updated_at BEFORE UPDATE ON public."ingredients" FOR EACH ROW EXECUTE FUNCTION public."touch_ingredients_updated_at"();$baseline_trigger_ddl_008$;
  end if;
end;
$baseline_trigger_008$;

do $baseline_trigger_009$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.meal_plans'::regclass and tgname = 'meal_plans_enforce_owner' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_009$CREATE TRIGGER meal_plans_enforce_owner BEFORE INSERT ON public."meal_plans" FOR EACH ROW EXECUTE FUNCTION public."meal_plans_set_owner"();$baseline_trigger_ddl_009$;
  end if;
end;
$baseline_trigger_009$;

do $baseline_trigger_010$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.meal_plans'::regclass and tgname = 'meal_plans_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_010$CREATE TRIGGER meal_plans_set_updated_at BEFORE UPDATE ON public."meal_plans" FOR EACH ROW EXECUTE FUNCTION public."touch_meal_plans_updated_at"();$baseline_trigger_ddl_010$;
  end if;
end;
$baseline_trigger_010$;

do $baseline_trigger_011$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.pantry_items'::regclass and tgname = 'pantry_items_enforce_owner' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_011$CREATE TRIGGER pantry_items_enforce_owner BEFORE INSERT ON public."pantry_items" FOR EACH ROW EXECUTE FUNCTION public."pantry_items_set_owner"();$baseline_trigger_ddl_011$;
  end if;
end;
$baseline_trigger_011$;

do $baseline_trigger_012$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.pantry_items'::regclass and tgname = 'pantry_items_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_012$CREATE TRIGGER pantry_items_set_updated_at BEFORE UPDATE ON public."pantry_items" FOR EACH ROW EXECUTE FUNCTION public."touch_pantry_items_updated_at"();$baseline_trigger_ddl_012$;
  end if;
end;
$baseline_trigger_012$;

do $baseline_trigger_013$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.payment_transactions'::regclass and tgname = 'payment_transactions_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_013$CREATE TRIGGER payment_transactions_set_updated_at BEFORE UPDATE ON public."payment_transactions" FOR EACH ROW EXECUTE FUNCTION public."touch_payment_transactions_updated_at"();$baseline_trigger_ddl_013$;
  end if;
end;
$baseline_trigger_013$;

do $baseline_trigger_014$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_protect_email' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_014$CREATE TRIGGER profiles_protect_email BEFORE UPDATE ON public."profiles" FOR EACH ROW EXECUTE FUNCTION public."profiles_protect_email"();$baseline_trigger_ddl_014$;
  end if;
end;
$baseline_trigger_014$;

do $baseline_trigger_015$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_015$CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public."profiles" FOR EACH ROW EXECUTE FUNCTION public."touch_profiles_updated_at"();$baseline_trigger_ddl_015$;
  end if;
end;
$baseline_trigger_015$;

do $baseline_trigger_016$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.recipes'::regclass and tgname = 'recipes_enforce_owner' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_016$CREATE TRIGGER recipes_enforce_owner BEFORE INSERT ON public."recipes" FOR EACH ROW EXECUTE FUNCTION public."recipes_set_owner"();$baseline_trigger_ddl_016$;
  end if;
end;
$baseline_trigger_016$;

do $baseline_trigger_017$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.recipes'::regclass and tgname = 'recipes_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_017$CREATE TRIGGER recipes_set_updated_at BEFORE UPDATE ON public."recipes" FOR EACH ROW EXECUTE FUNCTION public."touch_recipes_updated_at"();$baseline_trigger_ddl_017$;
  end if;
end;
$baseline_trigger_017$;

do $baseline_trigger_018$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.runtime_config'::regclass and tgname = 'runtime_config_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_018$CREATE TRIGGER runtime_config_set_updated_at BEFORE UPDATE ON public."runtime_config" FOR EACH ROW EXECUTE FUNCTION public."touch_runtime_config_updated_at"();$baseline_trigger_ddl_018$;
  end if;
end;
$baseline_trigger_018$;

do $baseline_trigger_019$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.store_analytics_daily'::regclass and tgname = 'store_analytics_daily_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_019$CREATE TRIGGER store_analytics_daily_set_updated_at BEFORE UPDATE ON public."store_analytics_daily" FOR EACH ROW EXECUTE FUNCTION public."touch_store_analytics_daily_updated_at"();$baseline_trigger_ddl_019$;
  end if;
end;
$baseline_trigger_019$;

do $baseline_trigger_020$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.subscription_plans'::regclass and tgname = 'subscription_plans_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_020$CREATE TRIGGER subscription_plans_set_updated_at BEFORE UPDATE ON public."subscription_plans" FOR EACH ROW EXECUTE FUNCTION public."touch_subscription_plans_updated_at"();$baseline_trigger_ddl_020$;
  end if;
end;
$baseline_trigger_020$;

do $baseline_trigger_021$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.subscriptions'::regclass and tgname = 'subscriptions_set_updated_at' and not tgisinternal
  ) then
    execute $baseline_trigger_ddl_021$CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON public."subscriptions" FOR EACH ROW EXECUTE FUNCTION public."touch_subscription_updated_at"();$baseline_trigger_ddl_021$;
  end if;
end;
$baseline_trigger_021$;

do $baseline_auth_trigger_1$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created' and not tgisinternal
  ) then
    execute $baseline_auth_trigger_ddl_1$CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();$baseline_auth_trigger_ddl_1$;
  end if;
end;
$baseline_auth_trigger_1$;

do $baseline_auth_trigger_2$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_email_updated' and not tgisinternal
  ) then
    execute $baseline_auth_trigger_ddl_2$CREATE TRIGGER on_auth_user_email_updated AFTER UPDATE OF email ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_user_email_updated();$baseline_auth_trigger_ddl_2$;
  end if;
end;
$baseline_auth_trigger_2$;

-- No production rows are copied; the migration only restores schema, policies, and routines.
