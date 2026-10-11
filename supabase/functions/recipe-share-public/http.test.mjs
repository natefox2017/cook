// Developer: gengyun
// Purpose: Execute the actual anonymous share handler with synthetic DB dependencies, without sockets or credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';

const root = process.env.RECIPE_SHARE_SOURCE_ROOT
  ? pathToFileURL(process.env.RECIPE_SHARE_SOURCE_ROOT.replace(/\/$/, '') + '/')
  : new URL('../', import.meta.url);
const snapshot = {
  title: 'Synthetic soup', summary: 'Owner-approved source', sourceURL: null,
  servings: 2, prepMinutes: 5, cookMinutes: 10,
  ingredients: [{name: 'Salt', amountText: 'to taste'}],
  steps: [{title: 'Mix', instruction: 'Stir gently.'}],
};
const slug = 'synthetic_123';
let row, databaseError, calls, observed;
const admin = {from(table) {
  calls++;
  observed = {table, filters: []};
  return {
    select(columns) {observed.columns = columns; return this;},
    eq(key, value) {observed.filters.push([key, value]); return this;},
    is(key, value) {observed.filters.push([key, value]); return this;},
    async maybeSingle() {
      if (databaseError) return {data: null, error: {code: 'SYNTHETIC_FAILURE'}};
      const visible = row && observed.filters.every(([key, value]) => row[key] === value);
      return {data: visible ? {...row} : null, error: null};
    },
  };
}};
const priorAuth = globalThis.__publicShareTestAuth;
const priorDeno = globalThis.Deno;
globalThis.__publicShareTestAuth = {createServiceClient: () => admin};
globalThis.Deno = {serve() {}};
let source = await readFile(new URL('recipe-share-public/index.ts', root), 'utf8');
source = source.replace(/import \{createServiceClient\} from "\.\.\/_shared\/auth.ts";/,
  'const {createServiceClient} = globalThis.__publicShareTestAuth;');
source = source.replace('"../_shared/recipeShareContract.mjs"',
  JSON.stringify(new URL('_shared/recipeShareContract.mjs', root).href));
const {handlePublicShare} = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
// The imported handler captures only synthetic Auth; restore process globals immediately.
if (priorAuth === undefined) delete globalThis.__publicShareTestAuth;
else globalThis.__publicShareTestAuth = priorAuth;
if (priorDeno === undefined) delete globalThis.Deno;
else globalThis.Deno = priorDeno;

function reset() {
  calls = 0; databaseError = false;
  row = {opaque_slug: slug, revoked_at: null, scope: 'fullInstructions',
    has_distribution_rights: true, sanitized_snapshot: structuredClone(snapshot),
    owner_id: 'synthetic-private-owner', share_id: 'synthetic-private-share'};
}
const request = (method = 'GET', tail = slug) => new Request(
  'https://api.recipepals.app/functions/v1/recipe-share-public/' + tail, {method});
function privacy(response) {
  assert.match(response.headers.get('cache-control'), /no-store/);
  assert.match(response.headers.get('x-robots-tag'), /noindex/);
}

test('GET emits only eight public fields and enforces slug/revocation query filters', async () => {
  reset(); const response = await handlePublicShare(request());
  assert.equal(response.status, 200); privacy(response);
  assert.deepEqual(await response.json(), snapshot);
  assert.deepEqual(observed, {table: 'recipe_shared_snapshots',
    columns: 'sanitized_snapshot,scope,has_distribution_rights',
    filters: [['opaque_slug', slug], ['revoked_at', null]]});
  assert.equal(calls, 1);
});

test('scope, rights and private-field pollution fail closed without leaking data', async () => {
  for (const corrupt of [
    r => {r.scope = 'summaryAndSource';},
    r => {r.has_distribution_rights = false;},
    r => {r.scope = 'private';},
    r => {r.sanitized_snapshot.owner_id = 'PRIVATE_MARKER';},
    r => {r.sanitized_snapshot.ingredients[0].notes = 'PRIVATE_MARKER';},
  ]) {
    reset(); corrupt(row);
    const response = await handlePublicShare(request());
    assert.equal(response.status, 503); privacy(response);
    assert.doesNotMatch(await response.text(), /PRIVATE_MARKER|synthetic-private/);
  }
  reset(); row.scope = 'summaryAndSource'; row.has_distribution_rights = false;
  row.sanitized_snapshot.ingredients = []; row.sanitized_snapshot.steps = [];
  assert.equal((await handlePublicShare(request())).status, 200);
});

test('invalid slug and route cause zero database queries', async () => {
  for (const tail of ['short', 'abcdefgh/extra', '%2Fsecret', 'a'.repeat(129)]) {
    reset(); const response = await handlePublicShare(request('GET', tail));
    assert.equal(response.status, 404); privacy(response); assert.equal(calls, 0);
  }
});

test('revoked, unknown and cleared snapshots share the same private 404 response', async () => {
  let expected;
  for (const state of ['unknown', 'revoked', 'cleared']) {
    reset();
    if (state === 'unknown') row = null;
    if (state === 'revoked') row.revoked_at = '2026-10-11T00:00:00Z';
    if (state === 'cleared') row.sanitized_snapshot = null;
    const response = await handlePublicShare(request());
    assert.equal(response.status, 404); privacy(response);
    const body = await response.text();
    if (expected === undefined) expected = body; else assert.equal(body, expected);
    assert.doesNotMatch(body, /synthetic-private|Synthetic soup/);
  }
});

test('database error is private 503; unsupported method is 405 without querying', async () => {
  reset(); databaseError = true;
  const error = await handlePublicShare(request());
  assert.equal(error.status, 503); privacy(error);
  assert.doesNotMatch(await error.text(), /SYNTHETIC_FAILURE|synthetic-private/);
  reset(); const method = await handlePublicShare(request('POST'));
  assert.equal(method.status, 405); privacy(method); assert.equal(calls, 0);
});

test('successful HEAD retains JSON/privacy headers and has no body', async () => {
  reset(); const response = await handlePublicShare(request('HEAD'));
  assert.equal(response.status, 200); privacy(response);
  assert.match(response.headers.get('content-type'), /application\/json/);
  assert.equal(await response.text(), ''); assert.equal(calls, 1);
});
