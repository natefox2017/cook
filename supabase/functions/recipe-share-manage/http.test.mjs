// Developer: gengyun
// Purpose: Execute management handler logic under Node with explicit synthetic Auth/DB dependencies.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
const owner='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';
const id='33333333-3333-4333-8333-333333333333';
const row={share_id:id,owner_id:owner,source_recipe_id:other,opaque_slug:'a'.repeat(43),share_version:1,scope:'summaryAndSource',created_at:'2026-10-10T11:00:00Z',updated_at:'2026-10-10T11:00:00Z',revoked_at:null,sanitized_snapshot:{title:'Soup'}};
let origin, user, writes=0;
const admin={from(){const filters=[];let update;return {
 select(){return this;},eq(k,v){filters.push([k,v]);return this;},is(k,v){filters.push([k,v]);return this;},
 update(v){update=v;return this;},async maybeSingle(){if(!filters.every(([k,v])=>row[k]===v))return {data:null,error:null};if(update){Object.assign(row,update);writes++;}return {data:{...row},error:null};}
};}};
globalThis.__shareAuth={createServiceClient:()=>admin,requireUser:async()=>({user:{id:user}})};
globalThis.Deno={env:{get:()=>origin},serve(){}};
let source=await readFile(new URL('./index.ts',import.meta.url),'utf8');
source=source.replace(/import \{createServiceClient, requireUser\} from "\.\.\/_shared\/auth.ts";/,'const {createServiceClient, requireUser}=globalThis.__shareAuth;');
source=source.replace('"../_shared/recipeShareContract.mjs"',JSON.stringify(new URL('../_shared/recipeShareContract.mjs',import.meta.url).href));
const {handleRecipeShareManage}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
const req=method=>new Request('https://api.recipepals.app/functions/v1/recipe-share-manage'+(method==='POST'?'':'/'+id),{method});
test('owner can revoke with missing host; other owner cannot; POST still fails closed',async()=>{
 origin=undefined;user=other;assert.equal((await handleRecipeShareManage(req('DELETE'))).status,404);
 user=owner;assert.equal((await handleRecipeShareManage(req('POST'))).status,503);assert.equal(writes,0);
 assert.equal((await handleRecipeShareManage(req('DELETE'))).status,204);assert.equal(writes,1);assert.ok(row.revoked_at);assert.equal(row.sanitized_snapshot,null);
 assert.equal((await handleRecipeShareManage(req('DELETE'))).status,204);assert.equal(writes,1);
});
test('own metadata emits only documented management fields',async()=>{
 origin='https://recipes.recipepals.app';user=owner;
 const response=await handleRecipeShareManage(req('GET'));assert.equal(response.status,200);
 assert.deepEqual(Object.keys(await response.json()).sort(),['shareID','slug','shareVersion','scope','createdAt','updatedAt','revokedAt','publicURL'].sort());
});
