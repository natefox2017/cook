-- Developer: gengyun
-- Purpose: Build anonymous local tables from observed columns; not a production schema migration.
create table public.purchase_events (
  id uuid default gen_random_uuid() not null,
  user_id uuid,
  rc_event_id text,
  event_type text not null,
  product_id text,
  store text,
  environment text,
  raw_event jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);
create table public.payment_transactions (
  id uuid default gen_random_uuid() not null,
  user_id uuid,
  platform text,
  store text,
  environment text,
  product_id text,
  entitlement_id text,
  transaction_id text,
  original_transaction_id text,
  order_id text,
  purchase_token text,
  event_type text not null,
  status text default 'unknown'::text not null,
  purchase_at timestamp with time zone,
  renewal_at timestamp with time zone,
  expires_at timestamp with time zone,
  cancel_at timestamp with time zone,
  refund_at timestamp with time zone,
  currency text,
  gross_amount numeric,
  refund_amount numeric,
  estimated_proceeds numeric,
  final_proceeds numeric,
  estimated_gross_usd numeric,
  territory text,
  provider_source text default 'revenuecat'::text not null,
  provider_event_id text,
  purchase_event_id uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);
create table public.subscriptions (
  user_id uuid not null,
  entitlement_id text,
  product_id text,
  status text default 'none'::text not null,
  store text,
  environment text,
  expires_at timestamp with time zone,
  will_renew boolean,
  revenuecat_app_user_id text,
  latest_event_type text,
  updated_at timestamp with time zone default now() not null,
  created_at timestamp with time zone default now() not null,
  plan text,
  latest_event_timestamp_ms bigint
);

alter table public.purchase_events add primary key (id), add unique (rc_event_id), add foreign key (user_id) references auth.users(id) on delete set null;
alter table public.payment_transactions add primary key (id), add unique (provider_source, provider_event_id),
  add foreign key (user_id) references auth.users(id) on delete set null,
  add foreign key (purchase_event_id) references public.purchase_events(id) on delete set null;
alter table public.subscriptions add primary key (user_id), add foreign key (user_id) references auth.users(id) on delete cascade;
grant all on public.purchase_events, public.payment_transactions, public.subscriptions to service_role;
insert into auth.users(id, aud, role) values
  ('00000000-0000-4000-8000-000000000001','authenticated','authenticated'),
  ('00000000-0000-4000-8000-000000000002','authenticated','authenticated');
