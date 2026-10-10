// Developer: gengyun
// Purpose: Verify fail-closed public API configuration, redirects, and guest page status.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRecipeServer } from '../src/server.mjs';

const nativeFetch = globalThis.fetch;
const sample = {
  title: 'Soup',
  summary: 'Simple meal',
  sourceURL: null,
  servings: 2,
  prepMinutes: 10,
  cookMinutes: 15,
  ingredients: [{ name: 'Carrot', amountText: '2' }],
  steps: [{ title: 'Boil', instruction: 'Simmer gently.' }],
};

async function withGuestServer(callback) {
  const server = createRecipeServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await callback(base);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

async function withEnvironment(callback) {
  const originalAPI = process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
  const originalFetch = globalThis.fetch;
  try {
    await callback();
  } finally {
    if (originalAPI === undefined) {
      delete process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
    } else {
      process.env.RECIPE_PALS_PUBLIC_RECIPE_API = originalAPI;
    }
    globalThis.fetch = originalFetch;
  }
}

async function guestRequest(base, method = 'GET') {
  return nativeFetch(`${base}/r/abcdefgh`, { method });
}

test('unsafe configured public API hosts and URLs fail closed before fetch', async () => {
  await withEnvironment(async () => {
    const unsafe = [
      undefined,
      'http://api.example.org/functions/v1/recipe-share-public',
      'https://127.0.0.1/functions/v1/recipe-share-public',
      'https://[::1]/functions/v1/recipe-share-public',
      'https://localhost/functions/v1/recipe-share-public',
      'https://api.localhost/functions/v1/recipe-share-public',
      'https://printer.local/functions/v1/recipe-share-public',
      'https://metadata.google.internal/functions/v1/recipe-share-public',
      'https://api.example.org:8443/functions/v1/recipe-share-public',
      'https://api.example.org:443/functions/v1/recipe-share-public',
      'https://user:pass@api.example.org/functions/v1/recipe-share-public',
      'https://api.example.org/functions/v1/recipe-share-public?token=private',
      'https://api.example.org/functions/v1/recipe-share-public?',
      'https://api.example.org/functions/v1/recipe-share-public#private',
      'https://api.example.org/functions/v1/recipe-share-public#',
      ' https://api.example.org/functions/v1/recipe-share-public',
      'https://api.example.org/functions/v1/recipe-share-public\n',
      'https://api.example.org\\internal/functions/v1/recipe-share-public',
      'https://api.example.org/functions/v1/recipe-share-public///',
      'https://a..example.org/functions/v1/recipe-share-public',
      'https://123.456/functions/v1/recipe-share-public',
    ];
    let outboundCalls = 0;
    globalThis.fetch = async () => {
      outboundCalls++;
      throw new Error('Unexpected outbound API request');
    };

    await withGuestServer(async base => {
      for (const value of unsafe) {
        if (value === undefined) {
          delete process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
        } else {
          process.env.RECIPE_PALS_PUBLIC_RECIPE_API = value;
        }
        const res = await guestRequest(base);
        assert.equal(res.status, 503, String(value));
        assert.equal(res.headers.get('cache-control'), 'private, no-store, max-age=0');
        const body = await res.text();
        assert.match(body, /Temporarily unavailable/);
        assert.doesNotMatch(body, /token=private|user:pass|metadata\.google\.internal/);
        assert.equal(outboundCalls, 0, String(value));
      }
    });
  });
});

test('valid public API base uses one no-redirect GET and preserves guest headers', async () => {
  await withEnvironment(async () => {
    process.env.RECIPE_PALS_PUBLIC_RECIPE_API =
      'https://api.example.org/functions/v1/recipe-share-public/';
    const outbound = [];
    globalThis.fetch = async (url, options) => {
      outbound.push({ url, options });
      return new Response(JSON.stringify(sample), {
        status: 200,
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
      });
    };

    await withGuestServer(async base => {
      const res = await guestRequest(base);
      assert.equal(res.status, 200);
      assert.equal(res.headers.get('cache-control'), 'private, no-store, max-age=0');
      assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
      const html = await res.text();
      assert.match(html, /Soup/);
      assert.match(html, /noindex,nofollow/);
      assert.equal(outbound.length, 1);
      assert.equal(outbound[0].url,
        'https://api.example.org/functions/v1/recipe-share-public/abcdefgh');
      assert.equal(outbound[0].options.redirect, 'error');
      assert.equal(outbound[0].options.cache, 'no-store');
      assert.equal(outbound[0].options.headers.Accept, 'application/json');
      assert.ok(outbound[0].options.signal instanceof AbortSignal);

      const head = await guestRequest(base, 'HEAD');
      assert.equal(head.status, 200);
      assert.equal(await head.text(), '');
      assert.equal(outbound.length, 2);
      assert.equal(outbound[1].options.redirect, 'error');
    });
  });
});

test('guest API 404/410 remain private 404; redirects and network failures return 503', async () => {
  await withEnvironment(async () => {
    process.env.RECIPE_PALS_PUBLIC_RECIPE_API =
      'https://api.example.org/functions/v1/recipe-share-public';
    let reply;
    let redirectPolicy;
    globalThis.fetch = async (_url, options) => {
      redirectPolicy = options.redirect;
      if (reply === 'reject') throw new Error('Upstream request failed');
      return reply;
    };

    await withGuestServer(async base => {
      for (const code of [404, 410]) {
        reply = new Response('', { status: code });
        const res = await guestRequest(base);
        assert.equal(res.status, 404);
        assert.match(await res.text(), /Recipe unavailable/);
        assert.equal(redirectPolicy, 'error');
      }

      reply = new Response('', {
        status: 302,
        headers: { Location: 'http://169.254.169.254/latest/meta-data/' },
      });
      const redirected = await guestRequest(base);
      assert.equal(redirected.status, 503);
      assert.doesNotMatch(await redirected.text(), /169\.254\.169\.254/);
      assert.equal(redirectPolicy, 'error');

      reply = 'reject';
      const failed = await guestRequest(base);
      assert.equal(failed.status, 503);
      assert.match(await failed.text(), /Temporarily unavailable/);
    });
  });
});

test('invalid routes and methods preserve existing public-web responses', async () => {
  await withEnvironment(async () => {
    delete process.env.RECIPE_PALS_PUBLIC_RECIPE_API;
    globalThis.fetch = async () => {
      throw new Error('Invalid route must not call the API');
    };
    await withGuestServer(async base => {
      assert.equal((await nativeFetch(`${base}/r/short`)).status, 404);
      assert.equal((await nativeFetch(`${base}/r/abcdefgh`, { method: 'POST' })).status, 405);
    });
  });
});
