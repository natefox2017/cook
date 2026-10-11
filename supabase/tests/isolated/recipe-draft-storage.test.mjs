// Developer: gengyun
// Purpose: Exercise real disposable PostgreSQL DEV-293 storage without network/credentials.
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { PGlite } from '@electric-sql/pglite';
import { pgtap } from '@electric-sql/pglite-pgtap';
import { pgmq } from '@electric-sql/pglite-pgmq';
const root = new URL('../../', import.meta.url);
const sql = p => readFile(new URL(p, root), 'utf8');
const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const E = '33333333-3333-4333-8333-333333333333';
const H = 'a'.repeat(64), H2 = 'b'.repeat(64);
const context = { status: 'needs_review', fields: {
  title: { raw_value: null, evidence_ids: [E], user_confirmed: false, origin: 'extracted' },
  servings: { raw_value: '2', evidence_ids: [E], user_confirmed: false, origin: 'extracted' },
}, evidence: [{ id: E, excerpt: 'Soup serves 2' }], review_fields: ['title', 'servings'] };
const proposal = { status: 'proposal', origin: 'AI_suggested', requires_approval: true,
  questions: [], suggestions: [{ path: 'title', raw_value: 'Soup', evidence_ids: [E], reason: 'Source' }] };

test('DEV-293 fresh/reapply/rollback, real ACL and transaction contract', async () => {
  const db = new PGlite({ extensions: { pgtap, pgmq } });
  let assertions = 0;
  const eq = (a,b) => { assert.deepEqual(a,b); assertions++; };
  const query = async (q,p=[]) => (await db.query(q,p)).rows;
  const rpc = async (name,args) => (await query(`select public.${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) as value`,args))[0].value;
  const row = async (table, where='true', p=[]) => (await query(`select * from public.${table} where ${where}`,p))[0];
  const code = async (name,args,expected) => eq((await rpc(name,args)).code,expected);
  const create = async (job,c=context,owner=A,key=randomUUID()) => rpc('create_recipe_draft_session',[owner,key,job,{fixture:'original'},c,H,true]);
  const claim = (sid,id=randomUUID(),rev=1,msg='review',hash=H,owner=A,ctxhash=H) => rpc('claim_recipe_draft_turn',[owner,sid,id,rev,msg,hash,ctxhash,true]);
  const mark = t => rpc('mark_recipe_draft_turn_dispatched',[A,t.session_id,t.request_id,t.fencing_token,true]);
  const finish = (t,result=proposal,usage=null,state='dispatched_unknown') => rpc('finish_recipe_draft_turn',[A,t.session_id,t.request_id,t.fencing_token,result,usage,state]);
  const expire = t => query(`update public.recipe_draft_turns set lease_expires_at=now()-interval '1 second' where session_id=$1 and request_id=$2`,[t.session_id,t.request_id]);
  const budget = async date => row('recipe_draft_owner_budgets',date?'owner_id=$1 and utc_date=$2':'owner_id=$1',[A,...(date?[date]:[])]);
  try {
    await db.exec('create extension pgtap; create extension pgmq;');
    await db.exec(await sql('tests/isolated/bootstrap.sql'));
    for (const f of ['20261007_user_snapshots.sql','20261008155000_recipe_import_jobs_v1.sql']) await db.exec(await sql('migrations/'+f));
    const files = (await readdir(new URL('migrations/',root))).filter(f=>/^\d{14}_recipe_draft_sessions_v1\.sql$/.test(f)); eq(files.length,1);
    const migration = await sql('migrations/'+files[0]);
    await db.exec(migration);
    await query('insert into auth.users(id) values ($1),($2)',[A,B]);
    const job = randomUUID();
    await query(`insert into public.recipe_import_jobs(id,owner_id,client_request_id,input_type,source_value,source_fingerprint,status,result) values ($1,$2,$3,'text','synthetic original','original-hash','completed',$4)`,[job,A,randomUUID(),{fixture:'original'}]);
    await query(`insert into public.user_snapshots(user_id,payload,client_updated_at) values ($1,'{"private":"unchanged"}',now())`,[A]);
    const privateBefore = await query('select * from public.user_snapshots');
    const jobBefore = await query('select * from public.recipe_import_jobs');
    const key=randomUUID(); const made=await create(job,context,A,key); const sid=made.session.id;
    eq(made.session.revision,'1');
    eq(made.outcome,'created'); eq(made.session.source_fingerprint,'original-hash');
    const tap = await db.exec(await sql('tests/isolated/fixtures/recipe_draft_sessions_v1.sql'));
    const lines=tap.flatMap(r=>r.rows.flatMap(Object.values)).filter(x=>typeof x==='string').flatMap(x=>x.split('\n'));
    assert(!lines.some(x=>/^(not ok|Bail out!|# Looks like)/.test(x)),lines.join('\n'));
    eq(lines.filter(x=>/^ok \d+/.test(x)).length,20); eq(lines.includes('1..20'),true);
    eq((await create(job,context,A,key)).session.id,sid);
    await code('create_recipe_draft_session',[A,key,randomUUID(),{},context,H,true],'IDEMPOTENCY_CONFLICT');
    await code('create_recipe_draft_session',[B,randomUUID(),job,{fixture:'original'},context,H,true],'NOT_FOUND');
    await code('create_recipe_draft_session',[A,randomUUID(),job,{fixture:'changed'},context,H,true],'STALE_REVISION');
    await code('create_recipe_draft_session',[A,randomUUID(),job,{fixture:'original'},context,H,false],'DRAFT_DISABLED');
    const bad=structuredClone(context);delete bad.status;
    await code('create_recipe_draft_session',[A,randomUUID(),job,{fixture:'original'},bad,H,true],'INVALID_INPUT');
    const t=(await claim(sid)).turn; eq(t.reserved_tokens,4096);
    eq((await claim(sid,t.request_id)).turn,t);
    await code('claim_recipe_draft_turn',[A,sid,t.request_id,1,'different',H,H,true],'IDEMPOTENCY_CONFLICT');
    await code('claim_recipe_draft_turn',[B,sid,randomUUID(),1,'review',H,H,true],'NOT_FOUND');
    await code('claim_recipe_draft_turn',[A,sid,randomUUID(),2,'review',H,H,true],'STALE_REVISION');
    eq((await budget()).reserved_tokens,4096);
    await code('mark_recipe_draft_turn_dispatched',[A,sid,t.request_id,randomUUID(),true],'CLAIM_EXPIRED');
    eq((await mark(t)).outcome,'dispatched');
    await code('mark_recipe_draft_turn_dispatched',[A,sid,t.request_id,t.fencing_token,true],'CLAIM_EXPIRED');
    eq((await finish(t,proposal,100)).turn.settled_tokens,100);eq((await budget()).reserved_tokens,0);
    await code('finish_recipe_draft_turn',[A,sid,t.request_id,t.fencing_token,proposal,0],'CLAIM_EXPIRED');
    const next=structuredClone(context);next.fields.title={raw_value:'Soup',evidence_ids:[E],user_confirmed:true,origin:'AI_suggested'};next.review_fields=['servings'];
    const approvalID=randomUUID();
    const approve=(ctx=next,action='accept',paths=['title'],id=approvalID,rev=1,hash=H2)=>rpc('approve_recipe_draft_turn',[A,sid,t.request_id,id,rev,action,paths,hash,ctx,H2,true]);
    for (const mutate of [c=>c.review_fields=[],c=>c.fields.servings.raw_value='999',c=>c.evidence[0].excerpt='changed']) {
      const invalid=structuredClone(next);mutate(invalid);eq((await approve(invalid)).code,'INVALID_INPUT');eq((await row('recipe_draft_sessions','id=$1',[sid])).revision,1);
    }
    eq((await query(`select public.approve_recipe_draft_turn($1,$2,$3,$4,1,'accept',ARRAY[['title']],$5,$6,$5,true) v`,[A,sid,t.request_id,randomUUID(),H2,next]))[0].v.code,'INVALID_INPUT');
    eq((await row('recipe_draft_sessions','id=$1',[sid])).revision,1);
    eq((await approve()).receipt.applied_revision,'2');
    eq((await approve(null)).outcome,'replay');
    eq((await approve(next,'reject',[])).code,'IDEMPOTENCY_CONFLICT');
    eq((await approve(next,'accept',['title'],randomUUID())).code,'TURN_ALREADY_DECIDED');
    eq((await claim(sid,t.request_id)).turn.result,proposal); // old revision stable replay
    eq((await row('recipe_draft_sessions','id=$1',[sid])).overlay.title.confirmed_revision,'2');
    const t2=(await claim(sid,randomUUID(),2,'review',H,A,H2)).turn;
    await expire(t2);const reclaimed=(await rpc('recover_recipe_draft_turn',[A,sid,t2.request_id,true])).turn;
    assert.notEqual(reclaimed.fencing_token,t2.fencing_token);assertions++;
    eq(reclaimed.reserved_tokens,4096);await code('mark_recipe_draft_turn_dispatched',[A,sid,t2.request_id,t2.fencing_token,true],'CLAIM_EXPIRED');
    await mark(reclaimed);await expire(reclaimed);
    const unknown=(await rpc('recover_recipe_draft_turn',[A,sid,t2.request_id,true])).turn;
    eq(unknown.result.code,'PROVIDER_OUTCOME_UNKNOWN');eq(unknown.settled_tokens,4096);
    eq((await rpc('recover_recipe_draft_turn',[A,sid,t2.request_id,true])).turn,unknown);
    await code('finish_recipe_draft_turn',[A,sid,t2.request_id,reclaimed.fencing_token,proposal,0],'CLAIM_EXPIRED');
    const t3=(await claim(sid,randomUUID(),2,'review',H,A,H2)).turn;
    eq((await rpc('recover_recipe_draft_turn',[A,sid,t3.request_id,false])).turn.settled_tokens,0);
    const t4=(await claim(sid,randomUUID(),2,'review',H,A,H2)).turn;
    eq((await finish(t4,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},null,'predispatch')).turn.settled_tokens,0);
    const t5=(await claim(sid,randomUUID(),2,'review',H,A,H2)).turn;await mark(t5);
    await query('update public.recipe_draft_sessions set revision=3 where id=$1',[sid]);
    eq((await finish(t5,proposal,0)).turn.result.code,'STALE_REVISION');
    eq((await row('recipe_draft_turns','request_id=$1',[t5.request_id])).settled_tokens,4096);
    // Legal full context > provider prepared cap is allowed for ready/no dispatch.
    const large={status:'ready',fields:{},evidence:context.evidence,review_fields:[]};
    for(let i=0;i<100;i++)large.fields[`steps[${i}].instruction`]={raw_value:'x'.repeat(1500),evidence_ids:[E],user_confirmed:true,origin:'extracted'};
    const largeSid=(await create(job,large)).session.id;eq((await claim(largeSid)).turn.result.status,'no_review_needed');
    eq((await row('recipe_draft_sessions','id=$1',[largeSid])).reserved_tokens,0);
    // A losing preflight cannot settle a same-fence winner that already marked dispatch.
    const raceSid=(await create(job)).session.id;const raceTurn=(await claim(raceSid)).turn;
    eq((await finish(raceTurn,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},null)).code,'CLAIM_EXPIRED');
    await mark(raceTurn);
    eq((await finish(raceTurn,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},null,'predispatch')).code,'CLAIM_EXPIRED');
    eq((await row('recipe_draft_turns','request_id=$1',[raceTurn.request_id])).state,'pending');
    eq((await row('recipe_draft_turns','request_id=$1',[raceTurn.request_id])).reserved_tokens,4096);
    eq((await finish(raceTurn,proposal,0)).turn.state,'terminal');
    // Trusted DEV283 preparation rejects/no-review results consume zero dispatch/cost.
    for(const outcome of [{status:'rejected',code:'INVALID_EVIDENCE'},{status:'no_review_needed'}]) {
      const ps=(await create(job)).session.id;const pt=(await claim(ps)).turn;
      eq((await finish(pt,outcome,null,'predispatch')).turn.settled_tokens,0);
      eq((await row('recipe_draft_sessions','id=$1',[ps])).dispatch_count,0);
    }
    // Populated records are invisible to another real RLS subject.
    await db.exec(`begin;set local role authenticated;select set_config('request.jwt.claim.sub','${B}',true);`);
    for(const table of ['recipe_draft_sessions','recipe_draft_turns','recipe_draft_approvals','recipe_draft_owner_budgets'])eq((await query(`select count(*)::int n from public.${table}`))[0].n,0);
    await db.exec('rollback;');
    await assert.rejects(query(`insert into public.recipe_draft_turns(owner_id,session_id,request_id,request_body,request_hash,based_revision,context_snapshot,context_hash,state,result,lease_expires_at,dispatch_state,reserved_tokens,budget_date) values ($1,$2,$3,'{}',$4,1,'{}',$4,'terminal','{}',now(),'settled',0,current_date)`,[B,sid,randomUUID(),H]),e=>e.code==='23503');assertions++;
    for(const change of [c=>c.fields.title.evidence_ids=[E,E],c=>c.evidence.push(c.evidence[0]),c=>c.fields.title.origin=null,c=>c.review_fields.push('unsupported'),c=>c.fields.title.raw_value='']) {
      const malformed=structuredClone(context);change(malformed);eq((await create(job,malformed)).code,'INVALID_INPUT');
    }
    // Exact missing reviewed path is valid; unrelated group flags cannot disappear.
    const missing=structuredClone(context);delete missing.fields.title;
    const missingSid=(await create(job,missing)).session.id;
    const mt=(await claim(missingSid)).turn;await mark(mt);await finish(mt,proposal,0);
    const missingNext=structuredClone(missing);missingNext.fields.title=next.fields.title;missingNext.review_fields=['servings'];
    const mr=await rpc('approve_recipe_draft_turn',[A,missingSid,mt.request_id,randomUUID(),1,'accept',['title'],H2,missingNext,H2,true]);
    eq(mr.receipt.applied_revision,'2');eq(mr.receipt.session_id,missingSid);
    // Previously confirmed fields cannot be overwritten, even with a persisted service result.
    const confirmed=structuredClone(context);confirmed.fields.title.user_confirmed=true;
    const confirmedSid=(await create(job,confirmed)).session.id;
    const ct=(await claim(confirmedSid)).turn;await mark(ct);await finish(ct,proposal,0);
    eq((await rpc('approve_recipe_draft_turn',[A,confirmedSid,ct.request_id,randomUUID(),1,'accept',['title'],H2,next,H2,true])).code,'INVALID_INPUT');
    // Reject is durable, advances once, and leaves the effective context unchanged.
    const rejectSid=(await create(job)).session.id;const rt=(await claim(rejectSid)).turn;await mark(rt);await finish(rt,proposal,0);
    const rejectID=randomUUID();const rejectArgs=[A,rejectSid,rt.request_id,rejectID,1,'reject',[],H2,context,H2,true];
    eq((await rpc('approve_recipe_draft_turn',rejectArgs)).receipt.applied_revision,'2');
    rejectArgs[8]=null;eq((await rpc('approve_recipe_draft_turn',rejectArgs)).outcome,'replay');
    eq((await row('recipe_draft_sessions','id=$1',[rejectSid])).overlay,{});
    // Exhausted revision refuses approval atomically; usage absence/invalidity charges conservatively.
    const maxSid=(await create(job)).session.id;await query('update public.recipe_draft_sessions set revision=9223372036854775807 where id=$1',[maxSid]);
    const maxTurn=(await claim(maxSid,randomUUID(),'9223372036854775807')).turn;eq(maxTurn.based_revision,'9223372036854775807');await mark(maxTurn);await finish(maxTurn,proposal,0);
    eq((await rpc('approve_recipe_draft_turn',[A,maxSid,maxTurn.request_id,randomUUID(),'9223372036854775807','reject',[],H2,context,H2,true])).code,'REVISION_EXHAUSTED');
    const invalidUsageSid=(await create(job)).session.id;
    for(const usage of [-1,4097]){const ut=(await claim(invalidUsageSid)).turn;await mark(ut);eq((await finish(ut,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},usage)).turn.settled_tokens,4096);}
    // Group flag resolves only after every actual field gap is confirmed.
    const groupContext=structuredClone(context);
    groupContext.fields={'ingredients[0].name':context.fields.title,'ingredients[1].name':context.fields.servings};groupContext.review_fields=['ingredients'];
    const gs=(await create(job,groupContext)).session.id;const gt=(await claim(gs)).turn;await mark(gt);
    const gp=structuredClone(proposal);gp.suggestions[0].path='ingredients[0].name';await finish(gt,gp,0);
    const gn=structuredClone(groupContext);gn.fields['ingredients[0].name']=next.fields.title;
    const badGroup=structuredClone(gn);badGroup.review_fields=[];badGroup.status='ready';
    eq((await rpc('approve_recipe_draft_turn',[A,gs,gt.request_id,randomUUID(),1,'accept',['ingredients[0].name'],H2,badGroup,H2,true])).code,'INVALID_INPUT');
    eq((await rpc('approve_recipe_draft_turn',[A,gs,gt.request_id,randomUUID(),1,'accept',['ingredients[0].name'],H2,gn,H2,true])).receipt.applied_revision,'2');
    const siblingContext=structuredClone(groupContext);delete siblingContext.fields['ingredients[1].name'];
    siblingContext.review_fields=['ingredients','ingredients[1].name'];
    const ss=(await create(job,siblingContext)).session.id;const st=(await claim(ss)).turn;await mark(st);await finish(st,gp,0);
    const sn=structuredClone(siblingContext);sn.fields['ingredients[0].name']=next.fields.title;
    const erasedGroup=structuredClone(sn);erasedGroup.review_fields=['ingredients[1].name'];
    eq((await rpc('approve_recipe_draft_turn',[A,ss,st.request_id,randomUUID(),1,'accept',['ingredients[0].name'],H2,erasedGroup,H2,true])).code,'INVALID_INPUT');
    eq((await rpc('approve_recipe_draft_turn',[A,ss,st.request_id,randomUUID(),1,'accept',['ingredients[0].name'],H2,sn,H2,true])).receipt.applied_revision,'2');
    const resolvedContext=structuredClone(siblingContext);resolvedContext.review_fields=['ingredients','ingredients[0].name'];
    const rs=(await create(job,resolvedContext)).session.id;const rst=(await claim(rs)).turn;await mark(rst);await finish(rst,gp,0);
    const rn=structuredClone(resolvedContext);rn.fields['ingredients[0].name']=next.fields.title;rn.review_fields=[];rn.status='ready';
    eq((await rpc('approve_recipe_draft_turn',[A,rs,rst.request_id,randomUUID(),1,'accept',['ingredients[0].name'],H2,rn,H2,true])).receipt.applied_revision,'2');
    // Invalid persisted outcome inputs do not partially settle a reservation.
    const badResultSid=(await create(job)).session.id;const bt=(await claim(badResultSid)).turn;await mark(bt);
    for(const malformed of [{status:'unavailable'},{status:'unavailable',code:'SECRET'}, {...proposal,requiresApproval:true}, {...proposal,requires_approval:false}, {...proposal,suggestions:[{...proposal.suggestions[0],raw_value:'x'.repeat(1501)}]}, {...proposal,questions:Array(4).fill({path:'title',question:'?',evidence_ids:[E]})}, {...proposal,private_notes:'secret'}]) eq((await finish(bt,malformed,0)).code,'INVALID_INPUT');
    eq((await finish(bt,{},0)).code,'INVALID_INPUT');eq((await row('recipe_draft_turns','request_id=$1',[bt.request_id])).reserved_tokens,4096);
    await finish(bt,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},0);
    // Reservation slots prevent eight pending claims from admitting a ninth.
    const lowSid=(await create(job)).session.id;
    for(let i=0;i<8;i++){const lt=(await claim(lowSid)).turn;await mark(lt);await finish(lt,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},0);}
    await code('claim_recipe_draft_turn',[A,lowSid,randomUUID(),1,'review',H,H,true],'BUDGET_EXHAUSTED');
    eq((await row('recipe_draft_sessions','id=$1',[lowSid])).settled_tokens,0);
    await query('update public.recipe_draft_owner_budgets set settled_tokens=0 where owner_id=$1',[A]);
    const capSid=(await create(job)).session.id;
    for(let i=0;i<8;i++)eq((await claim(capSid)).turn.reserved_tokens,4096);
    await code('claim_recipe_draft_turn',[A,capSid,randomUUID(),1,'review',H,H,true],'BUDGET_EXHAUSTED');
    const capTurns=await query('select * from public.recipe_draft_turns where session_id=$1',[capSid]);
    for(const ct of capTurns){await mark(ct);await finish(ct,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},null);}
    eq((await row('recipe_draft_sessions','id=$1',[capSid])).dispatch_count,8);
    await code('claim_recipe_draft_turn',[A,capSid,randomUUID(),1,'review',H,H,true],'BUDGET_EXHAUSTED');
    // Original day settlement; fixtures shift only controlled ledger dates.
    const daySid=(await create(job)).session.id;const dt=(await claim(daySid)).turn;
    const oldDate='2000-01-01';await query(`update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens-4096 where owner_id=$1 and utc_date=$2`,[A,dt.budget_date]);
    await query(`insert into public.recipe_draft_owner_budgets(owner_id,utc_date,reserved_tokens) values ($1,$2,4096)`,[A,oldDate]);
    await query('update public.recipe_draft_turns set budget_date=$1 where session_id=$2',[oldDate,daySid]);
    await mark(dt);await finish(dt,{status:'unavailable',code:'PROVIDER_UNAVAILABLE'},1);eq((await budget(oldDate)).settled_tokens,1);
    // Deletion retains spent and unknown vendor budgets and releases predispatch only.
    const deleteSid=(await create(job)).session.id;const pending=(await claim(deleteSid)).turn;const dispatched=(await claim(deleteSid)).turn;
    await mark(dispatched);const before=await budget(dispatched.budget_date);
    await query('delete from public.recipe_draft_sessions where id=$1',[deleteSid]);const after=await budget(dispatched.budget_date);
    eq(after.reserved_tokens,before.reserved_tokens-8192);eq(after.settled_tokens,before.settled_tokens+4096);
    await code('mark_recipe_draft_turn_dispatched',[A,deleteSid,pending.request_id,pending.fencing_token,true],'NOT_FOUND');
    const multiSid=(await create(job)).session.id;const md1=(await claim(multiSid)).turn;const md2=(await claim(multiSid)).turn;
    await query('update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens-4096 where owner_id=$1 and utc_date=$2',[A,md1.budget_date]);
    await query('update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens+4096 where owner_id=$1 and utc_date=$2',[A,oldDate]);
    await query('update public.recipe_draft_turns set budget_date=$1 where request_id=$2',[oldDate,md1.request_id]);
    await mark(md1);await mark(md2);const oldBefore=await budget(oldDate);const newBefore=await budget(md2.budget_date);
    await query('delete from public.recipe_draft_sessions where id=$1',[multiSid]);
    eq((await budget(oldDate)).settled_tokens,oldBefore.settled_tokens+4096);eq((await budget(oldDate)).reserved_tokens,0);
    eq((await budget(md2.budget_date)).settled_tokens,newBefore.settled_tokens+4096);eq((await budget(md2.budget_date)).reserved_tokens,newBefore.reserved_tokens-4096);
    // Owner daily ceiling is shared by independent sessions and survives deletion.
    await query('update public.recipe_draft_owner_budgets set settled_tokens=65536 where owner_id=$1 and utc_date=$2',[A,dispatched.budget_date]);
    const exhausted=(await create(job)).session.id;
    await code('claim_recipe_draft_turn',[A,exhausted,randomUUID(),1,'review',H,H,true],'BUDGET_EXHAUSTED');
    eq(await query('select * from public.user_snapshots'),privateBefore);eq(await query('select * from public.recipe_import_jobs'),jobBefore);
    const beforeReplay=await query('select * from public.recipe_draft_sessions order by id');
    const security=async()=>query(`select p.proname,p.prosecdef,p.proconfig,
      has_function_privilege('anon',p.oid,'EXECUTE') guest,
      has_function_privilege('authenticated',p.oid,'EXECUTE') client,
      has_function_privilege('service_role',p.oid,'EXECUTE') service
      from pg_proc p where p.proname like '%recipe_draft_%' order by p.proname`);
    const securityBefore=await security();
    const policiesBefore=await query(`select * from pg_policies where tablename like 'recipe_draft_%' order by tablename`);

    await db.exec(migration);eq(await query('select * from public.recipe_draft_sessions order by id'),beforeReplay);
    eq(await security(),securityBefore);eq(await query(`select * from pg_policies where tablename like 'recipe_draft_%' order by tablename`),policiesBefore);
    // Job cascade spans multiple sessions/days; no refunds of dispatched outcomes.
    await query('update public.recipe_draft_owner_budgets set settled_tokens=0 where owner_id=$1 and utc_date=$2',[A,dispatched.budget_date]);
    const js1=(await create(job)).session.id;const js2=(await create(job)).session.id;
    const jt1=(await claim(js1)).turn;const jt2=(await claim(js2)).turn;
    await query('update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens-4096 where owner_id=$1 and utc_date=$2',[A,jt1.budget_date]);
    await query('update public.recipe_draft_owner_budgets set reserved_tokens=reserved_tokens+4096 where owner_id=$1 and utc_date=$2',[A,oldDate]);
    await query('update public.recipe_draft_turns set budget_date=$1 where request_id=$2',[oldDate,jt1.request_id]);
    await mark(jt1);await mark(jt2);
    const jobOldBefore=await budget(oldDate);
    await query('delete from public.recipe_import_jobs where id=$1',[job]);eq((await query('select count(*)::int n from public.recipe_draft_sessions'))[0].n,0);
    eq((await budget(dispatched.budget_date)).settled_tokens,4096);
    eq((await budget(oldDate)).settled_tokens,jobOldBefore.settled_tokens+4096);
    eq((await budget(oldDate)).reserved_tokens,0);
    // Account cascade with a live unknown reservation is an authorized complete purge.
    const bjob=randomUUID();await query(`insert into public.recipe_import_jobs(id,owner_id,client_request_id,input_type,source_value,source_fingerprint,status,result) values ($1,$2,$3,'text','B source','B-hash','completed',$4)`,[bjob,B,randomUUID(),{fixture:'original'}]);
    const bs=(await create(bjob,context,B)).session.id;const bturn=(await claim(bs,randomUUID(),1,'review',H,B)).turn;
    await rpc('mark_recipe_draft_turn_dispatched',[B,bs,bturn.request_id,bturn.fencing_token,true]);
    await query('delete from auth.users where id=$1',[B]);
    for(const table of ['recipe_draft_sessions','recipe_draft_turns','recipe_draft_approvals','recipe_draft_owner_budgets'])eq((await query(`select count(*)::int n from public.${table} where owner_id=$1`,[B]))[0].n,0);
    await query('delete from auth.users where id=$1',[A]);eq((await query('select count(*)::int n from public.recipe_draft_owner_budgets'))[0].n,0);
    const rollback=await sql('tests/isolated/recipe-draft-storage-rollback.sql');await db.exec(rollback);await db.exec(rollback);
    eq((await query(`select count(*)::int n from pg_class where relname like 'recipe_draft_%'`))[0].n,0);
    eq((await query(`select count(*)::int n from pg_proc where proname like '%recipe_draft_%'`))[0].n,0);
    await db.exec(migration);eq((await query(`select count(*)::int n from pg_policies where tablename like 'recipe_draft_%'`))[0].n,4);eq(await security(),securityBefore);
    console.log(`PASS: PostgreSQL 18.3, pgTAP 20, ${assertions} runtime assertions; multi-connection/HTTP/provider/Native NOT RUN.`);
  } finally { await db.close(); }
});
