import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';

test('proxy restricts endpoints, preserves bearer and does not forward browser credentials', async () => {
  const original = globalThis.fetch;
  let called = false;
  globalThis.fetch = async (url, options) => {
    called = true;
    assert.equal(url, 'https://example.org/functions/v1/admin-users?limit=1');
    assert.equal(options.headers.get('authorization'), 'Bearer test-session');
    assert.equal(options.headers.get('cookie'), null);
    assert.equal(options.headers.get('origin'), null);
    assert.equal(options.redirect, 'error');
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  };
  try {
    const env = { ADMIN_FUNCTIONS_URL: 'https://example.org/functions/v1' };
    const denied = await worker.fetch(new Request('https://admin.example.org/api/private-table'), env);
    assert.equal(denied.status, 404);
    assert.equal(called, false);
    const response = await worker.fetch(new Request('https://admin.example.org/api/admin-users?limit=1', {
      headers: { authorization: 'Bearer test-session', cookie: 'private=value', origin: 'https://admin.example.org' },
    }), env);
    assert.equal(response.status, 401);
    assert.match(response.headers.get('cache-control'), /no-store/);
  } finally {
    globalThis.fetch = original;
  }
});
