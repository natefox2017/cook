import {createServer} from "node:http";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {renderRecipePage,renderUnavailable} from "./page.mjs";
import {readPublicRecipeJSON} from "./public-api.mjs";

function configuredAPI() {
  const raw=process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
  if(!raw) return null;
  try {const u=new URL(raw);return u.protocol==="https:"&&u.hostname.includes(".")&&!u.username&&!u.password&&!u.hash?u.href.replace(/\/$/,""):null;}catch{return null;}
}
export function createRecipeServer({loadRecipe=null,appStoreURL=process.env.RECIPE_PALS_APP_STORE_URL}={}) {
  return createServer(async(req,res)=>{
    res.setHeader("X-Content-Type-Options","nosniff");
    res.setHeader("Referrer-Policy","no-referrer");
    res.setHeader("Cache-Control","private, no-store, max-age=0");
    res.setHeader("Content-Security-Policy","default-src 'none'; style-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    if(req.method!=="GET"&&req.method!=="HEAD"){res.writeHead(405).end();return;}
    if(req.url==="/styles.css"){
      const css=await readFile(new URL("./styles.css",import.meta.url),"utf8");
      res.writeHead(200,{"Content-Type":"text/css; charset=utf-8"}).end(req.method==="HEAD"?"":css);return;
    }
    const pathname=new URL(req.url??"/","http://placeholder.invalid").pathname;
    const match=pathname.match(/^\/r\/([A-Za-z0-9_-]{8,128})$/);
    if(!match){res.writeHead(404,{"Content-Type":"text/html; charset=utf-8"}).end(renderUnavailable());return;}
    try{
      let recipe;
      if(loadRecipe) recipe=await loadRecipe(match[1]);
      else {
        const api=configuredAPI();
        if(!api){res.writeHead(503,{"Content-Type":"text/html; charset=utf-8"}).end(renderUnavailable(503));return;}
        const response=await fetch(`${api}/${encodeURIComponent(match[1])}`,{headers:{Accept:"application/json"},cache:"no-store",signal:AbortSignal.timeout(8000)});
        if([404,410].includes(response.status)){res.writeHead(404,{"Content-Type":"text/html; charset=utf-8"}).end(renderUnavailable());return;}
        if(!response.ok) throw new Error("Public API unavailable");
        recipe=await readPublicRecipeJSON(response);
      }
      if(!recipe){res.writeHead(404,{"Content-Type":"text/html; charset=utf-8"}).end(renderUnavailable());return;}
      const page=renderRecipePage(recipe,{appStoreURL});
      res.writeHead(200,{"Content-Type":"text/html; charset=utf-8"}).end(req.method==="HEAD"?"":page);
    }catch{res.writeHead(503,{"Content-Type":"text/html; charset=utf-8"}).end(renderUnavailable(503));}
  });
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])createRecipeServer().listen(Number(process.env.PORT||3000));
