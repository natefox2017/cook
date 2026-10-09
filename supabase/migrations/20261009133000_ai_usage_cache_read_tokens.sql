alter table public.ai_usage_events
  add column if not exists cache_read_input_tokens integer;

comment on column public.ai_usage_events.cache_read_input_tokens is
  'OpenTelemetry gen_ai.usage.cache_read.input_tokens; a subset of input_tokens. NULL means the provider did not report it.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.ai_usage_events'::regclass
      and conname = 'ai_usage_events_cache_read_input_tokens_nonnegative'
  ) then
    alter table public.ai_usage_events
      add constraint ai_usage_events_cache_read_input_tokens_nonnegative
      check (cache_read_input_tokens is null or cache_read_input_tokens >= 0)
      not valid;
  end if;
end
$$;

alter table public.ai_usage_events
  validate constraint ai_usage_events_cache_read_input_tokens_nonnegative;
