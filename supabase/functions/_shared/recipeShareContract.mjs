// Developer: Recipe Pals
// Purpose: DEV-241 shared validated public-share contract. Never serialize a private Recipe.

export function isRecord(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function exactly(v, keys) {
  return isRecord(v) && Object.keys(v).length === keys.length &&
    Object.keys(v).every((key) => keys.includes(key));
}

export function isUUID(v) {
  return typeof v === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

export function utcTimestamp(v) {
  if (typeof v !== "string" ||
    !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(v)) return null;
  const d = new Date(v);
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 19) === v.slice(0, 19)
    ? d.toISOString() : null;
}

export function publicCitation(v) {
  if (typeof v !== "string" || v.length > 2048 ||
    /[\u0000-\u001f\u007f]/.test(v) || !v.startsWith("https://")) return false;
  try {
    const authority = v.slice(8).split(/[/?#]/, 1)[0];
    if (authority.includes("@") || authority.includes(":")) return false;
    const url = new URL(v);
    const host = url.hostname.toLowerCase();
    if (url.protocol !== "https:" || url.username || url.password || url.port || url.hash ||
      !host.includes(".") || host.endsWith(".") || host.includes(":") ||
      /(?:^|\.)(?:local|localhost|internal|invalid|test)$/.test(host) ||
      /^[\d.]+$/.test(host) || !/[a-z]/i.test(host)) return false;
    return [...url.searchParams.keys()].every((key) => ["v", "p", "id"].includes(key.toLowerCase()));
  } catch {
    return false;
  }
}

export function publicSnapshot(v) {
  const keys = ["title", "summary", "sourceURL", "servings", "prepMinutes", "cookMinutes", "ingredients", "steps"];
  if (!exactly(v, keys) || typeof v.title !== "string" || !v.title.trim() ||
    v.title.length > 180 || typeof v.summary !== "string" || v.summary.length > 2000 ||
    !(v.sourceURL === null || publicCitation(v.sourceURL)) ||
    !(v.servings === null || (Number.isInteger(v.servings) && v.servings >= 1 && v.servings <= 100)) ||
    !["prepMinutes", "cookMinutes"].every((name) => v[name] === null ||
      (Number.isInteger(v[name]) && v[name] >= 0 && v[name] <= 10080)) ||
    !Array.isArray(v.ingredients) || v.ingredients.length > 200 ||
    !Array.isArray(v.steps) || v.steps.length > 100) return null;
  if (v.ingredients.some((item) =>
    !exactly(item, ["name", "amountText"]) ||
    typeof item.name !== "string" || !item.name.trim() || item.name.length > 180 ||
    typeof item.amountText !== "string" || item.amountText.length > 120)) return null;
  if (v.steps.some((item) =>
    !exactly(item, ["title", "instruction"]) || typeof item.title !== "string" ||
    item.title.length > 220 || typeof item.instruction !== "string" ||
    !item.instruction.trim() || item.instruction.length > 6000)) return null;
  return {
    title: v.title, summary: v.summary, sourceURL: v.sourceURL,
    servings: v.servings, prepMinutes: v.prepMinutes, cookMinutes: v.cookMinutes,
    ingredients: v.ingredients.map(({name, amountText}) => ({name, amountText})),
    steps: v.steps.map(({title, instruction}) => ({title, instruction})),
  };
}

export function managePayload(v, creating) {
  const keys = ["sourceRecipeID", "sourceRecipeUpdatedAt", "scope", "hasDistributionRights", "snapshot"];
  if (creating) keys.unshift("idempotencyKey");
  if (!exactly(v, keys) || (creating && !isUUID(v.idempotencyKey)) ||
    !isUUID(v.sourceRecipeID) || !["summaryAndSource", "fullInstructions"].includes(v.scope) ||
    typeof v.hasDistributionRights !== "boolean") return null;
  const updated = utcTimestamp(v.sourceRecipeUpdatedAt);
  const snapshot = publicSnapshot(v.snapshot);
  if (!updated || !snapshot || (v.scope === "fullInstructions" && !v.hasDistributionRights) ||
    (v.scope === "summaryAndSource" && (snapshot.ingredients.length || snapshot.steps.length))) return null;
  const data = {
    sourceRecipeID: v.sourceRecipeID.toLowerCase(), sourceRecipeUpdatedAt: updated,
    scope: v.scope, hasDistributionRights: v.hasDistributionRights, snapshot,
  };
  return creating ? {idempotencyKey: v.idempotencyKey.toLowerCase(), ...data} : data;
}

export function webOrigin(v) {
  if (typeof v !== "string" || v.length > 2048) return null;
  try {
    const url = new URL(v);
    const host = url.hostname.toLowerCase();
    if (url.protocol !== "https:" || url.username || url.password || url.port ||
      url.search || url.hash || url.pathname !== "/" || !host.includes(".") ||
      host.endsWith(".") || host.includes(":") || /^[\d.]+$/.test(host) ||
      /(?:^|\.)(?:local|localhost|internal|invalid|test|example)$/.test(host) ||
      ["example.com", "example.net", "example.org"].includes(host)) return null;
    return url.origin;
  } catch {
    return null;
  }
}

export function routeTail(input, functionName) {
  const segments = new URL(input).pathname.split("/").filter(Boolean);
  const index = segments.lastIndexOf(functionName);
  return index < 0 ? null : segments.slice(index + 1);
}

export function versionMatch(v) {
  if (typeof v !== "string" || !/^"v[1-9]\d{0,14}"$/.test(v)) return null;
  const number = Number(v.slice(2, -1));
  return Number.isSafeInteger(number) ? number : null;
}

export function randomSlug() {
  return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function contentDigest(value) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(value)));
  return [...new Uint8Array(hash)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

export async function boundedJSON(req, maxBytes = 2 * 1024 * 1024) {
  const contentType = req.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  const declared = req.headers.get("content-length");
  if (contentType !== "application/json") return {error: 400};
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) return {error: 413};
  if (!req.body) return {error: 400};
  const reader = req.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.length;
      if (size > maxBytes) return {error: 413};
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return {value: JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes))};
  } catch {
    return {error: 400};
  } finally {
    try {await reader.cancel();} catch {}
    reader.releaseLock();
  }
}

export function privacyHeaders() {
  return {
    "Cache-Control": "private, no-store, max-age=0",
    "X-Robots-Tag": "noindex, nofollow",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  };
}

export function httpError(code, status, message = "The request could not be completed.") {
  return Response.json({code, message}, {status, headers: privacyHeaders()});
}
