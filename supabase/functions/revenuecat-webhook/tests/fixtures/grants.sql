-- Developer: gengyun
-- Purpose: Match observed service-only RPC privileges in the local fixture.
revoke all on function public.upsert_payment_transaction(uuid, text, text, text, text, text, text, text, text, text, text, text, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, text, numeric, numeric, numeric, numeric, numeric, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.upsert_payment_transaction(uuid, text, text, text, text, text, text, text, text, text, text, text, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, text, numeric, numeric, numeric, numeric, numeric, text, text, text, uuid) to service_role;
revoke all on function public.upsert_subscription_from_revenuecat(uuid, text, text, text, text, text, text, timestamp with time zone, boolean, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.upsert_subscription_from_revenuecat(uuid, text, text, text, text, text, text, timestamp with time zone, boolean, text, text, jsonb) to service_role;
