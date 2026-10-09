CREATE OR REPLACE FUNCTION public.map_commerce_store(p_store text)
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
$function$;

CREATE OR REPLACE FUNCTION public.map_commerce_platform(p_store text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case public.map_commerce_store(p_store)
    when 'app_store' then 'ios'
    when 'google_play' then 'android'
    else null
  end;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_payment_transaction(p_user_id uuid, p_platform text, p_store text, p_environment text, p_product_id text, p_entitlement_id text, p_transaction_id text, p_original_transaction_id text, p_order_id text, p_purchase_token text, p_event_type text, p_status text, p_purchase_at timestamp with time zone, p_renewal_at timestamp with time zone, p_expires_at timestamp with time zone, p_cancel_at timestamp with time zone, p_refund_at timestamp with time zone, p_currency text, p_gross_amount numeric, p_refund_amount numeric, p_estimated_proceeds numeric, p_final_proceeds numeric, p_estimated_gross_usd numeric, p_territory text, p_provider_source text, p_provider_event_id text, p_purchase_event_id uuid DEFAULT NULL::uuid)
 RETURNS payment_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.payment_transactions;
  v_store text;
  v_platform text;
  v_status text;
begin
  if p_event_type is null or length(trim(p_event_type)) = 0 then
    raise exception 'event_type required';
  end if;

  v_store := public.map_commerce_store(p_store);
  v_platform := coalesce(p_platform, public.map_commerce_platform(p_store));
  v_status := coalesce(nullif(p_status, ''), 'unknown');

  if p_provider_event_id is not null and length(trim(p_provider_event_id)) > 0 then
    insert into public.payment_transactions as t (
      user_id, platform, store, environment, product_id, entitlement_id,
      transaction_id, original_transaction_id, order_id, purchase_token,
      event_type, status, purchase_at, renewal_at, expires_at, cancel_at, refund_at,
      currency, gross_amount, refund_amount, estimated_proceeds, final_proceeds,
      estimated_gross_usd, territory, provider_source, provider_event_id, purchase_event_id
    ) values (
      p_user_id, v_platform, v_store, p_environment, p_product_id, p_entitlement_id,
      p_transaction_id, p_original_transaction_id, p_order_id, p_purchase_token,
      p_event_type, v_status, p_purchase_at, p_renewal_at, p_expires_at, p_cancel_at, p_refund_at,
      p_currency, p_gross_amount, p_refund_amount, p_estimated_proceeds, p_final_proceeds,
      p_estimated_gross_usd, p_territory, coalesce(nullif(p_provider_source, ''), 'revenuecat'),
      p_provider_event_id, p_purchase_event_id
    )
    on conflict (provider_source, provider_event_id) do update set
      user_id = coalesce(excluded.user_id, t.user_id),
      platform = coalesce(excluded.platform, t.platform),
      store = coalesce(excluded.store, t.store),
      environment = coalesce(excluded.environment, t.environment),
      product_id = coalesce(excluded.product_id, t.product_id),
      entitlement_id = coalesce(excluded.entitlement_id, t.entitlement_id),
      transaction_id = coalesce(excluded.transaction_id, t.transaction_id),
      original_transaction_id = coalesce(excluded.original_transaction_id, t.original_transaction_id),
      order_id = coalesce(excluded.order_id, t.order_id),
      purchase_token = coalesce(excluded.purchase_token, t.purchase_token),
      event_type = excluded.event_type,
      status = excluded.status,
      purchase_at = coalesce(excluded.purchase_at, t.purchase_at),
      renewal_at = coalesce(excluded.renewal_at, t.renewal_at),
      expires_at = coalesce(excluded.expires_at, t.expires_at),
      cancel_at = coalesce(excluded.cancel_at, t.cancel_at),
      refund_at = coalesce(excluded.refund_at, t.refund_at),
      currency = coalesce(excluded.currency, t.currency),
      gross_amount = coalesce(excluded.gross_amount, t.gross_amount),
      refund_amount = coalesce(excluded.refund_amount, t.refund_amount),
      estimated_proceeds = coalesce(excluded.estimated_proceeds, t.estimated_proceeds),
      final_proceeds = coalesce(t.final_proceeds, excluded.final_proceeds),
      estimated_gross_usd = coalesce(excluded.estimated_gross_usd, t.estimated_gross_usd),
      territory = coalesce(excluded.territory, t.territory),
      purchase_event_id = coalesce(excluded.purchase_event_id, t.purchase_event_id),
      updated_at = now()
    returning * into v_row;
  else
    insert into public.payment_transactions (
      user_id, platform, store, environment, product_id, entitlement_id,
      transaction_id, original_transaction_id, order_id, purchase_token,
      event_type, status, purchase_at, renewal_at, expires_at, cancel_at, refund_at,
      currency, gross_amount, refund_amount, estimated_proceeds, final_proceeds,
      estimated_gross_usd, territory, provider_source, provider_event_id, purchase_event_id
    ) values (
      p_user_id, v_platform, v_store, p_environment, p_product_id, p_entitlement_id,
      p_transaction_id, p_original_transaction_id, p_order_id, p_purchase_token,
      p_event_type, v_status, p_purchase_at, p_renewal_at, p_expires_at, p_cancel_at, p_refund_at,
      p_currency, p_gross_amount, p_refund_amount, p_estimated_proceeds, p_final_proceeds,
      p_estimated_gross_usd, p_territory, coalesce(nullif(p_provider_source, ''), 'revenuecat'),
      null, p_purchase_event_id
    )
    returning * into v_row;
  end if;

  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_subscription_from_revenuecat(p_user_id uuid, p_event_type text, p_product_id text, p_entitlement_id text, p_status text, p_store text, p_environment text, p_expires_at timestamp with time zone, p_will_renew boolean, p_revenuecat_app_user_id text, p_rc_event_id text, p_raw_event jsonb)
 RETURNS subscriptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.subscriptions;
  v_plan text;
  v_event_ts bigint;
  v_purchase_event_id uuid;
  v_is_duplicate boolean := false;
  v_purchase_at timestamptz;
  v_renewal_at timestamptz;
  v_cancel_at timestamptz;
  v_refund_at timestamptz;
  v_currency text;
  v_gross numeric;
  v_refund numeric;
  v_usd numeric;
  v_territory text;
  v_txn_id text;
  v_orig_txn_id text;
  v_tx_status text;
  v_type_upper text;
begin
  v_plan := coalesce(nullif(p_entitlement_id, ''), nullif(p_product_id, ''), 'pro');
  v_type_upper := upper(coalesce(p_event_type, ''));

  v_event_ts := null;
  if p_raw_event is not null and (p_raw_event ? 'event_timestamp_ms') then
    begin
      v_event_ts := nullif(p_raw_event ->> 'event_timestamp_ms', '')::bigint;
    exception
      when others then
        v_event_ts := null;
    end;
  end if;

  if p_rc_event_id is not null then
    insert into public.purchase_events (
      user_id, rc_event_id, event_type, product_id, store, environment, raw_event
    ) values (
      p_user_id, p_rc_event_id, p_event_type, p_product_id, p_store, p_environment, coalesce(p_raw_event, '{}'::jsonb)
    )
    on conflict (rc_event_id) do nothing
    returning id into v_purchase_event_id;

    if v_purchase_event_id is null then
      v_is_duplicate := true;
      select id into v_purchase_event_id
      from public.purchase_events
      where rc_event_id = p_rc_event_id
      limit 1;
    end if;
  else
    insert into public.purchase_events (
      user_id, event_type, product_id, store, environment, raw_event
    ) values (
      p_user_id, p_event_type, p_product_id, p_store, p_environment, coalesce(p_raw_event, '{}'::jsonb)
    )
    returning id into v_purchase_event_id;
  end if;

  begin
    v_purchase_at := null;
    if p_raw_event is not null and (p_raw_event ? 'purchased_at_ms') then
      begin
        v_purchase_at := to_timestamp((nullif(p_raw_event ->> 'purchased_at_ms', '')::bigint) / 1000.0);
      exception when others then
        v_purchase_at := null;
      end;
    end if;

    v_renewal_at := case when v_type_upper = 'RENEWAL' then v_purchase_at else null end;
    v_cancel_at := case when v_type_upper = 'CANCELLATION' then coalesce(
      case
        when p_raw_event ? 'event_timestamp_ms' then
          to_timestamp((nullif(p_raw_event ->> 'event_timestamp_ms', '')::bigint) / 1000.0)
        else null
      end,
      now()
    ) else null end;

    v_refund_at := null;
    v_refund := null;
    if v_type_upper = 'CANCELLATION'
       and lower(coalesce(p_raw_event ->> 'cancellation_reason', '')) in ('customer_support', 'refund') then
      v_refund_at := v_cancel_at;
      begin
        v_refund := nullif(p_raw_event ->> 'price_in_purchased_currency', '')::numeric;
      exception when others then
        v_refund := null;
      end;
    end if;

    begin
      v_gross := nullif(p_raw_event ->> 'price_in_purchased_currency', '')::numeric;
    exception when others then
      v_gross := null;
    end;
    begin
      v_usd := nullif(p_raw_event ->> 'price', '')::numeric;
    exception when others then
      v_usd := null;
    end;

    v_currency := nullif(p_raw_event ->> 'currency', '');
    v_territory := nullif(p_raw_event ->> 'country_code', '');
    v_txn_id := nullif(p_raw_event ->> 'transaction_id', '');
    v_orig_txn_id := nullif(p_raw_event ->> 'original_transaction_id', '');

    v_tx_status := case
      when v_refund_at is not null then 'refunded'
      when p_status in ('active', 'trialing', 'cancelled', 'expired', 'billing_issue') then p_status
      else 'unknown'
    end;

    perform public.upsert_payment_transaction(
      p_user_id,
      public.map_commerce_platform(p_store),
      public.map_commerce_store(p_store),
      p_environment,
      p_product_id,
      p_entitlement_id,
      v_txn_id,
      v_orig_txn_id,
      null,
      null,
      p_event_type,
      v_tx_status,
      v_purchase_at,
      v_renewal_at,
      p_expires_at,
      v_cancel_at,
      v_refund_at,
      v_currency,
      v_gross,
      v_refund,
      null,
      null,
      v_usd,
      v_territory,
      'revenuecat',
      p_rc_event_id,
      v_purchase_event_id
    );
  exception
    when others then
      raise warning 'payment_transactions upsert failed: %', sqlerrm;
  end;

  if v_is_duplicate then
    select * into v_row from public.subscriptions where user_id = p_user_id;
    return v_row;
  end if;

  insert into public.subscriptions as s (
    user_id, entitlement_id, product_id, plan, status, store, environment,
    expires_at, will_renew, revenuecat_app_user_id, latest_event_type, latest_event_timestamp_ms
  ) values (
    p_user_id, p_entitlement_id, p_product_id, v_plan, p_status, p_store, p_environment,
    p_expires_at, p_will_renew, p_revenuecat_app_user_id, p_event_type, v_event_ts
  )
  on conflict (user_id) do update set
    entitlement_id = excluded.entitlement_id,
    product_id = excluded.product_id,
    plan = excluded.plan,
    status = excluded.status,
    store = excluded.store,
    environment = excluded.environment,
    expires_at = excluded.expires_at,
    will_renew = coalesce(excluded.will_renew, s.will_renew),
    revenuecat_app_user_id = excluded.revenuecat_app_user_id,
    latest_event_type = excluded.latest_event_type,
    latest_event_timestamp_ms = coalesce(excluded.latest_event_timestamp_ms, s.latest_event_timestamp_ms),
    updated_at = now()
  where
    excluded.latest_event_timestamp_ms is null
    or s.latest_event_timestamp_ms is null
    or excluded.latest_event_timestamp_ms >= s.latest_event_timestamp_ms
  returning * into v_row;

  if v_row is null then
    select * into v_row from public.subscriptions where user_id = p_user_id;
  end if;

  return v_row;
end;
$function$;
