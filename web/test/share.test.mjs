import test from 'node:test';
import assert from 'node:assert/strict';
import { shareResponse } from '../lib/share.mjs';

const recipe = { title: '<script>alert(1)</script>', summary: 'An example for tests only',
  ingredients: [{ name: 'Salt', amountText: 'to taste' }],
  steps: [{ title: '', instruction: 'Mix.' }] };
const api = 'https://api.example.org/public';

test('valid public snapshots stay escaped, unlisted and uncached', async () => {
  const response = await shareResponse('abcdefgh', { api, fetcher: async (url, options) => {
    assert.equal(url, `${api}/abcdefgh`);
    assert.equal(options.redirect, 'error');
    assert.equal(options.cache, 'no-store');
    assert.ok(options.signal instanceof AbortSignal);
    return Response.json(recipe);
  } });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('cache-control'), /no-store/);
  assert.match(response.headers.get('x-robots-tag'), /noindex/);
  assert.match(response.headers.get('content-security-policy'), /font-src 'self'/);
  const html = await response.text();
  assert.ok(!html.includes('<script>alert'));
  assert.match(html, /&lt;script&gt;/);
  assert.match(html, /href="\/privacy"/);
  assert.match(html, /href="\/share.css"/);
});

test('invalid slug and unsafe/unconfigured API never trigger fetch', async () => {
  const fetcher = () => { throw new Error('must not fetch'); };
  assert.equal((await shareResponse('../private', { api, fetcher })).status, 404);
  for (const unsafe of ['', 'http://api.example.org', 'https://127.0.0.1', 'https://api.example.org/?key=secret']) {
    assert.equal((await shareResponse('abcdefgh', { api: unsafe, fetcher })).status, 503);
  }
});

test('withdrawal is 404; upstream failure, redirect or private fields fail closed', async () => {
  for (const status of [404, 410]) {
    const response = await shareResponse('abcdefgh', { api, fetcher: async () => new Response('', { status }) });
    assert.equal(response.status, 404);
    assert.ok(!(await response.text()).includes(recipe.summary));
  }
  for (const fetcher of [async () => new Response('', { status: 302 }),
    async () => { throw new Error('timeout'); },
    async () => Response.json({ ...recipe, ownerID: 'private-owner' }),
    async () => new Response('not JSON')]) {
    assert.equal((await shareResponse('abcdefgh', { api, fetcher })).status, 503);
  }
});
