-- Developer: gengyun
-- Purpose: Remove DEV-282 share objects only in a disposable in-memory test database.
-- Never use this fixture as a hosted database or production rollback command.
drop function if exists public.create_recipe_share_once(uuid, jsonb, text, text);
drop table if exists public.recipe_shared_snapshots;
