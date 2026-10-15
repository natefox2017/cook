-- Developer: gengyun
-- Purpose: Persist DEV-431 owner-scoped AI recipe edit proposals. Bounded 3-path changes only,
-- replay idempotency by operation, revision CAS, and single-commit approval. SECURITY DEFINER
-- RPCs are service-role only; the Edge Function verifies the JWT owner before invoking them.

create table if not exists public.recipe_edit_proposals (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    operation_id uuid not null,
    intent text not null check (intent in ('substitute','simplify','dietary')),
    recipe_id uuid not null,
    source_revision text not null,
    snapshot_hash text not null check (snapshot_hash ~ '^[a-f0-9]{64}$'),
    input_hash text not null check (input_hash ~ '^[a-f0-9]{64}$'),
    status text not null default 'generated' check (status in ('generated','approved','rejected')),
    changes jsonb not null,
    reasons jsonb not null default '[]'::jsonb,
    warnings jsonb not null default '[]'::jsonb,
    needs_manual_edit boolean not null default false,
    payload_hash text check (payload_hash is null or payload_hash ~ '^[a-f0-9]{64}$'),
    approved_payload jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (owner_id, operation_id),
    unique (id, owner_id)
);

create index if not exists recipe_edit_proposals_recipe_idx
    on public.recipe_edit_proposals(owner_id, recipe_id, source_revision);

-- Mirrors RecipeEditProposal.safeText: trimmed non-empty, bounded length, no control characters.
create or replace function public.recipe_edit_text_valid(t text, max_len integer) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
    if t is null or length(t) > max_len then return false; end if;
    if btrim(t) = '' then return false; end if;
    if t ~ '[[:cntrl:]]' then return false; end if;
    return true;
exception when others then return false;
end $$;

-- Strict edit-v1 change-set validator: only the three value-replacement paths the iOS
-- RecipeEditChange whitelist accepts. No additions, deletions, index moves, or other fields.
create or replace function public.recipe_edit_changes_valid(c jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare item jsonb; path text; max_len integer; begin
    if c is null or jsonb_typeof(c) <> 'array' or jsonb_array_length(c) not between 1 and 30 then return false; end if;
    if (select count(distinct x->>'path') from jsonb_array_elements(c) x) <> jsonb_array_length(c) then return false; end if;
    for item in select * from jsonb_array_elements(c) loop
        if jsonb_typeof(item) <> 'object'
            or (select count(*) from jsonb_object_keys(item)) <> 5
            or jsonb_typeof(item->'path') is distinct from 'string'
            or jsonb_typeof(item->'original') is distinct from 'string'
            or jsonb_typeof(item->'proposed') is distinct from 'string'
            or jsonb_typeof(item->'reason') is distinct from 'string'
            or jsonb_typeof(item->'warnings') is distinct from 'array' then return false; end if;
        path := item->>'path';
        if path ~ '^ingredient:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:(name|amount)$' then
            max_len := 240;
        elsif path ~ '^step:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:instruction$' then
            max_len := 8000;
        else
            return false;
        end if;
        if not public.recipe_edit_text_valid(item->>'original', max_len)
            or not public.recipe_edit_text_valid(item->>'proposed', max_len)
            or item->>'original' = item->>'proposed' then return false; end if;
        if length(item->>'reason') not between 1 and 300 then return false; end if;
        if jsonb_array_length(item->'warnings') > 8 then return false; end if;
        if exists(select 1 from jsonb_array_elements_text(item->'warnings') w where length(w) not between 1 and 300) then return false; end if;
        if (select count(distinct x) from jsonb_array_elements_text(item->'warnings') x) <> jsonb_array_length(item->'warnings') then return false; end if;
    end loop;
    return true;
exception when others then return false;
end $$;

create or replace function public.create_recipe_edit_proposal(
    p_owner_id uuid, p_operation_id uuid, p_intent text, p_recipe_id uuid,
    p_source_revision text, p_snapshot_hash text, p_input_hash text,
    p_changes jsonb, p_reasons jsonb, p_warnings jsonb, p_needs_manual_edit boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.recipe_edit_proposals%rowtype; begin
    if p_owner_id is null or p_operation_id is null or p_recipe_id is null
        or p_intent is null or p_intent not in ('substitute','simplify','dietary')
        or p_source_revision is null or btrim(p_source_revision) = ''
        or p_snapshot_hash is null or p_snapshot_hash !~ '^[a-f0-9]{64}$'
        or p_input_hash is null or p_input_hash !~ '^[a-f0-9]{64}$'
        or p_needs_manual_edit is null
        or p_reasons is null or jsonb_typeof(p_reasons) <> 'array' or jsonb_array_length(p_reasons) > 8
        or p_warnings is null or jsonb_typeof(p_warnings) <> 'array' or jsonb_array_length(p_warnings) > 8
        or exists(select 1 from jsonb_array_elements_text(p_reasons) x where length(x) not between 1 and 300)
        or exists(select 1 from jsonb_array_elements_text(p_warnings) x where length(x) not between 1 and 300) then
        return jsonb_build_object('code','INVALID_INPUT'); end if;
    if p_changes is null or jsonb_typeof(p_changes) <> 'array' then return jsonb_build_object('code','INVALID_INPUT'); end if;
    if p_needs_manual_edit then
        if jsonb_array_length(p_changes) <> 0 then return jsonb_build_object('code','INVALID_INPUT'); end if;
    elsif not public.recipe_edit_changes_valid(p_changes) then
        return jsonb_build_object('code','INVALID_INPUT');
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_owner_id::text || ':' || p_operation_id::text, 0));
    select * into s from public.recipe_edit_proposals where owner_id = p_owner_id and operation_id = p_operation_id;
    if found then
        if s.intent <> p_intent or s.snapshot_hash <> p_snapshot_hash or s.input_hash <> p_input_hash then
            return jsonb_build_object('code','IDEMPOTENCY_CONFLICT'); end if;
        return jsonb_build_object('outcome','replay','proposal',to_jsonb(s));
    end if;
    -- Reject edits based on an older recipe revision than an already recorded proposal.
    if exists(select 1 from public.recipe_edit_proposals
        where owner_id = p_owner_id and recipe_id = p_recipe_id
        and p_source_revision < source_revision) then
        return jsonb_build_object('code','STALE_REVISION'); end if;
    insert into public.recipe_edit_proposals(
        owner_id, operation_id, intent, recipe_id, source_revision, snapshot_hash, input_hash,
        status, changes, reasons, warnings, needs_manual_edit)
    values(p_owner_id, p_operation_id, p_intent, p_recipe_id, p_source_revision, p_snapshot_hash, p_input_hash,
        'generated', p_changes, p_reasons, p_warnings, p_needs_manual_edit)
    returning * into s;
    return jsonb_build_object('outcome','created','proposal',to_jsonb(s));
end $$;

create or replace function public.approve_recipe_edit_proposal(
    p_owner_id uuid, p_proposal_id uuid, p_changes jsonb,
    p_expected_snapshot_hash text, p_payload_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.recipe_edit_proposals%rowtype; begin
    if p_owner_id is null or p_proposal_id is null
        or p_expected_snapshot_hash is null or p_expected_snapshot_hash !~ '^[a-f0-9]{64}$'
        or p_payload_hash is null or p_payload_hash !~ '^[a-f0-9]{64}$' then
        return jsonb_build_object('code','INVALID_INPUT'); end if;
    if not public.recipe_edit_changes_valid(p_changes) then return jsonb_build_object('code','INVALID_INPUT'); end if;
    perform pg_advisory_xact_lock(hashtextextended(p_owner_id::text || ':' || p_proposal_id::text, 0));
    select * into s from public.recipe_edit_proposals where owner_id = p_owner_id and id = p_proposal_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if s.status = 'approved' then
        if s.approved_payload = p_changes and s.payload_hash = p_payload_hash then
            return jsonb_build_object('outcome','replay','proposal',to_jsonb(s));
        end if;
        return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');
    end if;
    if s.status = 'rejected' then return jsonb_build_object('code','ALREADY_REJECTED'); end if;
    if s.needs_manual_edit then return jsonb_build_object('code','NEEDS_MANUAL_EDIT'); end if;
    if s.snapshot_hash <> p_expected_snapshot_hash then return jsonb_build_object('code','STALE_REVISION'); end if;
    update public.recipe_edit_proposals
    set status = 'approved', approved_payload = p_changes, payload_hash = p_payload_hash, updated_at = now()
    where owner_id = p_owner_id and id = p_proposal_id returning * into s;
    return jsonb_build_object('outcome','approved','proposal',to_jsonb(s));
end $$;

alter table public.recipe_edit_proposals enable row level security;
revoke all on public.recipe_edit_proposals from public, anon, authenticated;
grant select on public.recipe_edit_proposals to authenticated;
grant all on public.recipe_edit_proposals to service_role;
drop policy if exists read_own on public.recipe_edit_proposals;
create policy read_own on public.recipe_edit_proposals
    for select to authenticated using (owner_id = (select auth.uid()));

-- SECURITY DEFINER is never an invitation to PUBLIC execution: writes stay service-role only.
do $$ declare fn record; begin
    for fn in select oid::regprocedure as signature from pg_proc
        where pronamespace='public'::regnamespace
        and proname in ('recipe_edit_text_valid','recipe_edit_changes_valid','create_recipe_edit_proposal','approve_recipe_edit_proposal') loop
        execute format('revoke all on function %s from public,anon,authenticated,service_role', fn.signature);
        if fn.signature::text ~ '^(public\.)?(create|approve)_recipe_edit_' then
            execute format('grant execute on function %s to service_role', fn.signature);
        end if;
    end loop;
end $$;
