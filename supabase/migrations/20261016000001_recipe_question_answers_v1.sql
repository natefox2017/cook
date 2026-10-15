-- Developer: gengyun
-- Purpose: DEV-438 durable recipe-question answer store. It persists one bounded, validated answer per
--          operation so a timeout recovery can settle the same operation without re-sending the provider
--          and the phase-II metering finalization can bind its durable result. It is NOT a chat history:
--          the 5-turn conversation stays local to the client and no long-term chat library is created.

create table if not exists public.recipe_question_answers (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    recipe_id uuid not null,
    operation_id uuid not null unique,
    input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
    question text not null check (char_length(question) between 1 and 1000),
    answer jsonb not null check (jsonb_typeof(answer) = 'object'),
    payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
    created_at timestamptz not null default now()
);

create index if not exists recipe_question_answers_owner_idx
    on public.recipe_question_answers(owner_id, created_at desc);

-- Defense in depth: the answer store is server-owned. No client may read or write it;
-- service_role alone backs the verified-owner Edge handler.
alter table public.recipe_question_answers enable row level security;
revoke all on public.recipe_question_answers from public, anon, authenticated;
grant all on public.recipe_question_answers to service_role;
