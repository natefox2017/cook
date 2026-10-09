// Developer: gengyun
// Purpose: Verify bounded and strictly typed public API payload parsing.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readPublicRecipeJSON } from '../src/public-api.mjs';

const response = (value, headers = {}) => new Response(value, {
  headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
});

test('accepts a bounded public JSON response', async () => {
  assert.deepEqual(await readPublicRecipeJSON(response('{"title":"Soup"}')), { title: 'Soup' });
});

test('rejects claimed body larger than the policy', async () => {
  await assert.rejects(
    () => readPublicRecipeJSON(response('{}', { 'content-length': '10485760' }), 1024),
    /size limit/
  );
});

test('rejects chunked oversized bodies even without content-length', async () => {
  const stream = new ReadableStream({ start(controller) {
    controller.enqueue(new TextEncoder().encode('{"name":"' + 'x'.repeat(800) + '"}'));
    controller.close();
  }});
  await assert.rejects(() => readPublicRecipeJSON(response(stream), 128), /size limit/);
});

test('rejects wrong MIME, malformed JSON, and invalid UTF-8', async () => {
  await assert.rejects(
    () => readPublicRecipeJSON(response('<script/>', { 'content-type': 'text/html' })),
    /response type/
  );
  await assert.rejects(() => readPublicRecipeJSON(response('{"bad":')), SyntaxError);
  await assert.rejects(() => readPublicRecipeJSON(response(Uint8Array.from([0x7b, 0xff, 0x7d]))), TypeError);
});

test('accepts +json media types and non-ASCII content', async () => {
  const payload = JSON.stringify({ title: '番茄汤 🍅' });
  assert.deepEqual(
    await readPublicRecipeJSON(response(payload, { 'content-type': 'application/vnd.recipe+json' })),
    { title: '番茄汤 🍅' }
  );
});
