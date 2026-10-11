import test from 'node:test';
import assert from 'node:assert/strict';
import { sendAdminRequest, AdminApiError } from '../src/api-request.ts';

const origin = 'https://admin.shopkivoo.com';
test('all admin credentials require a clean HTTPS endpoint before fetch', async () => {
  const previous = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('must not fetch'); };
  try {
    for (const base of ['http://example.com', 'https://user:pass@example.com', '/api?key=x', '/api#fragment', undefined]) {
      await assert.rejects(sendAdminRequest(base, 'fixture-key', origin, 'admin-auth/login', undefined, {method:'POST', body:{password:'fixture'}}), AdminApiError);
    }
    assert.equal(calls, 0);
  } finally { globalThis.fetch = previous; }
});
test('shared transport forbids redirects and bounds all calls including login', async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url, '/api/admin-auth/login');
    assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    assert.equal(options.cache, 'no-store');
    return Response.json({token:'fixture'});
  };
  try { assert.deepEqual(await sendAdminRequest('/api','public',origin,'admin-auth/login',undefined,{method:'POST',body:{password:'fixture'}}),{token:'fixture'}); }
  finally { globalThis.fetch = previous; }
});
test('invalid JSON and network exceptions produce safe readable errors', async () => {
  const previous = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response('<html>');
    await assert.rejects(sendAdminRequest('/api','public',origin,'admin-users','fixture'), /invalid JSON/);
    globalThis.fetch = async () => { throw new Error('secret fixture-key URL'); };
    await assert.rejects(sendAdminRequest('/api','public',origin,'admin-users','fixture'), e => e instanceof AdminApiError && !e.message.includes('fixture-key'));
    globalThis.fetch = async () => Response.json({error:{code:'server_misconfigured',message:'Service unavailable'}},{status:503});
    await assert.rejects(sendAdminRequest('/api','public',origin,'admin-users','fixture'), e => e.status === 503 && e.code === 'server_misconfigured');
  } finally { globalThis.fetch = previous; }
});
