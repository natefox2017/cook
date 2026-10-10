// Developer: Recipe Pals
// Purpose: Deterministic public-share wire, source-rights, and unsafe-input regression (DEV-241).

import test from "node:test";
import assert from "node:assert/strict";
import {
  boundedJSON,
  contentDigest,
  managePayload,
  publicCitation,
  publicSnapshot,
  randomSlug,
  routeTail,
  utcTimestamp,
  versionMatch,
  webOrigin,
} from "./recipeShareContract.mjs";

const uuid = "e8a3e5d3-38c7-4fd8-9580-999d75f787b2";
const snapshot = {
  title: "Lemon Pasta", summary: "A bright dinner.",
  sourceURL: "https://recipes.examplefood.com/r/lemon?p=12",
  servings: 2, prepMinutes: 10, cookMinutes: 20,
  ingredients: [{name: "Pasta", amountText: "200 g"}],
  steps: [{title: "Cook", instruction: "Cook until al dente."}],
};
const create = {
  idempotencyKey: uuid,
  sourceRecipeID: uuid,
  sourceRecipeUpdatedAt: "2026-10-10T11:00:00Z",
  scope: "fullInstructions",
  hasDistributionRights: true,
  snapshot,
};

test("normalizes a rights-approved exact eight-field public snapshot", () => {
  assert.deepEqual(Object.keys(publicSnapshot(snapshot)).sort(), [
    "cookMinutes", "ingredients", "prepMinutes", "servings",
    "sourceURL", "steps", "summary", "title",
  ]);
  assert.ok(managePayload(create, true));
  assert.equal(managePayload({...create, idempotencyKey: "bad"}, true), null);
  assert.equal(managePayload({...create, ownerID: uuid}, true), null);
  assert.equal(managePayload({...create, hasDistributionRights: false}, true), null);
});

test("summary-only never leaks recipe ingredients or directions", () => {
  assert.equal(managePayload({...create, scope: "summaryAndSource"}, true), null);
  const safe = {...create, scope: "summaryAndSource", hasDistributionRights: false,
    snapshot: {...snapshot, ingredients: [], steps: []}};
  assert.equal(managePayload(safe, true)?.snapshot.steps.length, 0);
  assert.equal(managePayload(safe, false), null); // PUT may not carry a create key.
  const {idempotencyKey, ...update} = safe;
  assert.ok(managePayload(update, false));
  assert.equal(idempotencyKey, uuid);
});

test("rejects private properties, invalid values and raw HTML URLs", () => {
  for (const change of [
    {owner_id: uuid}, {notes: "Private"}, {sourceText: "Secret"},
    {stepImages: ["file:///private"]}, {imageURL: "https://example.com/private.png"},
  ]) assert.equal(publicSnapshot({...snapshot, ...change}), null);
  assert.equal(publicSnapshot({...snapshot, title: " "}), null);
  assert.equal(publicSnapshot({...snapshot, servings: 0}), null);
  assert.equal(publicSnapshot({...snapshot, cookMinutes: 999999}), null);
  assert.equal(publicSnapshot({...snapshot, steps: [{title: "", instruction: " " }]}), null);
  assert.equal(publicSnapshot({...snapshot, ingredients: [{name: "Egg", amountText: "x", secret: true}]}), null);
});

test("restricts source citations to public, credential-free HTTPS lookups", () => {
  for (const value of [
    "https://recipes.examplefood.com/video?v=12",
    "https://recipes.examplefood.com/post/p?id=22",
  ]) assert.equal(publicCitation(value), true);
  for (const value of [
    "http://recipes.examplefood.com", "https://127.0.0.1/a",
    "https://foo.local/a", "https://foo.internal/a",
    "https://user:password@foo.com/a",
    "https://foo.com/a?token=abcdef", "https://foo.com/a#private",
    "https://foo.com:443/a", "file:///some/private/file",
  ]) assert.equal(publicCitation(value), false, value);
});

test("checks UTC dates, route suffix and version preconditions", () => {
  assert.equal(utcTimestamp("2026-02-30T10:00:00Z"), null);
  assert.equal(utcTimestamp("2026-02-28T10:00:00Z"), "2026-02-28T10:00:00.000Z");
  assert.equal(versionMatch('"v3"'), 3);
  for(const input of ["v3", '"v0"', '"v-1"', '"v999999999999999999999"']) {
    assert.equal(versionMatch(input), null);
  }
  assert.deepEqual(routeTail(
    "https://api.examplefood.com/functions/v1/recipe-share-public/abcd_1234",
    "recipe-share-public",
  ), ["abcd_1234"]);
});

test("fake host and private address cannot become public poster URL", () => {
  assert.equal(webOrigin("https://example.com"), null);
  assert.equal(webOrigin("https://localhost"), null);
  assert.equal(webOrigin("http://recipes.examplefood.com"), null);
  assert.equal(webOrigin("https://127.0.0.1"), null);
  assert.equal(webOrigin("https://recipes.examplefood.com"), "https://recipes.examplefood.com");
  const slug = randomSlug();
  assert.match(slug, /^[A-Za-z0-9_-]{43}$/);
});

test("idempotency canonical digest is stable and changes with rights", async () => {
  assert.equal(await contentDigest(create), await contentDigest(create));
  assert.notEqual(await contentDigest(create), await contentDigest({...create, scope: "summaryAndSource"}));
});

test("bounded request parses valid JSON, rejects oversized, malformed and invalid UTF-8", async () => {
  const make = (body, type = "application/json") =>
    new Request("https://api.examplefood.com", {method: "POST", headers: {"content-type": type}, body});
  assert.equal((await boundedJSON(make(JSON.stringify(create)))).value.idempotencyKey, uuid);
  assert.equal((await boundedJSON(make(JSON.stringify(create)), 8)).error, 413);
  assert.equal((await boundedJSON(make("{bad json"))).error, 400);
  assert.equal((await boundedJSON(make("hello", "text/plain"))).error, 400);
  assert.equal((await boundedJSON(make(new Uint8Array([0xff, 0xfe])))).error, 400);
});
