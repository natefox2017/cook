# Admin Dashboard

This endpoint is based on the read-only production `admin-dashboard` v1 `index.ts`, SHA-256 `508bd852b227a8367fe7cf6c2776f3e74d0d2fdd6a3d77ee8700eaef71169237`. Supabase reported `ezbr_sha256` `ba97df336b9ca7f894d7fc08f10d9e6d49c76482f5606ae37bfc33ca4119bd51`; that metadata value is distinct from the downloaded `index.ts` file hash.

It returns aggregate financial metrics and recent user details, including email and registration IP. The route therefore requires an owner admin session before creating a service-role client or querying dashboard data. The production function uses custom admin bearer tokens, so Supabase gateway JWT verification must remain disabled when deploying this function.

Dependencies are pinned and frozen in this directory's `deno.json` and `deno.lock`.

Local checks:

```sh
deno test --config supabase/functions/admin-dashboard/deno.json supabase/functions/admin-dashboard/access_test.ts
deno check --config supabase/functions/admin-dashboard/deno.json supabase/functions/admin-dashboard/index.ts supabase/functions/admin-dashboard/access_test.ts
```

These checks do not exercise a Supabase Edge Runtime, real admin sessions, database queries, or staging/production behavior.
