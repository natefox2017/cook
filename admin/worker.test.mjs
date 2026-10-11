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
    assert.equal(options.redirect, 'manual');
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

test('redirects fail closed without exposing an upstream location', async () => {
  const original = globalThis.fetch;
  const originalError = console.error;
  globalThis.fetch = async (_url, options) => {
    assert.equal(options.redirect, 'manual');
    return new Response(null, { status: 302, headers: { Location: 'http://127.0.0.1/private' } });
  };
  console.error = () => {};
  try {
    const response = await worker.fetch(new Request('https://admin.example.org/api/admin-auth/session'), {
      ADMIN_FUNCTIONS_URL: 'https://example.org/functions/v1',
    });
    assert.equal(response.status, 502);
    assert.equal(response.headers.get('location'), null);
    assert.match(response.headers.get('cache-control'), /no-store/);
    assert.doesNotMatch(await response.text(), /127\.0\.0\.1/);
  } finally {
    globalThis.fetch = original;
    console.error = originalError;
  }
});

test('misconfigured upstream never receives admin credentials', async () => {
  const previousFetch=globalThis.fetch;
  const previousError=console.error;
  let fetched=false;
  globalThis.fetch=async()=>{fetched=true;throw new Error('must not fetch');};
  console.error=()=>{};
  try {
    for(const base of ['http://example.org/functions/v1','https://user:pass@example.org/functions/v1','https://example.org/functions/v1?key=x','invalid']) {
      const response=await worker.fetch(new Request('https://admin.example.org/api/admin-auth/login',{method:'POST',body:'fixture',headers:{authorization:'Bearer fixture'}}),{ADMIN_FUNCTIONS_URL:base});
      assert.equal(response.status,502);assert.equal(fetched,false);
    }
  } finally {globalThis.fetch=previousFetch;console.error=previousError;}
});
