import {test} from "node:test";
import assert from "node:assert/strict";
import {validatePublicRecipe,renderRecipePage,renderUnavailable} from "../src/page.mjs";
import {createRecipeServer} from "../src/server.mjs";
const sample={title:"Soup",summary:"Simple meal",servings:2,prepMinutes:10,cookMinutes:15,sourceURL:"https://example.org/soup",ingredients:[{name:"Carrot",amountText:"2"}],steps:[{title:"Boil",instruction:"Simmer gently."}]};

test("reject owner-private fields",()=>{for(const key of ["notes","coverData","owner_id","importRecord"]){assert.equal(validatePublicRecipe({...sample,[key]:"secret"}),null);}});
test("HTML escaped, no fake app store link",()=>{const html=renderRecipePage({...sample,title:"<script>alert(1)</script>",steps:[{title:"",instruction:"<img src=x onerror=alert(1)>"}]});assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>alert/);assert.doesNotMatch(html,/apps\.apple\.com/);assert.match(html,/noindex,nofollow/);});
test("public ingredients, steps and source render",()=>{const html=renderRecipePage(sample);for(const text of ["Simmer gently","Carrot","Prep","View original"])assert.match(html,new RegExp(text));});
test("unsafe source URL not rendered",()=>{assert.doesNotMatch(renderRecipePage({...sample,sourceURL:"javascript:alert(1)"}),/javascript:/);});
test("revoked and invalid recipe fail closed",async()=>{assert.equal(validatePublicRecipe({...sample,steps:"private"}),null);assert.match(renderUnavailable(),/Recipe unavailable/);const server=createRecipeServer({loadRecipe:async()=>null});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,404);}finally{await new Promise(r=>server.close(r));}});
test("guest HTML requires no login and cannot be cached",async()=>{const server=createRecipeServer({loadRecipe:async()=>sample});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,200);assert.equal(res.headers.get("cache-control"),"private, no-store, max-age=0");assert.match(await res.text(),/Soup/);}finally{await new Promise(r=>server.close(r));}});
