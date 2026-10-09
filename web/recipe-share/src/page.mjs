const ALLOWED = new Set(["title","summary","sourceURL","servings","prepMinutes","cookMinutes","ingredients","steps"]);
export const escapeHTML = v => String(v).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const str = (v,n) => typeof v === "string" && v.length <= n ? v : null;
const sourceURL = v => { try { const u=new URL(v);return ["http:","https:"].includes(u.protocol)&&u.hostname&&!u.username&&!u.password?u.href:null; }catch{return null;} };
const safeStoreURL = v => { try{const u=new URL(v);return u.protocol==="https:"&&u.hostname==="apps.apple.com"&&/\/id\d+(?:$|\/)/.test(u.pathname)?u.href:null;}catch{return null;} };

export function validatePublicRecipe(raw) {
  if (!raw || typeof raw!=="object" || Array.isArray(raw) || Object.keys(raw).some(k=>!ALLOWED.has(k))) return null;
  const title=str(raw.title,180),summary=str(raw.summary,2000);
  if (!title?.trim() || summary===null || !Array.isArray(raw.ingredients) || raw.ingredients.length>200 || !Array.isArray(raw.steps) || raw.steps.length>100) return null;
  if ([raw.servings,raw.prepMinutes,raw.cookMinutes].some(v=>v!=null&&!Number.isInteger(v))) return null;
  if ([raw.prepMinutes,raw.cookMinutes].some(v=>v!=null&&(v<0||v>10080))) return null;
  if (raw.servings!=null && (raw.servings<1||raw.servings>100)) return null;
  const ingredients=raw.ingredients.map(x=>x&&typeof x==="object"&&!Array.isArray(x)&&Object.keys(x).every(k=>["name","amountText"].includes(k))&&str(x.name,180)&&str(x.amountText,120)!==null?{name:x.name,amountText:x.amountText}:null);
  const steps=raw.steps.map(x=>x&&typeof x==="object"&&!Array.isArray(x)&&Object.keys(x).every(k=>["title","instruction"].includes(k))&&str(x.title,220)!==null&&str(x.instruction,6000)?{title:x.title,instruction:x.instruction}:null);
  if(ingredients.some(x=>!x)||steps.some(x=>!x)) return null;
  return {title,summary,sourceURL:raw.sourceURL?sourceURL(raw.sourceURL):null,servings:raw.servings??null,prepMinutes:raw.prepMinutes??null,cookMinutes:raw.cookMinutes??null,ingredients,steps};
}

export function renderRecipePage(raw,{appStoreURL=null}={}) {
  const recipe=validatePublicRecipe(raw);
  if(!recipe) throw new Error("Invalid public recipe payload");
  const metric=(name,val)=>val==null?"":`<span><b>${name}</b> ${escapeHTML(val)}</span>`;
  const stats=metric("Prep",recipe.prepMinutes==null?null:`${recipe.prepMinutes} min`)+metric("Cook",recipe.cookMinutes==null?null:`${recipe.cookMinutes} min`)+metric("Servings",recipe.servings);
  const ingredients=recipe.ingredients.map((x,i)=>`<li><label><input type="checkbox" aria-label="Mark ingredient ${i+1} done"><span>${escapeHTML([x.amountText,x.name].filter(Boolean).join(" "))}</span></label></li>`).join("");
  const steps=recipe.steps.map((x,i)=>`<li><div class="step"><span class="num">${i+1}</span><div>${x.title?`<h3>${escapeHTML(x.title)}</h3>`:""}<p>${escapeHTML(x.instruction)}</p></div></div></li>`).join("");
  const source=recipe.sourceURL?`<p class="source">Source: <a href="${escapeHTML(recipe.sourceURL)}" rel="noopener noreferrer nofollow">View original</a></p>`:"";
  const store=safeStoreURL(appStoreURL);
  const cta=store?`<a class="cta" href="${escapeHTML(store)}" rel="noopener noreferrer">Get Recipe Pals on the App Store</a>`:"";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><meta property="og:type" content="article"><meta property="og:title" content="${escapeHTML(recipe.title)}"><meta property="og:description" content="${escapeHTML(recipe.summary)}"><title>${escapeHTML(recipe.title)} · Recipe Pals</title><link rel="stylesheet" href="/styles.css"></head><body><header class="brand">✦ RECIPE PALS</header><main><article><div class="hero"><span class="eyebrow">From a shared recipe</span><h1>${escapeHTML(recipe.title)}</h1>${recipe.summary?`<p class="summary">${escapeHTML(recipe.summary)}</p>`:""}<div class="metrics">${stats}</div></div>${recipe.ingredients.length?`<section><h2>Ingredients</h2><ul class="ingredients">${ingredients}</ul></section>`:""}${recipe.steps.length?`<section><h2>Cooking steps</h2><ol class="steps">${steps}</ol></section>`:""}${source}</article><aside><h2>Cook your way</h2><p>Save and organize your own recipes in Recipe Pals.</p>${cta}</aside></main><footer>Recipe Pals · Shared by choice. Content may be withdrawn by its publisher.</footer></body></html>`;
}
export function renderUnavailable(status=404) {
  const title=status===503?"Temporarily unavailable":"Recipe unavailable";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${title} · Recipe Pals</title><link rel="stylesheet" href="/styles.css"></head><body><header class="brand">✦ RECIPE PALS</header><main><article class="hero"><h1>${title}</h1><p>This recipe is private, withdrawn or unavailable. No account or download is required to view available public recipes.</p></article></main></body></html>`;
}
