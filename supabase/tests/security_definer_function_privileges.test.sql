-- These legacy functions are not created by repository migrations; missing signatures must fail this ACL test.
begin;

select plan(20);

select ok(
  to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is not null,
  'admin_bootstrap_owner exists in the ACL test database'
);
select is(
  has_function_privilege(
    'anon',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  false,
  'anon cannot execute admin_bootstrap_owner'
);
select is(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  false,
  'authenticated cannot execute admin_bootstrap_owner'
);
select is(
  has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  true,
  'service_role can execute admin_bootstrap_owner'
);

select ok(
  to_regprocedure('public.admin_change_password(uuid,text,text)') is not null,
  'admin_change_password exists in the ACL test database'
);
select is(
  has_function_privilege(
    'anon',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  false,
  'anon cannot execute admin_change_password'
);
select is(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  false,
  'authenticated cannot execute admin_change_password'
);
select is(
  has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  true,
  'service_role can execute admin_change_password'
);

select ok(
  to_regprocedure('public.admin_verify_credentials(text,text)') is not null,
  'admin_verify_credentials exists in the ACL test database'
);
select is(
  has_function_privilege(
    'anon',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  false,
  'anon cannot execute admin_verify_credentials'
);
select is(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  false,
  'authenticated cannot execute admin_verify_credentials'
);
select is(
  has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  true,
  'service_role can execute admin_verify_credentials'
);

select ok(
  to_regprocedure('public.capture_registration_meta(text,text)') is not null,
  'capture_registration_meta exists in the ACL test database'
);
select is(
  has_function_privilege(
    'anon',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  false,
  'anon cannot execute capture_registration_meta'
);
select is(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  true,
  'authenticated can execute capture_registration_meta'
);
select is(
  has_function_privilege(
    'service_role',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  false,
  'service_role cannot execute capture_registration_meta'
);

select ok(
  to_regprocedure('public.get_runtime_config_number(text,numeric)') is not null,
  'get_runtime_config_number exists in the ACL test database'
);
select is(
  has_function_privilege(
    'anon',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  false,
  'anon cannot execute get_runtime_config_number'
);
select is(
  has_function_privilege(
    'authenticated',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  false,
  'authenticated cannot execute get_runtime_config_number'
);
select is(
  has_function_privilege(
    'service_role',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  false,
  'service_role cannot execute get_runtime_config_number'
);

select * from finish();

rollback;
