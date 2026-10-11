// Developer: gengyun
// Purpose: Verify seven offline owner draft flows using real HTTP/dispatch source and PostgreSQL RPCs.
import assert from 'node:assert/strict';
import { before, after, test } from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { pgmq } from '@electric-sql/pglite-pgmq';
import { handleRequest } from '../../functions/recipe-draft-sessions/handler.ts';
import { canonicalHash } from '../../functions/recipe-draft-sessions/canonicalJSON.ts';
import { createAIDraftDispatchWorker } from '../../functions/recipe-import-worker/aiDraftDispatch.ts';

const root = new URL('../../', import.meta.url);
const sql = path => readFile(new URL(path, root), 'utf8');
let db, sourceFixture, assertions = 0;
const eq = (actual, expected) => { assert.deepEqual(actual, expected); assertions++; };
const query = async (text, parameters=[]) => (await db.query(text, parameters)).rows;
const signatures = {
  create_recipe_draft_session: ['p_owner_id','p_client_request_id','p_job_id','p_expected_job_result','p_base_context','p_base_context_hash','p_enabled'],
  claim_recipe_draft_turn: ['p_owner_id','p_session_id','p_request_id','p_expected_revision','p_message','p_request_hash','p_context_hash','p_enabled'],
  mark_recipe_draft_turn_dispatched: ['p_owner_id','p_session_id','p_request_id','p_fencing_token','p_enabled'],
  finish_recipe_draft_turn: ['p_owner_id','p_session_id','p_request_id','p_fencing_token','p_result','p_validated_usage','p_expected_dispatch_state'],
  recover_recipe_draft_turn: ['p_owner_id','p_session_id','p_request_id','p_enabled'],
  approve_recipe_draft_turn: ['p_owner_id','p_session_id','p_turn_request_id','p_request_id','p_expected_revision','p_action','p_selected_paths','p_approval_hash','p_next_context','p_next_context_hash','p_enabled'],
};
async function rpc(name,args) {
  assert(Object.hasOwn(signatures,name), 'RPC name must be explicitly allowed');
  eq(Object.keys(args).sort(), [...signatures[name]].sort());
  const names=signatures[name];
  // Names are constants, values are parameters. These execute the actual migration functions.
  return (await query(`select public.${name}(${names.map((n,i)=>`${n} => $${i+1}`).join(',')}) as value`,names.map(n=>args[n])))[0].value;
}
const owned = async (table,predicate,args,revision) => (await query(
  `select to_jsonb(r)${revision?` || jsonb_build_object('${revision}',r.${revision}::text)`:''} as value from public.${table} r where ${predicate}`,args))[0]?.value ?? null;
const sessionRow=(owner,id)=>owned('recipe_draft_sessions','owner_id=$1 and id=$2',[owner,id],'revision');
const turnRow=(owner,sid,rid)=>owned('recipe_draft_turns','owner_id=$1 and session_id=$2 and request_id=$3',[owner,sid,rid],'based_revision');
const budget=async owner=>(await query('select settled_tokens,reserved_tokens from public.recipe_draft_owner_budgets where owner_id=$1 order by utc_date',[owner]));
const configuration=()=>({
  route:{route_key:'recipe_import_draft_v1',primary_model_id:'m',enabled:true,timeout_ms:10000,max_retries:0,max_output_tokens:1000,temperature:null},
  model:{id:'m',provider_id:'p',upstream_model_id:'synthetic-model',display_name:'Synthetic',enabled:true,created_at:'2026-01-01T00:00:00Z'},
  provider:{id:'p',name:'Synthetic',base_url:'https://synthetic.invalid/v1',secret_ref:'synthetic-ref',enabled:true,updated_at:'2026-01-01T00:00:00Z'},
});
before(async()=>{
  // One shared engine, sequential cases with independent owners; no connection string is accepted.
  db=new PGlite({extensions:{pgmq}});
  await db.exec('create extension pgmq;');
  await db.exec(await sql('tests/isolated/bootstrap.sql'));
  for(const file of ['20261007_user_snapshots.sql','20261008155000_recipe_import_jobs_v1.sql'])await db.exec(await sql('migrations/'+file));
  const migrations=(await readdir(new URL('migrations/',root))).filter(f=>/^\d{14}_recipe_draft_sessions_v1\.sql$/.test(f));
  eq(migrations.length,1);await db.exec(await sql('migrations/'+migrations[0]));
  const examples=JSON.parse(await readFile(new URL('../../../docs/import-fixtures/contract-examples.json',import.meta.url),'utf8'));
  sourceFixture=examples.cases.find(c=>c.schema==='JobResponse' && c.valid && c.data.status==='completed').data.result;
});
after(async()=>{await db?.close();console.log(`LOCAL INTEGRATION: 7 flows, ${assertions} assertions; real JWT/network/provider/multi-connection/Native NOT RUN.`);});

async function fixture({ready=false,usage=25}={}) {
  const owner=randomUUID(), foreign=randomUUID(), job=randomUUID();
  await query('insert into auth.users(id) values ($1),($2)',[owner,foreign]);
  const result=structuredClone(sourceFixture);
  result.recipe_id=randomUUID();result.candidate_recipes=[];
  // The source fixture already contains normalized metadata, user edits and genuine review gaps.
  const replacement=new Map(result.evidence.map(e=>[e.id,randomUUID()]));
  for(const e of result.evidence)e.id=replacement.get(e.id);
  for(const field of Object.values(result.fields))field.evidence_ids=field.evidence_ids.map(id=>replacement.get(id));
  result.review_fields=['ingredients',...result.review_fields];
  if(ready){
    result.status='ready';result.review_fields=[];
    for(const field of Object.values(result.fields)){field.user_confirmed=true;field.origin='user';}
  }
  await query(`insert into public.recipe_import_jobs(id,owner_id,client_request_id,input_type,source_value,source_fingerprint,status,stage,recipe_id,recipe_status,review_count,result,completed_at)
    values ($1,$2,$3,'url',$4,$5,'completed','done',$6,$7,$8,$9,now())`,[job,owner,randomUUID(),result.source.original_url,'synthetic-source:'+job,result.recipe_id,result.status,result.review_fields.length,result]);
  await query(`insert into public.user_snapshots(user_id,payload,client_updated_at) values ($1,$2,now())`,[owner,{private:'synthetic private journal',recipes:[{id:result.recipe_id}]}]);
  const f={owner,foreign,job,result,transportCount:0,routeCount:0,secretCount:0,rpcCalls:[]};
  const bridge=async(name,args)=>{f.rpcCalls.push({name,args:structuredClone(args)});return rpc(name,args);};
  const deps={
    // Synthetic verified owner boundary, NOT a real JWT verifier.
    verifiedOwner:async request=>{const id=request.headers.get('authorization')?.replace(/^Bearer /,'');return id===owner||id===foreign?{id,isAnonymous:false}:null;},
    isEnabled:()=>true,
    loadOwnedJob:(o,j)=>owned('recipe_import_jobs','owner_id=$1 and id=$2',[o,j]),
    loadOwnedSession:sessionRow,
    loadOwnedSessionByCreationKey:(o,key)=>owned('recipe_draft_sessions','owner_id=$1 and client_request_id=$2',[o,key],'revision'),
    loadOwnedTurn:turnRow,
    loadOwnedApprovalForTurn:(o,sid,rid)=>owned('recipe_draft_approvals','owner_id=$1 and session_id=$2 and turn_request_id=$3',[o,sid,rid],'applied_revision'),
    rpc:bridge,
  };
  f.http=async(method,path,body,as=owner)=>{
    const response=await handleRequest(new Request('https://synthetic.invalid'+path,{method,headers:{authorization:'Bearer '+as,'content-type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})}),deps);
    return {status:response.status,body:await response.json()};
  };
  const amount=result.fields['ingredients[0].amount'];
  f.inner={questions:[{path:'ingredients',question:'Which ingredient amount needs review?',evidence_ids:amount.evidence_ids}],suggestions:[{path:'ingredients[0].amount',raw_value:amount.raw_value,evidence_ids:amount.evidence_ids,reason:'Original source wording'}]};
  f.worker=(sid,rid)=>createAIDraftDispatchWorker({enabled:true,
    storage:async(name,args,{signal})=>{signal.throwIfAborted();return bridge(name,args);},
    loadRouteConfiguration:async signal=>{signal.throwIfAborted();f.routeCount++;return configuration();},
    resolveSecret:async(ref,signal)=>{signal.throwIfAborted();eq(ref,'synthetic-ref');f.secretCount++;return 'synthetic-secret-not-a-key';},
    safeTransport:async(request,{signal,maxResponseBytes})=>{
      signal.throwIfAborted();eq(maxResponseBytes,65536);eq(request.url,'https://synthetic.invalid/v1/chat/completions');
      const durable=await turnRow(owner,sid,rid);eq(durable.state,'pending');eq(durable.dispatch_state,'dispatched_unknown');eq(durable.reserved_tokens,4096);
      f.transportCount++;
      return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{role:'assistant',content:JSON.stringify(f.inner)}}],usage:{total_tokens:usage}}),{headers:{'content-type':'application/json'}});
    },outerTimeoutMs:10000,
  });
  f.create=async()=>{const body={job_id:job,client_request_id:randomUUID()};const response=await f.http('POST','/recipe-draft-sessions',body);eq(response.status,201);return {sid:response.body.session_id,body,session:response.body};};
  f.claim=async(sid,revision='1',requestID=randomUUID(),message='Keep the original evidence wording.')=>{
    const body={request_id:requestID,expected_revision:revision,message};return {response:await f.http('POST',`/recipe-draft-sessions/${sid}/turns`,body),body};
  };
  f.run=(sid,rid,as=owner)=>f.worker(sid,rid).runTurn({ownerID:as,sessionID:sid,requestID:rid});
  f.approve=async(sid,rid)=>{
    const body={request_id:randomUUID(),expected_revision:'1',action:'accept',selected_paths:['ingredients[0].amount']};
    const response=await f.http('POST',`/recipe-draft-sessions/${sid}/turns/${rid}/approval`,body);eq(response.status,200);return {response,body};
  };
  return f;
}

test('1. create → pending → dispatch → poll → approve → stable replay with real hashes',async()=>{
  const f=await fixture();const originalJob=await owned('recipe_import_jobs','id=$1',[f.job]);const privateBefore=await query('select * from public.user_snapshots where user_id=$1',[f.owner]);
  const {sid,body:createBody}=await f.create();const {response,body}=await f.claim(sid);eq(response.status,202);eq(response.body.state,'pending');eq(await budget(f.owner),[{settled_tokens:0,reserved_tokens:4096}]);
  const stored=await turnRow(f.owner,sid,body.request_id);eq(stored.request_hash,await canonicalHash(body));
  const s=await sessionRow(f.owner,sid);const c=s.base_context;
  eq(s.base_context_hash,await canonicalHash({job_id:f.job,source_fingerprint:s.source_fingerprint,revision:'1',context:{status:c.status,fields:c.fields,evidence:c.evidence,reviewFields:c.review_fields}}));
  const dispatched=await f.run(sid,body.request_id);eq(dispatched.state,'terminal');eq(dispatched.result.status,'proposal');eq(f.transportCount,1);
  const polled=await f.http('GET',`/recipe-draft-sessions/${sid}/turns/${body.request_id}`);eq(polled.status,200);eq(polled.body.result.questions[0].path,'ingredients');eq(polled.body.decision,null);
  eq(await budget(f.owner),[{settled_tokens:25,reserved_tokens:0}]);
  const approval=await f.approve(sid,body.request_id);eq(approval.response.body.applied_revision,'2');
  const current=await f.http('GET',`/recipe-draft-sessions/${sid}`);eq(current.status,200);eq(current.body.revision,'2');eq(current.body.overlay['ingredients[0].amount'].origin,'AI_suggested');eq(current.body.overlay['ingredients[0].amount'].user_confirmed,true);
  const turnReplay=await f.http('POST',`/recipe-draft-sessions/${sid}/turns`,body);eq(turnReplay.status,200);eq(turnReplay.body.result,polled.body.result);eq(turnReplay.body.decision,approval.response.body);
  eq((await f.http('POST',`/recipe-draft-sessions/${sid}/turns/${body.request_id}/approval`,approval.body)).body,approval.response.body);
  eq((await f.http('POST','/recipe-draft-sessions',createBody)).status,200);
  eq((await f.run(sid,body.request_id)).result,polled.body.result);eq(f.transportCount,1);eq(await budget(f.owner),[{settled_tokens:25,reserved_tokens:0}]);
  eq(await owned('recipe_import_jobs','id=$1',[f.job]),originalJob);eq(await query('select * from public.user_snapshots where user_id=$1',[f.owner]),privateBefore);
});

test('2. complete ready job commits no-review turn without provider/config/secret work',async()=>{
  const f=await fixture({ready:true});const {sid}=await f.create();const {response,body}=await f.claim(sid);eq(response.status,200);eq(response.body.result,{status:'no_review_needed'});
  eq((await f.run(sid,body.request_id)).result,{status:'no_review_needed'});eq(f.transportCount,0);eq(f.routeCount,0);eq(f.secretCount,0);eq(await budget(f.owner),[]);eq((await sessionRow(f.owner,sid)).dispatch_count,0);
});

test('3. foreign and unknown HTTP/worker identifiers preserve existing private state',async()=>{
  const f=await fixture();const {sid}=await f.create();const {body}=await f.claim(sid);const before=await turnRow(f.owner,sid,body.request_id);const balances=await budget(f.owner);
  for(const path of [`/recipe-draft-sessions/${sid}`,`/recipe-draft-sessions/${sid}/turns/${body.request_id}`]){
    const foreign=await f.http('GET',path,undefined,f.foreign);const unknown=await f.http('GET',`/recipe-draft-sessions/${randomUUID()}`,undefined,f.foreign);eq(foreign.status,404);eq(unknown.status,404);eq(foreign.body.code,unknown.body.code);eq(foreign.body.message,unknown.body.message);
  }
  eq((await f.run(sid,body.request_id,f.foreign)).code,'NOT_FOUND');eq(f.transportCount,0);eq(await turnRow(f.owner,sid,body.request_id),before);eq(await budget(f.owner),balances);
});

test('4. independent workers share real CAS and old request replay survives approval revision',async()=>{
  const f=await fixture();const {sid}=await f.create();const {body}=await f.claim(sid);
  const results=await Promise.all([f.run(sid,body.request_id),f.run(sid,body.request_id)]);eq(f.transportCount,1);eq(results.some(r=>r.state==='terminal'),true);
  const markers=f.rpcCalls.filter(c=>c.name==='mark_recipe_draft_turn_dispatched');eq(markers.length,2);eq(markers[0].args.p_fencing_token,markers[1].args.p_fencing_token);eq(f.rpcCalls.filter(c=>c.name==='finish_recipe_draft_turn').length,1);
  const polled=await f.http('GET',`/recipe-draft-sessions/${sid}/turns/${body.request_id}`);eq(polled.body.result.status,'proposal');eq(await budget(f.owner),[{settled_tokens:25,reserved_tokens:0}]);
  const conflict=await f.http('POST',`/recipe-draft-sessions/${sid}/turns`,{...body,message:'Changed'});eq(conflict.status,409);eq(conflict.body.code,'IDEMPOTENCY_CONFLICT');
  const approval=await f.approve(sid,body.request_id);const replay=await f.http('POST',`/recipe-draft-sessions/${sid}/turns`,body);eq(replay.status,200);eq(replay.body.result,polled.body.result);eq(replay.body.decision,approval.response.body);
  const stale=await f.claim(sid);eq(stale.response.status,409);eq(stale.response.body.code,'STALE_REVISION');eq(f.transportCount,1);eq(await budget(f.owner),[{settled_tokens:25,reserved_tokens:0}]);
});

test('5. committed unknown dispatch recovers full budget once without resend or late replacement',async()=>{
  const f=await fixture();const {sid}=await f.create();const {body}=await f.claim(sid);const t=await turnRow(f.owner,sid,body.request_id);
  const marker=await rpc('mark_recipe_draft_turn_dispatched',{p_owner_id:f.owner,p_session_id:sid,p_request_id:body.request_id,p_fencing_token:t.fencing_token,p_enabled:true});eq(marker.outcome,'dispatched');
  await query(`update public.recipe_draft_turns set lease_expires_at=now()-interval '1 second' where owner_id=$1 and session_id=$2 and request_id=$3`,[f.owner,sid,body.request_id]);
  const recovered=await f.run(sid,body.request_id);eq(recovered.result,{status:'unavailable',code:'PROVIDER_OUTCOME_UNKNOWN'});eq(f.transportCount,0);eq(await budget(f.owner),[{settled_tokens:4096,reserved_tokens:0}]);
  const replay=await f.http('POST',`/recipe-draft-sessions/${sid}/turns`,body);eq(replay.status,200);eq(replay.body.result,recovered.result);
  eq((await f.run(sid,body.request_id)).result,recovered.result);
  const late=await rpc('finish_recipe_draft_turn',{p_owner_id:f.owner,p_session_id:sid,p_request_id:body.request_id,p_fencing_token:t.fencing_token,p_result:{status:'no_review_needed'},p_validated_usage:0,p_expected_dispatch_state:'dispatched_unknown'});eq(late.code,'CLAIM_EXPIRED');eq(await budget(f.owner),[{settled_tokens:4096,reserved_tokens:0}]);
});

test('6. real dispatches exhaust shared owner quota and session deletion does not refund it',async()=>{
  const f=await fixture({usage:4096});const sessions=[];
  for(let s=0;s<2;s++){
    const {sid}=await f.create();sessions.push(sid);
    for(let i=0;i<8;i++){const {response,body}=await f.claim(sid);eq(response.status,202);eq((await f.run(sid,body.request_id)).result.status,'proposal');}
    eq((await sessionRow(f.owner,sid)).dispatch_count,8);
  }
  eq(f.transportCount,16);eq(await budget(f.owner),[{settled_tokens:65536,reserved_tokens:0}]);
  const {sid}=await f.create();const exhausted=await f.claim(sid);eq(exhausted.response.status,429);eq(exhausted.response.body.code,'BUDGET_EXHAUSTED');
  await query('delete from public.recipe_draft_sessions where owner_id=$1 and id=$2',[f.owner,sessions[0]]);
  const stillExhausted=await f.claim(sid);eq(stillExhausted.response.status,429);eq(stillExhausted.response.body.code,'BUDGET_EXHAUSTED');eq(f.transportCount,16);eq(await budget(f.owner),[{settled_tokens:65536,reserved_tokens:0}]);
});

test('7. job cascade settles unknown, releases predispatch and preserves unrelated source/private rows',async()=>{
  const f=await fixture();const sentinel=await fixture();const jobBefore=await owned('recipe_import_jobs','id=$1',[sentinel.job]);const snapshotsBefore=await query('select * from public.user_snapshots where user_id in ($1,$2) order by user_id',[f.owner,sentinel.owner]);
  const a=await f.create(), b=await f.create();const pending=await f.claim(a.sid), unknown=await f.claim(b.sid);const t=await turnRow(f.owner,b.sid,unknown.body.request_id);
  await rpc('mark_recipe_draft_turn_dispatched',{p_owner_id:f.owner,p_session_id:b.sid,p_request_id:unknown.body.request_id,p_fencing_token:t.fencing_token,p_enabled:true});eq(await budget(f.owner),[{settled_tokens:0,reserved_tokens:8192}]);
  await query('delete from public.recipe_import_jobs where owner_id=$1 and id=$2',[f.owner,f.job]);
  eq(await budget(f.owner),[{settled_tokens:4096,reserved_tokens:0}]);eq((await f.http('GET',`/recipe-draft-sessions/${a.sid}`)).status,404);eq((await f.http('GET',`/recipe-draft-sessions/${b.sid}`)).status,404);
  eq((await f.run(a.sid,pending.body.request_id)).code,'NOT_FOUND');eq((await f.run(b.sid,unknown.body.request_id)).code,'NOT_FOUND');eq(f.transportCount,0);
  eq(await owned('recipe_import_jobs','id=$1',[sentinel.job]),jobBefore);eq(await query('select * from public.user_snapshots where user_id in ($1,$2) order by user_id',[f.owner,sentinel.owner]),snapshotsBefore);
});
