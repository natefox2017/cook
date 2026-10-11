// Developer: gengyun
// Purpose: Runs the real handler with synthetic atomic-row storage, not hosted Auth or database concurrency.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
const owner='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';
const key='44444444-4444-4444-8444-444444444444';
let rows = [];
let user = owner;
let countOverride = null;
let insertCalls = 0;
const admin = {
  async rpc(name, args) {
    assert.equal(name, 'create_recipe_share_once');
    const prior = rows.find(row => row.owner_id === args.p_owner_id &&
      row.idempotency_key === args.p_payload.idempotencyKey);
    if (prior) {
      return {
        data: prior.revoked_at || prior.request_hash !== args.p_request_hash
          ? {status: 409} : {status: 200, share: {...prior}},
        error: null,
      };
    }
    if ((countOverride ?? 0) + rows.filter(row => row.owner_id === args.p_owner_id).length >= 200) {
      return {data: {status: 429}, error: null};
    }
    const payload = args.p_payload;
    const row = {
      owner_id: args.p_owner_id, source_recipe_id: payload.sourceRecipeID,
      opaque_slug: args.p_slug, share_version: 1, scope: payload.scope,
      sanitized_snapshot: payload.snapshot, idempotency_key: payload.idempotencyKey,
      request_hash: args.p_request_hash, share_id: crypto.randomUUID(),
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
      revoked_at: null,
    };
    rows.push(row);
    insertCalls++;
    return {data: {status: 201, share: {...row}}, error: null};
  },
  from() {
    const filters = [];
    let update;
    return {
      select() { return this; },
      eq(key, value) { filters.push(row => row[key] === value); return this; },
      is(key, value) { filters.push(row => row[key] === value); return this; },
      update(value) { update = value; return this; },
      async maybeSingle() {
        const row = rows.find(row => filters.every(filter => filter(row)));
        if (!row) return {data: null, error: null};
        if (update) Object.assign(row, update);
        return {data: {...row}, error: null};
      },
    };
  },
};
globalThis.__lifecycleAuth={createServiceClient:()=>admin,requireUser:async()=>({user:{id:user}})};
globalThis.Deno={env:{get:()=> 'https://recipes.recipepals.app'},serve(){}};
let source=await readFile(new URL('./index.ts',import.meta.url),'utf8');
source=source.replace(/import \{createServiceClient, requireUser\} from "\.\.\/_shared\/auth.ts";/,'const {createServiceClient, requireUser}=globalThis.__lifecycleAuth;');
source=source.replace('"../_shared/recipeShareContract.mjs"',JSON.stringify(new URL('../_shared/recipeShareContract.mjs',import.meta.url).href));
const {handleRecipeShareManage:handle}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const snapshot={title:'Soup',summary:'Approved',sourceURL:null,servings:2,prepMinutes:10,cookMinutes:5,ingredients:[],steps:[]};
const payload={idempotencyKey:key,sourceRecipeID:key,sourceRecipeUpdatedAt:'2026-10-10T11:00:00Z',scope:'summaryAndSource',hasDistributionRights:false,snapshot};
function request(method,body=payload,id='',version){return new Request('https://api.recipepals.app/functions/v1/recipe-share-manage'+(id?'/'+id:''),{method,headers:{'content-type':'application/json',...(version?{'if-match':version}:{})},...(method==='POST'||method==='PUT'?{body:JSON.stringify(body)}:{})});
}
function reset(){rows=[];
user=owner;
countOverride=null;
insertCalls=0;

}
test('create retries are stable, changed-body conflicts and revoked replay cannot republish',async()=>{
reset();
const first=await handle(request('POST'));
assert.equal(first.status,201);
const metadata=await first.json();
countOverride=200;
const retry=await handle(request('POST'));
assert.equal(retry.status,200);
assert.deepEqual(await retry.json(),metadata);
assert.equal(insertCalls,1);
assert.equal((await handle(request('POST',{...payload,snapshot:{...snapshot,title:'Changed'}}))).status,409);
assert.equal((await handle(request('DELETE',undefined,metadata.shareID))).status,204);
assert.equal((await handle(request('POST'))).status,409);
assert.equal(rows.length,1);
assert.equal(rows[0].sanitized_snapshot,null);
});
test('concurrent identical POST resolves atomic RPC retry to winner metadata',async()=>{
reset();
const responses=await Promise.all([handle(request('POST')),handle(request('POST'))]);
assert.deepEqual(responses.map(r=>r.status).sort(),[200,201]);
assert.deepEqual(await responses[0].json(),await responses[1].json());
assert.equal(rows.length,1);
assert.equal(insertCalls,1);
});
test('CAS updates once, stale update conflicts, cross-owner is hidden, revoke blocks later update',async()=>{
reset();
const created=await (await handle(request('POST'))).json();
const {idempotencyKey,...update}=payload;
user=other;
assert.equal((await handle(request('PUT',update,created.shareID,'"v1"'))).status,404);
assert.equal(rows[0].share_version,1);
user=owner;
const changed=await handle(request('PUT',{...update,snapshot:{...snapshot,title:'Fresh'}},created.shareID,'"v1"'));
assert.equal(changed.status,200);
assert.equal((await changed.json()).shareVersion,2);
assert.equal((await handle(request('PUT',update,created.shareID,'"v1"'))).status,409);
assert.equal(rows[0].sanitized_snapshot.title,'Fresh');
assert.equal((await handle(request('DELETE',undefined,created.shareID))).status,204);
assert.equal((await handle(request('PUT',update,created.shareID,'"v2"'))).status,404);
assert.equal(rows[0].sanitized_snapshot,null);
});
test('quota returns 429 before insert for a new intent but permits existing retry',async()=>{
reset();
countOverride=200;
assert.equal((await handle(request('POST'))).status,429);
assert.equal(insertCalls,0);
});

test('atomic RPC admits only one different intent at quota boundary',async()=>{
reset();
countOverride=199;
const responses=await Promise.all([handle(request('POST')),handle(request('POST',{...payload,idempotencyKey:'55555555-5555-4555-8555-555555555555'}))]);
assert.deepEqual(responses.map(r=>r.status).sort(),[201,429]);
assert.equal(insertCalls,1);
});
