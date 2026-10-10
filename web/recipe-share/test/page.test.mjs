import {test} from "node:test";
import assert from "node:assert/strict";
import {validatePublicRecipe,renderRecipePage,renderUnavailable} from "../src/page.mjs";
import {createRecipeServer} from "../src/server.mjs";
const sample={title:"Soup",summary:"Simple meal",servings:2,prepMinutes:10,cookMinutes:15,sourceURL:"https://example.org/soup",ingredients:[{name:"Carrot",amountText:"2"}],steps:[{title:"Boil",instruction:"Simmer gently."}]};

test("reject owner-private fields",()=>{for(const key of ["notes","coverData","owner_id","importRecord"]){assert.equal(validatePublicRecipe({...sample,[key]:"secret"}),null);}});
test("HTML escaped, no fake app store link",()=>{const html=renderRecipePage({...sample,title:"<script>alert(1)</script>",steps:[{title:"",instruction:"<img src=x onerror=alert(1)>"}]});assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>alert/);assert.doesNotMatch(html,/apps\.apple\.com/);assert.match(html,/noindex,nofollow/);});
test("public ingredients, steps and source render",()=>{const html=renderRecipePage(sample);for(const text of ["Simmer gently","Carrot","Prep","View original"])assert.match(html,new RegExp(text));});
test("rejects unsafe public source URLs instead of silently presenting them", () => {
  const disallowed = [
    "javascript:alert(1)", "http://example.org/soup", "https://localhost/soup",
    "https://printer.local/soup", "https://printer.local./soup",
    "https://127.0.0.1/soup", "https://192.168.1.1/soup",
    "https://[::1]/soup", "https://example.org:8443/soup",
    "https://example.org:443/soup", "https://user:pass@example.org/soup",
    "https://example.org/soup#secret", "https://example.org/soup#",
    "https://example.org/soup?access_token=private",
    "https://example.org/soup?api_key=secret",
    "https://example.org/soup?signature=secret",
    "https://example.org/soup?unknown=secret",
    "https://example.org/soup?%61ccess_token=secret",
    "https://example.org/soup\n?access_token=private",
    "https://example.org/" + "a".repeat(2049),
    "", "not-a-url", 123, { href: "https://example.org/soup" },
  ];
  for (const citation of disallowed) {
    const payload = { ...sample, sourceURL: citation };
    assert.equal(validatePublicRecipe(payload), null, String(citation));
    assert.throws(() => renderRecipePage(payload), /Invalid public recipe payload/);
  }
});

test("renders only public HTTPS citations with approved query keys", () => {
  const allowed = [
    "https://example.org/recipes/soup",
    "https://www.youtube.com/watch?v=abc123",
    "https://example.org/r?p=42&id=2",
    "https://example.org/r?V=abc123",
    "https://xn--bcher-kva.de/r?id=1",
  ];
  for (const citation of allowed) {
    const payload = { ...sample, sourceURL: citation };
    assert.notEqual(validatePublicRecipe(payload), null, citation);
    const html = renderRecipePage(payload);
    assert.match(html, /View original/);
    assert.match(html, /href="https:\/\//);
    assert.doesNotMatch(html, /access_token=/);
  }
  for (const citation of [null, undefined]) {
    const html = renderRecipePage({ ...sample, sourceURL: citation });
    assert.doesNotMatch(html, /View original/);
    assert.notEqual(validatePublicRecipe({ ...sample, sourceURL: citation }), null);
  }
});

test("rejects invalid public citations at the HTTP guest boundary", async () => {
  const secret = "top-secret-recipe-token";
  const server = createRecipeServer({
    loadRecipe: async () => ({ ...sample, sourceURL: "https://example.org/r?token=" + secret }),
  });
  await new Promise(resolve => server.listen(0, resolve));
  try {
    const response = await fetch("http://127.0.0.1:" + server.address().port + "/r/abcdefgh");
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("cache-control"), "private, no-store, max-age=0");
    assert.match(response.headers.get("content-security-policy"), /default-src 'none'/);
    assert.doesNotMatch(await response.text(), new RegExp(secret));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
test("revoked and invalid recipe fail closed",async()=>{assert.equal(validatePublicRecipe({...sample,steps:"private"}),null);assert.match(renderUnavailable(),/Recipe unavailable/);const server=createRecipeServer({loadRecipe:async()=>null});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,404);}finally{await new Promise(r=>server.close(r));}});
test("guest HTML requires no login and cannot be cached",async()=>{const server=createRecipeServer({loadRecipe:async()=>sample});await new Promise(r=>server.listen(0,r));try{const res=await fetch(`http://127.0.0.1:${server.address().port}/r/abcdefgh`);assert.equal(res.status,200);assert.equal(res.headers.get("cache-control"),"private, no-store, max-age=0");assert.match(await res.text(),/Soup/);}finally{await new Promise(r=>server.close(r));}});
