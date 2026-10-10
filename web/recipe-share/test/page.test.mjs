import {test} from "node:test";
import assert from "node:assert/strict";
import {validatePublicRecipe,renderRecipePage,renderUnavailable} from "../src/page.mjs";
import {createRecipeServer} from "../src/server.mjs";
const sample={title:"Soup",summary:"Simple meal",servings:2,prepMinutes:10,cookMinutes:15,sourceURL:"https://example.org/soup",ingredients:[{name:"Carrot",amountText:"2"}],steps:[{title:"Boil",instruction:"Simmer gently."}]};

test("reject owner-private fields",()=>{for(const key of ["notes","coverData","owner_id","importRecord"]){assert.equal(validatePublicRecipe({...sample,[key]:"secret"}),null);}});
test("HTML escaped, no fake app store link",()=>{const html=renderRecipePage({...sample,title:"<script>alert(1)</script>",steps:[{title:"",instruction:"<img src=x onerror=alert(1)>"}]});assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>alert/);assert.doesNotMatch(html,/apps\.apple\.com/);assert.match(html,/noindex,nofollow/);});
test("public ingredients, steps and source render",()=>{const html=renderRecipePage(sample);for(const text of ["Simmer gently","Carrot","Prep","View original"])assert.match(html,new RegExp(text));});
test("unsafe source URL not rendered", () => {
  const unsafe = {...sample, sourceURL:"javascript:alert(1)"};
  assert.equal(validatePublicRecipe(unsafe), null);
  assert.throws(() => renderRecipePage(unsafe), /Invalid public recipe payload/);
});

test("only safe public HTTPS source citations are rendered", () => {
  for (const url of [
    "https://example.org/soup",
    "https://www.youtube.com/watch?v=abc123",
    "https://example.org/recipe?p=42&id=2",
  ]) {
    assert.equal(validatePublicRecipe({...sample, sourceURL:url})?.sourceURL, url);
    assert.match(renderRecipePage({...sample, sourceURL:url}), /View original/);
  }
  for (const source of [null, undefined]) {
    const input = {...sample, sourceURL:source};
    assert.equal(validatePublicRecipe(input)?.sourceURL, null);
    assert.doesNotMatch(renderRecipePage(input), /View original/);
  }
});

test("private, credentialed and malformed citations invalidate public recipes", () => {
  for (const url of [
    "http://example.org/soup",
    "https://example.org/soup?access_token=private",
    "https://example.org/soup?api_key=private",
    "https://example.org/soup?signature=private",
    "https://example.org/soup?utm_source=tracking",
    "https://example.org/soup?api%5Fkey=encoded",
    "https://example.org/soup#signed-session",
    "https://alice:password@example.org/soup",
    "https://example.org:8443/soup",
    "https://example.org:443/soup",
    "https://127.0.0.1/soup",
    "https://[::1]/soup",
    "https://printer.local/soup",
    "https://localhost/soup",
    "https://example.org/soup\nwith-control",
    "https://example.org/" + "x".repeat(2049),
    "",
    42,
  ]) {
    const input = {...sample, sourceURL:url};
    assert.equal(validatePublicRecipe(input), null, String(url).slice(0, 80));
    assert.throws(() => renderRecipePage(input), /Invalid public recipe payload/);
  }
});
test("revoked and invalid recipe fail closed",async()=>{assert.equal(validatePublicRecipe({...sample,steps:"private"}),null);assert.match(renderUnavailable(),/Recipe unavailable/);const server=createRecipeServer({loadRecipe:async()=>null});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,404);}finally{await new Promise(r=>server.close(r));}});
test("guest HTML requires no login and cannot be cached",async()=>{const server=createRecipeServer({loadRecipe:async()=>sample});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,200);assert.equal(res.headers.get("cache-control"),"private, no-store, max-age=0");assert.match(await res.text(),/Soup/);}finally{await new Promise(r=>server.close(r));}});
