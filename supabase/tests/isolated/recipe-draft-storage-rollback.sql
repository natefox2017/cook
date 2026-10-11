-- Developer: gengyun
-- Purpose: Disposable DEV-293 rollback only; never execute against a hosted database.
drop trigger if exists recipe_draft_job_delete_locks on public.recipe_import_jobs;
drop function if exists public.recipe_draft_before_job_delete();
drop table if exists public.recipe_draft_approvals;
drop table if exists public.recipe_draft_turns;
drop table if exists public.recipe_draft_sessions;
drop table if exists public.recipe_draft_owner_budgets;
drop function if exists public.create_recipe_draft_session(uuid,uuid,uuid,jsonb,jsonb,text,boolean);
drop function if exists public.claim_recipe_draft_turn(uuid,uuid,uuid,bigint,text,text,text,boolean);
drop function if exists public.mark_recipe_draft_turn_dispatched(uuid,uuid,uuid,uuid,boolean);
drop function if exists public.finish_recipe_draft_turn(uuid,uuid,uuid,uuid,jsonb,integer,text);
drop function if exists public.recover_recipe_draft_turn(uuid,uuid,uuid,boolean);
drop function if exists public.approve_recipe_draft_turn(uuid,uuid,uuid,uuid,bigint,text,text[],text,jsonb,text,boolean);
drop function if exists public.recipe_draft_settle(uuid,uuid,uuid,jsonb,integer);
drop function if exists public.recipe_draft_before_session_delete();
drop function if exists public.recipe_draft_context_valid(jsonb);
drop function if exists public.recipe_draft_result_valid(jsonb);
