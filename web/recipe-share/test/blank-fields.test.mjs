// Developer: gengyun
// Purpose: Reject blank public ingredients and instructions at the actual guest request handler without sockets.
import test from 'node:test';
import assert from 'node:assert/strict';
import {validatePublicRecipe, renderRecipePage} from '../src/page.mjs';
import {createRecipeServer} from '../src/server.mjs';

const sample = {
  title: 'Soup', summary: 'A simple meal', sourceURL: null,
  servings: 2, prepMinutes: 5, cookMinutes: 10,
  ingredients: [{name: 'Salt', amountText: 'to taste'}],
  steps: [{title: '', instruction: 'Stir gently.'}],
};
async function guest(recipe, method = 'GET') {
  const server = createRecipeServer({loadRecipe: async () => recipe});
  const response = {
    headers: {},
    setHeader(name, value) {this.headers[name.toLowerCase()] = value;},
    writeHead(status, headers) {
      this.status = status;
      for (const [name, value] of Object.entries(headers ?? {})) this.setHeader(name, value);
      return this;
    },
    end(body) {this.body = body;},
  };
  // Exercise the original asynchronous listener, without binding a port.
  await server.listeners('request')[0]({method, url: '/r/abcdefgh'}, response);
  return response;
}

test('whitespace-only ingredient names and instructions fail closed at validation and guest handler', async () => {
  for (const whitespace of [' ', '\t\n\r', '\u00a0', '\u3000']) {
    for (const field of ['ingredient', 'instruction']) {
      const recipe = structuredClone(sample);
      if (field === 'ingredient') recipe.ingredients[0].name = whitespace;
      else recipe.steps[0].instruction = whitespace;
      assert.equal(validatePublicRecipe(recipe), null, field);
      assert.throws(() => renderRecipePage(recipe), /Invalid public recipe payload/);
      const response = await guest(recipe);
      assert.equal(response.status, 503);
      assert.match(response.headers['cache-control'], /no-store/);
      assert.match(response.body, /Temporarily unavailable/);
      assert.doesNotMatch(response.body, /A simple meal|Stir gently/);
    }
  }
});

test('valid surrounding whitespace is preserved, and optional empty amounts and step titles remain supported', async () => {
  const recipe = structuredClone(sample);
  recipe.ingredients[0] = {name: ' Salt ', amountText: ''};
  recipe.steps[0] = {title: '', instruction: ' Stir gently. '};
  assert.deepEqual(validatePublicRecipe(recipe), recipe);
  const get = await guest(recipe);
  assert.equal(get.status, 200);
  assert.match(get.body, / Salt /);
  assert.match(get.body, / Stir gently\. /);
  assert.match(get.headers['cache-control'], /no-store/);
  const head = await guest(recipe, 'HEAD');
  assert.equal(head.status, 200);
  assert.equal(head.body, '');
});

test('literal HTML in valid fields remains escaped at the guest boundary', async () => {
  const recipe = structuredClone(sample);
  recipe.ingredients[0].name = '<script>ingredient</script>';
  recipe.steps[0].instruction = '<img src=x onerror=alert(1)>';
  const response = await guest(recipe);
  assert.equal(response.status, 200);
  assert.match(response.body, /&lt;script&gt;ingredient&lt;\/script&gt;/);
  assert.match(response.body, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.doesNotMatch(response.body, /<script>|<img src=x/);
});
