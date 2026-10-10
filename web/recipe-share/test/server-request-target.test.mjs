// Developer: gengyun
// Purpose: Keep malformed guest HTTP request targets from terminating the recipe reader.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createConnection } from 'node:net';
import { createRecipeServer } from '../src/server.mjs';

const sample = {
  title: 'Soup', summary: 'A simple meal', sourceURL: null,
  servings: 2, prepMinutes: 5, cookMinutes: 10,
  ingredients: [], steps: [],
};

function sendRawRequest(port, target) {
  return new Promise((resolve, reject) => {
    const socket = createConnection({ host: '127.0.0.1', port });
    let response = '';
    let settled = false;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      if (error) reject(error);
      else resolve(response);
    };
    socket.setTimeout(3_000, () => finish(new Error('Raw HTTP request timed out')));
    socket.on('connect', () => {
      socket.write('GET ' + target + ' HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n');
    });
    socket.on('data', chunk => { response += chunk.toString('utf8'); });
    socket.on('end', () => finish());
    socket.on('error', finish);
    socket.on('close', () => finish());
  });
}

test('malformed raw request targets fail without crashing or loading recipes', async () => {
  let loads = 0;
  const server = createRecipeServer({ loadRecipe: async () => {
    loads += 1;
    return sample;
  } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const url = 'http://127.0.0.1:' + port;
  try {
    for (const target of [
      'http://[broken]/r/abcdefgh',
      'http://%ZZ/r/abcdefgh',
      '//[bad]/r/abcdefgh',
    ]) {
      const response = await sendRawRequest(port, target);
      assert.match(response, /^HTTP\/1\.1 (?:400|404)\b/, 'unexpected response to ' + target);
      if (/^HTTP\/1\.1 404\b/.test(response)) {
        assert.match(response.toLowerCase(), /cache-control: private, no-store, max-age=0/);
        assert.match(response.toLowerCase(), /content-security-policy: default-src 'none'/);
      }
      assert.doesNotMatch(response, /broken|%ZZ|\[bad\]|stack|typeerror|invalid url/i);
      assert.equal(loads, 0, 'invalid target loaded recipe: ' + target);
    }

    // The same process must still serve valid routes after all invalid requests.
    const get = await fetch(url + '/r/abcdefgh');
    assert.equal(get.status, 200);
    assert.match(await get.text(), /Soup/);
    assert.equal(loads, 1);
    const head = await fetch(url + '/r/abcdefgh', { method: 'HEAD' });
    assert.equal(head.status, 200);
    assert.equal(await head.text(), '');
    assert.equal(loads, 2);
    const css = await fetch(url + '/styles.css');
    assert.equal(css.status, 200);
    assert.match(css.headers.get('content-type'), /text\/css/);
    assert.equal((await fetch(url + '/r/not-allowed!')).status, 404);
    assert.equal((await fetch(url + '/r/abcdefgh', { method: 'POST' })).status, 405);
    assert.equal(loads, 2);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
