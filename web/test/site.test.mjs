import test from 'node:test';
import assert from 'node:assert/strict';
import { storeURL, siteURL } from '../lib/site.mjs';

test('download and canonical configuration reject malformed destinations', () => {
  const oldStore = process.env.RECIPE_PALS_APP_STORE_URL;
  const oldSite = process.env.RECIPE_PALS_SITE_URL;
  try {
    for (const value of ['', 'https://example.org/id1234', 'http://apps.apple.com/app/id1234',
      'https://user@apps.apple.com/app/id1234', 'https://apps.apple.com/app/id1234?token=secret']) {
      process.env.RECIPE_PALS_APP_STORE_URL = value;
      assert.equal(storeURL(), null);
    }
    process.env.RECIPE_PALS_APP_STORE_URL = 'https://apps.apple.com/us/app/example/id1234';
    assert.equal(storeURL(), process.env.RECIPE_PALS_APP_STORE_URL);
    for (const value of ['', 'http://example.org', 'https://user@example.org', 'https://example.org/private']) {
      process.env.RECIPE_PALS_SITE_URL = value;
      assert.equal(siteURL(), null);
    }
    process.env.RECIPE_PALS_SITE_URL = 'https://example.org';
    assert.equal(siteURL().href, 'https://example.org/');
  } finally {
    if (oldStore === undefined) delete process.env.RECIPE_PALS_APP_STORE_URL;
    else process.env.RECIPE_PALS_APP_STORE_URL = oldStore;
    if (oldSite === undefined) delete process.env.RECIPE_PALS_SITE_URL;
    else process.env.RECIPE_PALS_SITE_URL = oldSite;
  }
});
