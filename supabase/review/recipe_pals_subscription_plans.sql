-- Developer: gengyun
-- Purpose: Preview additive Recipe Pals plan mappings without changing historical products.
-- Review-only proposal for #132; deliberately excluded from migrations.
-- Recheck the live catalog and (platform, product_id) uniqueness before approval.
-- Existing legacy plans, subscriptions, purchase events and payments remain intact.
BEGIN;

INSERT INTO public.subscription_plans (
    plan_key, display_name, platform, product_id, price, currency,
    billing_period, active, description
)
VALUES
    (
        'pro_monthly', 'Recipe Pals Pro Monthly', 'app_store',
        'com.shopkivoo.recipe.pro.monthly', 4.99, 'USD',
        'monthly', true, 'Premium recipe features, billed monthly.'
    ),
    (
        'pro_yearly', 'Recipe Pals Pro Annual', 'app_store',
        'com.shopkivoo.recipe.pro.yearly', 39.99, 'USD',
        'yearly', true, 'Premium recipe features, billed annually.'
    )
ON CONFLICT (platform, product_id) DO NOTHING
RETURNING plan_key, platform, product_id, price, currency, billing_period;

-- This file always rolls back. Applying the reviewed proposal requires a
-- separately approved migration/configuration action by the coordinator.
ROLLBACK;
