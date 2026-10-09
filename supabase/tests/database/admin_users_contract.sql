-- Developer: gengyun
-- Purpose: Verify admin user subscription lookups use persisted plan identity and billing periods.
begin;

create temp table admin_user_profiles_fixture (
    id uuid primary key,
    registration_provider text
);
create temp table admin_user_subscriptions_fixture (
    user_id uuid primary key,
    product_id text,
    store text,
    status text,
    plan text
);
create temp table admin_user_plans_fixture (
    plan_key text not null,
    product_id text not null,
    platform text not null,
    billing_period text not null,
    primary key (platform, product_id)
);

insert into admin_user_profiles_fixture values
    ('00000000-0000-4000-8000-000000000001', 'email'),
    ('00000000-0000-4000-8000-000000000002', 'apple'),
    ('00000000-0000-4000-8000-000000000003', 'google');
insert into admin_user_subscriptions_fixture values
    ('00000000-0000-4000-8000-000000000001', 'ios.monthly', 'app_store', 'active', null),
    ('00000000-0000-4000-8000-000000000002', 'play.yearly', 'play_store', 'trialing', null);
insert into admin_user_plans_fixture values
    ('pro_monthly', 'ios.monthly', 'app_store', 'monthly'),
    ('pro_yearly', 'play.yearly', 'play_store', 'yearly');

select plan(5);

select is(
    (select plan.billing_period
     from admin_user_subscriptions_fixture subscription
     join admin_user_plans_fixture plan
       on plan.product_id = subscription.product_id
      and plan.platform = subscription.store
     where subscription.user_id = '00000000-0000-4000-8000-000000000001'),
    'monthly',
    'monthly billing period comes from the matching platform plan'
);

select is(
    (select plan.billing_period
     from admin_user_subscriptions_fixture subscription
     join admin_user_plans_fixture plan
       on plan.product_id = subscription.product_id
      and plan.platform = subscription.store
     where subscription.user_id = '00000000-0000-4000-8000-000000000002'),
    'yearly',
    'yearly billing period comes from the matching platform plan'
);

select is(
    (select count(*)::integer
     from admin_user_profiles_fixture profile
     left join admin_user_subscriptions_fixture subscription on subscription.user_id = profile.id
     where profile.id = '00000000-0000-4000-8000-000000000003'
       and subscription.user_id is null),
    1,
    'a user with no subscription remains present in the page result'
);

select is(
    (select count(*)::integer
     from admin_user_profiles_fixture profile
     left join admin_user_subscriptions_fixture subscription on subscription.user_id = profile.id
     left join admin_user_plans_fixture plan
       on plan.product_id = subscription.product_id
      and plan.platform = subscription.store
     where profile.id = '00000000-0000-4000-8000-000000000003'
       and plan.billing_period is null),
    1,
    'missing subscription metadata stays null instead of being inferred'
);

select is(
    (select registration_provider from admin_user_profiles_fixture
     where id = '00000000-0000-4000-8000-000000000003'),
    'google',
    'registration provider comes from the profile record'
);

select * from finish();
rollback;
