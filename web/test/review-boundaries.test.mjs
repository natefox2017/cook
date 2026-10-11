import test from 'node:test';
import assert from 'node:assert/strict';
import { validatePublicRecipe, safeStoreURL } from '../lib/public-recipe.mjs';
import { isValidShareToken, isValidReferralCode, validateAggregateShareEvent } from '../lib/referrals.mjs';
import { shareResponse } from '../lib/share.mjs';

test('public source citations reject local aliases and noncanonical trailing dots', () => {
  const recipe = { title: 'Test', summary: '', ingredients: [], steps: [] };
  for (const host of ['router.localhost', 'printer.localdomain', 'metadata.google.internal', 'example.org.']) {
    assert.equal(validatePublicRecipe({ ...recipe, sourceURL: `https://${host}/recipe` }), null);
  }
  assert.equal(validatePublicRecipe({ ...recipe, sourceURL: 'https://example.org/recipe' }).sourceURL,
    'https://example.org/recipe');
});

test('the shared store validator rejects credentialed and malformed destinations', () => {
  for (const url of ['https://user:password@apps.apple.com/app/id1234',
    'https://apps.apple.com:443/app/id1234', 'https://apps.apple.com/app/id1234\n',
    'https://apps.apple.com/app/id1234?token=secret']) {
    assert.equal(safeStoreURL(url), null);
  }
  assert.equal(safeStoreURL('https://apps.apple.com/us/app/example/id1234'),
    'https://apps.apple.com/us/app/example/id1234');
});

test('tokens ending in newlines are not accepted by regex end anchors', async () => {
  assert.equal(isValidShareToken('abcdefgh\n'), false);
  assert.equal(isValidReferralCode('abcdefghijklmnop\n'), false);
  assert.throws(() => validateAggregateShareEvent({ kind: 'copy_link', shareToken: 'abcdefgh',
    eventID: 'abcdefghijklmnop\n' }));
  const response = await shareResponse('abcdefgh\n', { api: 'https://api.example.org',
    fetcher: () => assert.fail('Invalid tokens must not trigger fetch') });
  assert.equal(response.status, 404);
});
