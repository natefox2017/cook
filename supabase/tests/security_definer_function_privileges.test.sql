begin;

select plan(15);

select ok(
  to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is null
  or not has_function_privilege(
    'anon',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  'anon cannot execute admin_bootstrap_owner'
);
select ok(
  to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is null
  or not has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  'authenticated cannot execute admin_bootstrap_owner'
);
select ok(
  to_regprocedure('public.admin_bootstrap_owner(text,text,text)') is null
  or has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_bootstrap_owner(text,text,text)'),
    'execute'
  ),
  'service_role can execute admin_bootstrap_owner'
);

select ok(
  to_regprocedure('public.admin_change_password(uuid,text,text)') is null
  or not has_function_privilege(
    'anon',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  'anon cannot execute admin_change_password'
);
select ok(
  to_regprocedure('public.admin_change_password(uuid,text,text)') is null
  or not has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  'authenticated cannot execute admin_change_password'
);
select ok(
  to_regprocedure('public.admin_change_password(uuid,text,text)') is null
  or has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_change_password(uuid,text,text)'),
    'execute'
  ),
  'service_role can execute admin_change_password'
);

select ok(
  to_regprocedure('public.admin_verify_credentials(text,text)') is null
  or not has_function_privilege(
    'anon',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  'anon cannot execute admin_verify_credentials'
);
select ok(
  to_regprocedure('public.admin_verify_credentials(text,text)') is null
  or not has_function_privilege(
    'authenticated',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  'authenticated cannot execute admin_verify_credentials'
);
select ok(
  to_regprocedure('public.admin_verify_credentials(text,text)') is null
  or has_function_privilege(
    'service_role',
    to_regprocedure('public.admin_verify_credentials(text,text)'),
    'execute'
  ),
  'service_role can execute admin_verify_credentials'
);

select ok(
  to_regprocedure('public.capture_registration_meta(text,text)') is null
  or not has_function_privilege(
    'anon',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  'anon cannot execute capture_registration_meta'
);
select ok(
  to_regprocedure('public.capture_registration_meta(text,text)') is null
  or has_function_privilege(
    'authenticated',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  'authenticated can execute capture_registration_meta'
);
select ok(
  to_regprocedure('public.capture_registration_meta(text,text)') is null
  or has_function_privilege(
    'service_role',
    to_regprocedure('public.capture_registration_meta(text,text)'),
    'execute'
  ),
  'service_role can execute capture_registration_meta'
);

select ok(
  to_regprocedure('public.get_runtime_config_number(text,numeric)') is null
  or not has_function_privilege(
    'anon',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  'anon cannot execute get_runtime_config_number'
);
select ok(
  to_regprocedure('public.get_runtime_config_number(text,numeric)') is null
  or not has_function_privilege(
    'authenticated',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  'authenticated cannot execute get_runtime_config_number'
);
select ok(
  to_regprocedure('public.get_runtime_config_number(text,numeric)') is null
  or has_function_privilege(
    'service_role',
    to_regprocedure('public.get_runtime_config_number(text,numeric)'),
    'execute'
  ),
  'service_role can execute get_runtime_config_number'
);

select * from finish();

rollback;
