-- Developer: gengyun
-- Purpose: Persist DEV-293 owner draft claims, approval CAS and conservative token budgets.
-- JWT/non-anonymous verification and RFC8785 SHA256 belong to the trusted caller.
-- Service-role bypass is not owner authorization. No provider or private recipe writes.
create table if not exists public.recipe_draft_sessions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    job_id uuid not null references public.recipe_import_jobs(id) on delete cascade,
    client_request_id uuid not null,
    source_fingerprint text not null,
    base_context jsonb not null,
    base_context_hash text not null check (base_context_hash ~ '^[a-f0-9]{64}$'),
    effective_context jsonb not null,
    effective_context_hash text not null check (effective_context_hash ~ '^[a-f0-9]{64}$'),
    overlay jsonb not null default '{}',
    revision bigint not null default 1 check (revision > 0),
    settled_tokens integer not null default 0 check (settled_tokens >= 0),
    reserved_tokens integer not null default 0 check (reserved_tokens >= 0),
    dispatch_count integer not null default 0 check (dispatch_count between 0 and 8),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (owner_id, client_request_id), unique (id, owner_id),
    check (settled_tokens + reserved_tokens <= 32768)
);
create index if not exists recipe_draft_sessions_job_idx on public.recipe_draft_sessions(job_id);
create table if not exists public.recipe_draft_owner_budgets (
    owner_id uuid not null references auth.users(id) on delete cascade,
    utc_date date not null,
    settled_tokens integer not null default 0 check (settled_tokens >= 0),
    reserved_tokens integer not null default 0 check (reserved_tokens >= 0),
    primary key (owner_id, utc_date),
    check (settled_tokens + reserved_tokens <= 65536)
);
create table if not exists public.recipe_draft_turns (
    owner_id uuid not null,
    session_id uuid not null,
    request_id uuid not null,
    request_body jsonb not null,
    request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
    based_revision bigint not null check (based_revision > 0),
    context_snapshot jsonb not null,
    context_hash text not null check (context_hash ~ '^[a-f0-9]{64}$'),
    state text not null check (state in ('pending','terminal')),
    result jsonb,
    fencing_token uuid not null default gen_random_uuid(),
    lease_expires_at timestamptz not null,
    dispatch_state text not null check (dispatch_state in ('predispatch','dispatched_unknown','settled')),
    reserved_tokens integer not null check (reserved_tokens in (0,4096)),
    settled_tokens integer not null default 0 check (settled_tokens between 0 and 4096),
    budget_date date not null,
    created_at timestamptz not null default now(),
    finished_at timestamptz,
    primary key (owner_id, session_id, request_id),
    foreign key (session_id, owner_id) references public.recipe_draft_sessions(id, owner_id) on delete cascade,
    check ((state = 'pending' and result is null and reserved_tokens = 4096 and dispatch_state <> 'settled')
        or (state = 'terminal' and result is not null and reserved_tokens = 0 and dispatch_state = 'settled'))
);
create table if not exists public.recipe_draft_approvals (
    owner_id uuid not null, session_id uuid not null, request_id uuid not null,
    turn_request_id uuid not null, approval_body jsonb not null,
    approval_hash text not null check (approval_hash ~ '^[a-f0-9]{64}$'),
    action text not null check (action in ('accept','reject')),
    selected_paths text[] not null, applied_revision bigint not null check (applied_revision > 0),
    receipt jsonb not null,
    primary key (owner_id, session_id, request_id),
    unique (owner_id, session_id, turn_request_id),
    foreign key (owner_id, session_id, turn_request_id)
        references public.recipe_draft_turns(owner_id,session_id,request_id) on delete cascade
);
-- Policy creation is replay-safe without broadening write privileges.
do $$ declare name text; begin
    foreach name in array array['recipe_draft_sessions','recipe_draft_turns','recipe_draft_approvals','recipe_draft_owner_budgets'] loop
        execute format('alter table public.%I enable row level security', name);
        execute format('revoke all on public.%I from public, anon, authenticated', name);
        execute format('grant select on public.%I to authenticated', name);
        execute format('grant all on public.%I to service_role', name);
        execute format('drop policy if exists read_own on public.%I', name);
        execute format('create policy read_own on public.%I for select to authenticated using (owner_id = (select auth.uid()))', name);
    end loop;
end $$;

-- This checks storage/authorization shape, not extractive grounding or JCS.
create or replace function public.recipe_draft_context_valid(c jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare item jsonb; key text; total integer := 0; begin
    if c is null or jsonb_typeof(c) <> 'object' or octet_length(c::text) > 1048576
        or c->>'status' is null or c->>'status' not in ('ready','needs_review')
        or jsonb_typeof(c->'fields') is distinct from 'object'
        or jsonb_typeof(c->'evidence') is distinct from 'array'
        or jsonb_typeof(c->'review_fields') is distinct from 'array'
        or (select count(*) from jsonb_object_keys(c)) <> 4
        or (select count(*) from jsonb_object_keys(c->'fields')) > 100
        or jsonb_array_length(c->'evidence') > 60
        or jsonb_array_length(c->'review_fields') > 100 then return false; end if;
    for key,item in select * from jsonb_each(c->'fields') loop
        if key !~ '^(title|servings|ingredients\[([0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[([0-9]|[1-9][0-9])\]\.instruction)$'
            or jsonb_typeof(item) <> 'object'
            or jsonb_typeof(item->'user_confirmed') is distinct from 'boolean'
            or not (item ? 'raw_value') or jsonb_typeof(item->'raw_value') not in ('string','null')
            or jsonb_typeof(item->'origin') is distinct from 'string' or length(item->>'origin') not between 1 and 64
            or exists(select 1 from jsonb_object_keys(item) k where k not in ('raw_value','evidence_ids','user_confirmed','origin'))
            or (jsonb_typeof(item->'raw_value')='string' and length(item->>'raw_value') not between 1 and 1500)
            or jsonb_typeof(item->'evidence_ids') is distinct from 'array'
            or jsonb_array_length(item->'evidence_ids') > 60 then return false; end if;
        if exists(select 1 from jsonb_array_elements(item->'evidence_ids') x where jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') then return false; end if;
    end loop;
    for item in select * from jsonb_array_elements(c->'evidence') loop
        if jsonb_typeof(item) <> 'object' or jsonb_typeof(item->'id') is distinct from 'string'
            or jsonb_typeof(item->'excerpt') is distinct from 'string'
            or length(item->>'excerpt') not between 1 and 1500
            or item->>'id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
            or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','excerpt')) then return false; end if;
        total := total + length(item->>'excerpt');
    end loop;
    if total > 20000
        or (select count(distinct x->>'id') from jsonb_array_elements(c->'evidence') x)<>jsonb_array_length(c->'evidence')
        or (select count(distinct x) from jsonb_array_elements(c->'review_fields') x)<>jsonb_array_length(c->'review_fields') then return false; end if;
    for item in select value from jsonb_each(c->'fields') loop
        if (select count(distinct x) from jsonb_array_elements(item->'evidence_ids') x)<>jsonb_array_length(item->'evidence_ids')
            or exists(select 1 from jsonb_array_elements_text(item->'evidence_ids') x
                where not exists(select 1 from jsonb_array_elements(c->'evidence') e where e->>'id'=x)) then return false; end if;
    end loop;
    for item in select * from jsonb_array_elements(c->'review_fields') loop
        if jsonb_typeof(item) <> 'string' or (item #>> '{}') !~ '^(title|servings|ingredients|steps|ingredients\[([0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[([0-9]|[1-9][0-9])\]\.instruction)$' then return false; end if;
    end loop;
    return true;
exception when others then return false;
end $$;

create or replace function public.create_recipe_draft_session(
    p_owner_id uuid,p_client_request_id uuid,p_job_id uuid,p_expected_job_result jsonb,
    p_base_context jsonb,p_base_context_hash text,p_enabled boolean default false
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare j public.recipe_import_jobs%rowtype; s public.recipe_draft_sessions%rowtype; begin
    if p_enabled is distinct from true then return jsonb_build_object('code','DRAFT_DISABLED'); end if;
    if p_owner_id is null or p_client_request_id is null or p_job_id is null
        or p_base_context_hash is null or p_base_context_hash !~ '^[a-f0-9]{64}$'
        or not public.recipe_draft_context_valid(p_base_context) then return jsonb_build_object('code','INVALID_INPUT'); end if;
    -- Serialize creation replay keys without altering original import schema.
    perform pg_advisory_xact_lock(hashtextextended(p_owner_id::text || p_client_request_id::text,0));
    select * into s from public.recipe_draft_sessions where owner_id=p_owner_id and client_request_id=p_client_request_id;
    if found then
        if s.job_id <> p_job_id then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT'); end if;
        return jsonb_build_object('outcome','replay','session',(to_jsonb(s) || jsonb_build_object('revision',s.revision::text)));
    end if;
    select * into j from public.recipe_import_jobs where id=p_job_id and owner_id=p_owner_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if j.status <> 'completed' then return jsonb_build_object('code','JOB_NOT_READY'); end if;
    if j.result is null or j.result is distinct from p_expected_job_result then return jsonb_build_object('code','STALE_REVISION'); end if;
    insert into public.recipe_draft_sessions(owner_id,job_id,client_request_id,source_fingerprint,base_context,base_context_hash,effective_context,effective_context_hash)
    values(p_owner_id,p_job_id,p_client_request_id,j.source_fingerprint,p_base_context,p_base_context_hash,p_base_context,p_base_context_hash) returning * into s;
    return jsonb_build_object('outcome','created','session',(to_jsonb(s) || jsonb_build_object('revision',s.revision::text)));
end $$;

create or replace function public.claim_recipe_draft_turn(
    p_owner_id uuid,p_session_id uuid,p_request_id uuid,p_expected_revision bigint,
    p_message text,p_request_hash text,p_context_hash text,p_enabled boolean default false
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.recipe_draft_sessions%rowtype; t public.recipe_draft_turns%rowtype;
    b public.recipe_draft_owner_budgets%rowtype; body jsonb; day date := (now() at time zone 'UTC')::date; begin
    if p_enabled is distinct from true then return jsonb_build_object('code','DRAFT_DISABLED'); end if;
    if p_request_id is null or p_expected_revision is null or p_expected_revision <= 0 or p_message is null or length(p_message)>2000
        or p_request_hash is null or p_request_hash !~ '^[a-f0-9]{64}$' or p_context_hash is null or p_context_hash !~ '^[a-f0-9]{64}$' then return jsonb_build_object('code','INVALID_INPUT'); end if;
    select * into s from public.recipe_draft_sessions where id=p_session_id and owner_id=p_owner_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    body := jsonb_build_object('request_id',p_request_id,'expected_revision',p_expected_revision::text,'message',p_message);
    select * into t from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id for update;
    if found then
        if t.request_hash <> p_request_hash or t.request_body <> body then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT'); end if;
        return jsonb_build_object('outcome','replay','turn',(to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text)));
    end if;
    if s.revision <> p_expected_revision or s.effective_context_hash <> p_context_hash then return jsonb_build_object('code','STALE_REVISION'); end if;
    if s.effective_context->>'status'='ready' or jsonb_array_length(s.effective_context->'review_fields')=0 then
        insert into public.recipe_draft_turns(owner_id,session_id,request_id,request_body,request_hash,based_revision,context_snapshot,context_hash,state,result,lease_expires_at,dispatch_state,reserved_tokens,budget_date,finished_at)
        values(p_owner_id,p_session_id,p_request_id,body,p_request_hash,s.revision,s.effective_context,s.effective_context_hash,'terminal','{"status":"no_review_needed"}',now(),'settled',0,day,now()) returning * into t;
    else
        insert into public.recipe_draft_owner_budgets(owner_id,utc_date) values(p_owner_id,day) on conflict do nothing;
        select * into b from public.recipe_draft_owner_budgets where owner_id=p_owner_id and utc_date=day for update;
        if s.dispatch_count + (select count(*) from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and state='pending' and dispatch_state='predispatch') >= 8
            or s.settled_tokens+s.reserved_tokens+4096 > 32768 or b.settled_tokens+b.reserved_tokens+4096 > 65536 then return jsonb_build_object('code','BUDGET_EXHAUSTED'); end if;
        update public.recipe_draft_sessions set reserved_tokens=reserved_tokens+4096 where id=p_session_id and owner_id=p_owner_id;
        update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens+4096 where owner_id=p_owner_id and utc_date=day;
        insert into public.recipe_draft_turns(owner_id,session_id,request_id,request_body,request_hash,based_revision,context_snapshot,context_hash,state,lease_expires_at,dispatch_state,reserved_tokens,budget_date)
        values(p_owner_id,p_session_id,p_request_id,body,p_request_hash,s.revision,s.effective_context,s.effective_context_hash,'pending',now()+interval '30 seconds','predispatch',4096,day) returning * into t;
    end if;
    return jsonb_build_object('outcome','accepted','turn',(to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text)));
end $$;

-- Internal settlement: caller already locks session then turn; lock original UTC budget next.
create or replace function public.recipe_draft_settle(o uuid,sid uuid,rid uuid,result_value jsonb,cost integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.recipe_draft_turns%rowtype; begin
    select * into t from public.recipe_draft_turns where owner_id=o and session_id=sid and request_id=rid;
    if t.state <> 'pending' then return (to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text)); end if;
    perform 1 from public.recipe_draft_owner_budgets where owner_id=o and utc_date=t.budget_date for update;
    update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens-t.reserved_tokens,settled_tokens=settled_tokens+cost where owner_id=o and utc_date=t.budget_date;
    update public.recipe_draft_sessions set reserved_tokens=reserved_tokens-t.reserved_tokens,settled_tokens=settled_tokens+cost,updated_at=now() where owner_id=o and id=sid;
    update public.recipe_draft_turns set state='terminal',result=result_value,reserved_tokens=0,settled_tokens=cost,dispatch_state='settled',finished_at=now() where owner_id=o and session_id=sid and request_id=rid returning * into t;
    return (to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text));
end $$;

create or replace function public.mark_recipe_draft_turn_dispatched(p_owner_id uuid,p_session_id uuid,p_request_id uuid,p_fencing_token uuid,p_enabled boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.recipe_draft_sessions%rowtype; t public.recipe_draft_turns%rowtype; begin
    select * into s from public.recipe_draft_sessions where owner_id=p_owner_id and id=p_session_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    select * into t from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if t.state <> 'pending' or t.fencing_token is distinct from p_fencing_token or t.dispatch_state <> 'predispatch' or t.lease_expires_at <= now() then return jsonb_build_object('code','CLAIM_EXPIRED'); end if;
    if p_enabled is distinct from true or s.revision<>t.based_revision or s.effective_context_hash<>t.context_hash then
        return jsonb_build_object('turn',public.recipe_draft_settle(p_owner_id,p_session_id,p_request_id,jsonb_build_object('status',case when p_enabled is distinct from true then 'unavailable' else 'rejected' end,'code',case when p_enabled is distinct from true then 'PROVIDER_UNAVAILABLE' else 'STALE_REVISION' end),0));
    end if;
    update public.recipe_draft_turns set dispatch_state='dispatched_unknown' where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id returning * into t;
    update public.recipe_draft_sessions set dispatch_count=dispatch_count+1 where owner_id=p_owner_id and id=p_session_id;
    return jsonb_build_object('outcome','dispatched','turn',(to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text)));
end $$;

-- Frozen wire shape only; DEV283 remains responsible for extractive grounding.
create or replace function public.recipe_draft_result_valid(r jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare item jsonb; key text; ids jsonb; begin
    if r is null or jsonb_typeof(r)<>'object' or octet_length(r::text)>65536 then return false; end if;
    if r->>'status'='no_review_needed' then return (select count(*) from jsonb_object_keys(r))=1; end if;
    if r->>'status' in ('rejected','unavailable') then
        return (select count(*) from jsonb_object_keys(r))=2 and r->>'code' is not null
            and r->>'code' in ('INVALID_INPUT','INVALID_EVIDENCE','INVALID_REVIEW_PATH','INVALID_PROVIDER_OUTPUT','INPUT_BUDGET','OUTPUT_BUDGET','STALE_REVISION','PROVIDER_TIMEOUT','PROVIDER_UNAVAILABLE','PROVIDER_OUTCOME_UNKNOWN');
    end if;
    if r->>'status' is distinct from 'proposal' or r->>'origin' is distinct from 'AI_suggested'
        or r->'requires_approval' is distinct from 'true'::jsonb
        or jsonb_typeof(r->'questions') is distinct from 'array' or jsonb_typeof(r->'suggestions') is distinct from 'array'
        or jsonb_array_length(r->'questions')>3 or jsonb_array_length(r->'suggestions')>20
        or (select count(*) from jsonb_object_keys(r))<>5
        or (select count(distinct x) from jsonb_array_elements(r->'questions') x)<>jsonb_array_length(r->'questions')
        or (select count(distinct x) from jsonb_array_elements(r->'suggestions') x)<>jsonb_array_length(r->'suggestions') then return false; end if;
    for key in select unnest(array['questions','suggestions']) loop
        for item in select * from jsonb_array_elements(r->key) loop
            if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'path') is distinct from 'string'
                or item->>'path' !~ '^(title|servings|ingredients\[([0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[([0-9]|[1-9][0-9])\]\.instruction)$'
                    and not (key='questions' and item->>'path' in ('ingredients','steps')) then return false; end if;
            ids:=item->'evidence_ids';
            if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids) not between 1 and 60
                or (select count(distinct x) from jsonb_array_elements(ids) x)<>jsonb_array_length(ids)
                or exists(select 1 from jsonb_array_elements(ids) x where jsonb_typeof(x)<>'string' or (x #>> '{}') !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') then return false; end if;
            if key='questions' then
                if (select count(*) from jsonb_object_keys(item))<>3 or jsonb_typeof(item->'question') is distinct from 'string' or length(item->>'question') not between 1 and 300 then return false; end if;
            else
                if (select count(*) from jsonb_object_keys(item))<>4 or jsonb_typeof(item->'raw_value') is distinct from 'string' or length(item->>'raw_value') not between 1 and 1500
                    or jsonb_typeof(item->'reason') is distinct from 'string' or length(item->>'reason') not between 1 and 500 then return false; end if;
            end if;
        end loop;
    end loop;
    return true;
exception when others then return false;
end $$;

create or replace function public.finish_recipe_draft_turn(p_owner_id uuid,p_session_id uuid,p_request_id uuid,p_fencing_token uuid,p_result jsonb,p_validated_usage integer default null,p_expected_dispatch_state text default 'dispatched_unknown')
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.recipe_draft_sessions%rowtype; t public.recipe_draft_turns%rowtype; cost integer; result_value jsonb; begin
    select * into s from public.recipe_draft_sessions where owner_id=p_owner_id and id=p_session_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    select * into t from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if t.state <> 'pending' or t.fencing_token is distinct from p_fencing_token then return jsonb_build_object('code','CLAIM_EXPIRED'); end if;
    if p_expected_dispatch_state is null or p_expected_dispatch_state not in ('predispatch','dispatched_unknown') then return jsonb_build_object('code','INVALID_INPUT'); end if;
    if t.dispatch_state<>p_expected_dispatch_state then return jsonb_build_object('code','CLAIM_EXPIRED'); end if;
    if not public.recipe_draft_result_valid(p_result) then return jsonb_build_object('code','INVALID_INPUT'); end if;
    if t.dispatch_state='predispatch' and p_result->>'status'='proposal' then return jsonb_build_object('code','INVALID_INPUT'); end if;
    cost := case when t.dispatch_state='predispatch' then 0 when p_validated_usage between 0 and 4096 then p_validated_usage else 4096 end;
    result_value := p_result;
    if t.lease_expires_at <= now() then
        result_value := jsonb_build_object('status','unavailable','code',case when t.dispatch_state='predispatch' then 'PROVIDER_UNAVAILABLE' else 'PROVIDER_OUTCOME_UNKNOWN' end);
        cost := case when t.dispatch_state='predispatch' then 0 else 4096 end;
    elsif s.revision<>t.based_revision or s.effective_context_hash<>t.context_hash then
        result_value := jsonb_build_object('status','rejected','code','STALE_REVISION');
        cost := case when t.dispatch_state='predispatch' then 0 else 4096 end;
    end if;
    return jsonb_build_object('turn',public.recipe_draft_settle(p_owner_id,p_session_id,p_request_id,result_value,cost));
end $$;

create or replace function public.recover_recipe_draft_turn(p_owner_id uuid,p_session_id uuid,p_request_id uuid,p_enabled boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.recipe_draft_sessions%rowtype; t public.recipe_draft_turns%rowtype; begin
    select * into s from public.recipe_draft_sessions where owner_id=p_owner_id and id=p_session_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    select * into t from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if t.state='terminal' then return jsonb_build_object('outcome','replay','turn',(to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text))); end if;
    if p_enabled is distinct from true or t.lease_expires_at<=now() then
        if t.dispatch_state='dispatched_unknown' then return jsonb_build_object('turn',public.recipe_draft_settle(p_owner_id,p_session_id,p_request_id,'{"status":"unavailable","code":"PROVIDER_OUTCOME_UNKNOWN"}',4096)); end if;
        if p_enabled is distinct from true or s.revision<>t.based_revision or s.effective_context_hash<>t.context_hash then
            return jsonb_build_object('turn',public.recipe_draft_settle(p_owner_id,p_session_id,p_request_id,jsonb_build_object('status',case when p_enabled is distinct from true then 'unavailable' else 'rejected' end,'code',case when p_enabled is distinct from true then 'PROVIDER_UNAVAILABLE' else 'STALE_REVISION' end),0));
        end if;
        update public.recipe_draft_turns set fencing_token=gen_random_uuid(),lease_expires_at=now()+interval '30 seconds' where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id returning * into t;
    end if;
    return jsonb_build_object('turn',(to_jsonb(t) || jsonb_build_object('based_revision',t.based_revision::text)));
end $$;

create or replace function public.approve_recipe_draft_turn(
    p_owner_id uuid,p_session_id uuid,p_turn_request_id uuid,p_request_id uuid,
    p_expected_revision bigint,p_action text,p_selected_paths text[],p_approval_hash text,
    p_next_context jsonb,p_next_context_hash text,p_enabled boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.recipe_draft_sessions%rowtype; t public.recipe_draft_turns%rowtype;
    a public.recipe_draft_approvals%rowtype; body jsonb; next_fields jsonb; next_overlay jsonb;
    path text; suggestion jsonb; current_field jsonb; new_field jsonb; flag text;
    expected_flags jsonb := '[]'; group_prefix text; receipt_value jsonb;
begin
    if p_enabled is distinct from true then return jsonb_build_object('code','DRAFT_DISABLED'); end if;
    if cardinality(p_selected_paths)>0 and array_ndims(p_selected_paths)<>1 then return jsonb_build_object('code','INVALID_INPUT'); end if;
    if p_request_id is null or p_turn_request_id is null or p_expected_revision is null or p_expected_revision<=0
        or p_action is null or p_action not in ('accept','reject') or p_selected_paths is null
        or array_position(p_selected_paths,null) is not null
        or p_approval_hash is null or p_approval_hash !~ '^[a-f0-9]{64}$' then return jsonb_build_object('code','INVALID_INPUT'); end if;
    select * into s from public.recipe_draft_sessions where owner_id=p_owner_id and id=p_session_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    body:=jsonb_build_object('request_id',p_request_id,'expected_revision',p_expected_revision::text,'action',p_action,'selected_paths',to_jsonb(p_selected_paths));
    select * into a from public.recipe_draft_approvals where owner_id=p_owner_id and session_id=p_session_id and request_id=p_request_id;
    if found then
        if a.turn_request_id<>p_turn_request_id or a.approval_hash<>p_approval_hash or a.approval_body<>body then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT'); end if;
        return jsonb_build_object('receipt',a.receipt,'outcome','replay');
    end if;
    select * into t from public.recipe_draft_turns where owner_id=p_owner_id and session_id=p_session_id and request_id=p_turn_request_id for update;
    if not found then return jsonb_build_object('code','NOT_FOUND'); end if;
    if exists(select 1 from public.recipe_draft_approvals where owner_id=p_owner_id and session_id=p_session_id and turn_request_id=p_turn_request_id) then return jsonb_build_object('code','TURN_ALREADY_DECIDED'); end if;
    if s.revision<>p_expected_revision or s.revision<>t.based_revision or s.effective_context_hash<>t.context_hash then return jsonb_build_object('code','STALE_REVISION'); end if;
    if s.revision=9223372036854775807 then return jsonb_build_object('code','REVISION_EXHAUSTED'); end if;
    if t.state<>'terminal' or t.result->>'status' is distinct from 'proposal' then return jsonb_build_object('code','INVALID_INPUT'); end if;
    if not public.recipe_draft_context_valid(p_next_context) or p_next_context_hash is null or p_next_context_hash !~ '^[a-f0-9]{64}$'
        or cardinality(p_selected_paths)<>(select count(distinct x) from unnest(p_selected_paths) x)
        or (p_action='accept' and cardinality(p_selected_paths) not between 1 and 20)
        or (p_action='reject' and cardinality(p_selected_paths)<>0) then return jsonb_build_object('code','INVALID_INPUT'); end if;
    next_fields:=s.effective_context->'fields'; next_overlay:=s.overlay;
    if p_action='accept' then
        if jsonb_typeof(t.result->'suggestions') is distinct from 'array' or jsonb_array_length(t.result->'suggestions')>20 then return jsonb_build_object('code','INVALID_INPUT'); end if;
        foreach path in array p_selected_paths loop
            select value into suggestion from jsonb_array_elements(t.result->'suggestions') where value->>'path'=path;
            current_field:=next_fields->path;
            if suggestion is null or current_field->>'user_confirmed'='true'
                or (current_field is null and not exists(select 1 from jsonb_array_elements_text(s.effective_context->'review_fields') f where f=path))
                or jsonb_typeof(suggestion->'raw_value') is distinct from 'string'
                or jsonb_typeof(suggestion->'evidence_ids') is distinct from 'array'
                or not exists(select 1 from jsonb_array_elements_text(s.effective_context->'review_fields') f where f=path or (f in ('ingredients','steps') and path like f||'[%')) then return jsonb_build_object('code','INVALID_INPUT'); end if;
            -- Persisted proposal is validated by DEV283; these are authorization projections only.
            new_field:=coalesce(current_field,'{}'::jsonb) || jsonb_build_object('raw_value',suggestion->'raw_value','evidence_ids',suggestion->'evidence_ids','origin','AI_suggested','user_confirmed',true);
            next_fields:=jsonb_set(next_fields,array[path],new_field,true);
            next_overlay:=jsonb_set(next_overlay,array[path],jsonb_build_object('raw_value',suggestion->'raw_value','evidence_ids',suggestion->'evidence_ids','origin','AI_suggested','user_confirmed',true,'confirmed_revision',(s.revision+1)::text),true);
        end loop;
    end if;
    -- Only selected exact gaps or groups with real fields and no remaining gap resolve.
    for flag in select * from jsonb_array_elements_text(s.effective_context->'review_fields') loop
        if p_action='accept' and flag=any(p_selected_paths) then continue; end if;
        if p_action='accept' and flag in ('ingredients','steps')
            and exists(select 1 from jsonb_each(next_fields) f where f.key like flag||'[%')
            and not exists(select 1 from jsonb_each(next_fields) f where f.key like flag||'[%' and f.value->>'user_confirmed' is distinct from 'true')
            and not exists(select 1 from jsonb_array_elements_text(s.effective_context->'review_fields') f where f like flag||'[%' and next_fields->f->>'user_confirmed' is distinct from 'true')
            and exists(select 1 from unnest(p_selected_paths) x where x like flag||'[%') then continue; end if;
        expected_flags:=expected_flags || to_jsonb(flag);
    end loop;
    if p_next_context->'fields'<>next_fields or p_next_context->'evidence'<>s.effective_context->'evidence'
        or p_next_context->'review_fields'<>expected_flags
        or (p_action='reject' and p_next_context<>s.effective_context)
        or (p_action='accept' and p_next_context->>'status'<>case when jsonb_array_length(expected_flags)=0 then 'ready' else 'needs_review' end) then return jsonb_build_object('code','INVALID_INPUT'); end if;
    receipt_value:=jsonb_build_object('request_id',p_request_id,'turn_request_id',p_turn_request_id,'action',p_action,'selected_paths',to_jsonb(p_selected_paths),'session_id',p_session_id,'applied_revision',(s.revision+1)::text);
    update public.recipe_draft_sessions set revision=revision+1,effective_context=p_next_context,effective_context_hash=p_next_context_hash,overlay=next_overlay,updated_at=now() where owner_id=p_owner_id and id=p_session_id;
    insert into public.recipe_draft_approvals(owner_id,session_id,request_id,turn_request_id,approval_body,approval_hash,action,selected_paths,applied_revision,receipt)
    values(p_owner_id,p_session_id,p_request_id,p_turn_request_id,body,p_approval_hash,p_action,p_selected_paths,s.revision+1,receipt_value);
    return jsonb_build_object('receipt',receipt_value);
end $$;

-- A job cascade prelocks all dependent sessions/turns before any owner-day budget.
create or replace function public.recipe_draft_before_job_delete() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    perform 1 from public.recipe_draft_sessions where job_id=old.id and owner_id=old.owner_id order by id for update;
    perform 1 from public.recipe_draft_turns t where t.owner_id=old.owner_id and t.session_id in
        (select id from public.recipe_draft_sessions where job_id=old.id and owner_id=old.owner_id)
        order by t.session_id,t.request_id for update;
    perform 1 from public.recipe_draft_owner_budgets b where b.owner_id=old.owner_id and b.utc_date in
        (select t.budget_date from public.recipe_draft_turns t join public.recipe_draft_sessions s on s.id=t.session_id and s.owner_id=t.owner_id
         where s.job_id=old.id and s.owner_id=old.owner_id and t.state='pending') order by b.utc_date for update;
    return old;
end $$;
drop trigger if exists recipe_draft_job_delete_locks on public.recipe_import_jobs;
create trigger recipe_draft_job_delete_locks before delete on public.recipe_import_jobs for each row execute function public.recipe_draft_before_job_delete();

create or replace function public.recipe_draft_before_session_delete() returns trigger
language plpgsql security definer set search_path='' as $$
declare t public.recipe_draft_turns%rowtype; cost integer; begin
    -- Parent row deletion already holds the session lock. Lock all turns before budgets.
    perform 1 from public.recipe_draft_turns where owner_id=old.owner_id and session_id=old.id order by request_id for update;
    perform 1 from public.recipe_draft_owner_budgets b where b.owner_id=old.owner_id
        and b.utc_date in (select budget_date from public.recipe_draft_turns where owner_id=old.owner_id and session_id=old.id and state='pending') order by b.utc_date for update;
    for t in select * from public.recipe_draft_turns where owner_id=old.owner_id and session_id=old.id and state='pending' order by budget_date,request_id loop
        cost:=case when t.dispatch_state='dispatched_unknown' then 4096 else 0 end;
        update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens-t.reserved_tokens,settled_tokens=settled_tokens+cost where owner_id=old.owner_id and utc_date=t.budget_date;
    end loop;
    return old;
end $$;
drop trigger if exists recipe_draft_delete_settlement on public.recipe_draft_sessions;
create trigger recipe_draft_delete_settlement before delete on public.recipe_draft_sessions for each row execute function public.recipe_draft_before_session_delete();

-- Also revoke helpers: SECURITY DEFINER is never an invitation to PUBLIC execution.
do $$ declare fn record; begin
    for fn in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace
        and proname in ('create_recipe_draft_session','claim_recipe_draft_turn','mark_recipe_draft_turn_dispatched','finish_recipe_draft_turn','recover_recipe_draft_turn','approve_recipe_draft_turn','recipe_draft_context_valid','recipe_draft_result_valid','recipe_draft_settle','recipe_draft_before_session_delete','recipe_draft_before_job_delete') loop
        execute format('revoke all on function %s from public,anon,authenticated,service_role',fn.signature);
        if fn.signature::text ~ '^(public\.)?(create|claim|mark|finish|recover|approve)_recipe_draft_' then
            execute format('grant execute on function %s to service_role',fn.signature);
        end if;
    end loop;
end $$;
