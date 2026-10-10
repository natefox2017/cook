// Developer: gengyun
// Purpose: Test pure multi-recipe candidate identity without Deno or a live database.

import test from "node:test";
import assert from "node:assert/strict";
import { stableCandidateIDs } from "./candidateIdentity.ts";

const soup = {
  title: "Soup",
  ingredients: ["200 ml stock"],
  steps: ["Simmer stock."],
};
const pasta = {
  title: "Pasta",
  ingredients: ["100 g pasta"],
  steps: ["Boil pasta."],
};
const pie = {
  title: "Pie",
  ingredients: ["1 apple"],
  steps: ["Bake the pie."],
};

test("stable candidate IDs ignore sibling order or insertion", () => {
  const original = stableCandidateIDs([soup, pasta]);
  const reordered = stableCandidateIDs([pasta, soup]);
  const inserted = stableCandidateIDs([pie, soup, pasta]);
  assert.deepEqual(original, reordered.toReversed());
  assert.deepEqual(original, inserted.slice(1));
  for (const id of original) {
    assert.match(id, /^candidate-v2-[a-f0-9]{32}$/);
  }
});

test("identical recipe occurrences have unique deterministic suffixes", () => {
  const first = stableCandidateIDs([soup, soup, pasta, soup]);
  const repeated = stableCandidateIDs([soup, soup, pasta, soup]);
  assert.deepEqual(first, repeated);
  assert.equal(first[1], first[0] + "-2");
  assert.equal(first[3], first[0] + "-3");
  assert.equal(new Set(first).size, 4);
});

test("changing saved recipe facts changes only that candidate fingerprint", () => {
  const original = stableCandidateIDs([soup, pasta]);
  const changed = stableCandidateIDs([
    { ...soup, steps: ["Simmer until done."] },
    pasta,
  ]);
  assert.notEqual(original[0], changed[0]);
  assert.equal(original[1], changed[1]);
  assert.deepEqual(stableCandidateIDs([soup, pasta]), original);
});

test("Unicode canonical equivalents generate the same identity", () => {
  const composed = { ...soup, title: "Crème brûlée" };
  const decomposed = { ...soup, title: "Cre\u0300me bru\u0302le\u0301e" };
  assert.equal(stableCandidateIDs([composed])[0], stableCandidateIDs([decomposed])[0]);
});

test("fingerprinting does not mutate caller recipes or require a source ID", () => {
  const frozen = Object.freeze({
    title: "Kimchi soup",
    ingredients: Object.freeze(["to taste"]),
    steps: Object.freeze(["Simmer gently."]),
  });
  const before = JSON.stringify(frozen);
  const id = stableCandidateIDs([frozen])[0];
  assert.match(id, /^candidate-v2-[a-f0-9]{32}$/);
  assert.equal(JSON.stringify(frozen), before);
});
