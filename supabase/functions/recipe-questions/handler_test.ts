// Developer: gengyun
// Purpose: Bounded recipe Q&A handler regression: cross-owner, over-limit, replay, timeout, unsafe output.

import test from "node:test";
import assert from "node:assert/strict";
import {
  boundAnswer,
  createQuestionHandler,
  validateQuestionRequest,
  type QuestionProviderPort,
  type QuestionProviderResult,
  type QuestionRequest,
} from "./handler.ts";
import { createInMemoryQuestionMetering } from "./questionMetering.ts";

const owner = "a0000000-0000-4000-8000-000000000001";
const other = "a0000000-0000-4000-8000-000000000002";

function validRequest(overrides: Partial<QuestionRequest> = {}): QuestionRequest {
  return {
    recipe_id: "b0000000-0000-4000-8000-000000000003",
    revision: 3,
    snapshot: {
      title: "Tomato Soup",
      ingredients: ["tomatoes", "onion"],
      steps: ["Simmer the tomatoes until soft."],
      source: "https://recipes.example/soup",
    },
    question: "How long do I simmer?",
    history: [],
    operation_id: "c0000000-0000-4000-8000-000000000004",
    ...overrides,
  };
}

const answered: QuestionProviderResult = {
  answer: "Simmer until soft; adding cream is not stated.",
  statements: [
    { kind: "recipe", text: "Simmer the tomatoes until soft." },
    { kind: "ai", text: "Adding cream is not in the recipe." },
  ],
  usage: { total_tokens: 12 },
};

function fixedProvider(result: unknown): QuestionProviderPort {
  return {
    async answer(): Promise<QuestionProviderResult> {
      if (result instanceof Error) throw result;
      return result as QuestionProviderResult;
    },
  };
}

test("rejects a question exceeding 1000 characters", () => {
  assert.throws(
    () => validateQuestionRequest(validRequest({ question: "x".repeat(1001) })),
    (error: { code?: string }) => error.code === "validation_error",
  );
});

test("rejects an over-large snapshot", () => {
  assert.throws(
    () =>
      validateQuestionRequest(
        validRequest({ snapshot: { title: "T", ingredients: [], steps: [], source: "s".repeat(2049) } }),
      ),
    (error: { code?: string }) => error.code === "validation_error",
  );
});

test("rejects history beyond five turns", () => {
  const history = Array.from({ length: 6 }, () => ({
    question: "q",
    answer: "a",
  }));
  assert.throws(
    () => validateQuestionRequest(validRequest({ history })),
    (error: { code?: string }) => error.code === "validation_error",
  );
});

test("forbids reusing an operation id owned by another owner", async () => {
  const handler = createQuestionHandler({
    provider: fixedProvider(answered),
    metering: createInMemoryQuestionMetering(),
  });
  await handler(validRequest(), owner);
  await assert.rejects(
    () => handler(validRequest({ question: "Different?" }), other),
    (error: { code?: string }) => error.code === "forbidden",
  );
});

test("conflicts when the same operation id carries different input", async () => {
  const handler = createQuestionHandler({
    provider: fixedProvider(answered),
    metering: createInMemoryQuestionMetering(),
  });
  await handler(validRequest(), owner);
  await assert.rejects(
    () => handler(validRequest({ question: "Another question?" }), owner),
    (error: { code?: string }) => error.code === "conflict",
  );
});

test("settles once across an identical replay", async () => {
  let settleCalls = 0;
  const metering = createInMemoryQuestionMetering();
  const counting = {
    async reserve(operation: Parameters<typeof metering.reserve>[0]) {
      await metering.reserve(operation);
    },
    async settle(operation: Parameters<typeof metering.settle>[0]) {
      settleCalls += 1;
      await metering.settle(operation);
    },
    async release(operation: Parameters<typeof metering.release>[0]) {
      await metering.release(operation);
    },
  };
  const handler = createQuestionHandler({ provider: fixedProvider(answered), metering: counting });
  const request = validRequest();
  await handler(request, owner);
  await handler(request, owner);
  assert.equal(settleCalls, 2);
  assert.doesNotThrow(() => handler(request, owner));
});

test("times out and releases without settling", async () => {
  const metering = createInMemoryQuestionMetering();
  let settled = false;
  const counting = {
    async reserve(operation: Parameters<typeof metering.reserve>[0]) {
      await metering.reserve(operation);
    },
    async settle(operation: Parameters<typeof metering.settle>[0]) {
      settled = true;
      await metering.settle(operation);
    },
    async release(operation: Parameters<typeof metering.release>[0]) {
      await metering.release(operation);
    },
  };
  const hanging: QuestionProviderPort = {
    answer(_input, signal) {
      return new Promise<QuestionProviderResult>((_resolve, reject) => {
        signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
      });
    },
  };
  const handler = createQuestionHandler({
    provider: hanging,
    metering: counting,
    deadline_ms: 20,
  });
  await assert.rejects(
    () => handler(validRequest(), owner),
    (error: { status?: number }) => error.status === 503,
  );
  assert.equal(settled, false);
});

test("preserves recipe versus AI statement marks", async () => {
  const handler = createQuestionHandler({
    provider: fixedProvider(answered),
    metering: createInMemoryQuestionMetering(),
  });
  const response = await handler(validRequest(), owner);
  assert.equal(response.statements.length, 2);
  assert.equal(response.statements[0].kind, "recipe");
  assert.equal(response.statements[1].kind, "ai");
});

test("rejects unsafe oversized answers without settling", async () => {
  const oversized = {
    answer: "x".repeat(2001),
    statements: [],
    usage: { total_tokens: 1 },
  };
  let settled = false;
  const metering = createInMemoryQuestionMetering();
  const counting = {
    async reserve(operation: Parameters<typeof metering.reserve>[0]) {
      await metering.reserve(operation);
    },
    async settle(operation: Parameters<typeof metering.settle>[0]) {
      settled = true;
      await metering.settle(operation);
    },
    async release(operation: Parameters<typeof metering.release>[0]) {
      await metering.release(operation);
    },
  };
  const handler = createQuestionHandler({
    provider: fixedProvider(oversized),
    metering: counting,
  });
  await assert.rejects(
    () => handler(validRequest(), owner),
    (error: { status?: number }) => error.status === 422,
  );
  assert.equal(settled, false);
});

test("boundAnswer rejects a malformed statement kind", () => {
  assert.throws(
    () =>
      boundAnswer({
        answer: "ok",
        statements: [{ kind: "guess", text: "not a real kind" }],
        usage: { total_tokens: 1 },
      }),
    (error: { status?: number }) => error.status === 422,
  );
});
