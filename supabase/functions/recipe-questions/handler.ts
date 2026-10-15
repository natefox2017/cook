// Developer: gengyun
// Purpose: Bounded, owner-scoped recipe Q&A orchestration over typed provider and metering ports.

import { AppError } from "../_shared/errors.ts";
import { canonicalHash } from "../recipe-draft-sessions/canonicalJSON.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const MAX_QUESTION_CHARS = 1000;
const MAX_ANSWER_CHARS = 2000;
const MAX_TURN_CHARS = 1000;
const MAX_SNAPSHOT_TITLE_CHARS = 500;
const MAX_SNAPSHOT_SOURCE_CHARS = 2048;
const MAX_SNAPSHOT_ITEMS = 64;
const MAX_SNAPSHOT_ITEM_CHARS = 1000;
const MAX_HISTORY_TURNS = 5;
const MAX_STATEMENTS = 20;
const DEFAULT_DEADLINE_MS = 30_000;

export type QuestionStatementKind = "recipe" | "ai";

export interface QuestionSnapshot {
  title: string;
  ingredients: string[];
  steps: string[];
  source: string | null;
}

export interface QuestionTurn {
  question: string;
  answer: string;
}

export interface QuestionRequest {
  recipe_id: string;
  revision: number;
  snapshot: QuestionSnapshot;
  question: string;
  history: QuestionTurn[];
  operation_id: string;
}

export interface QuestionStatement {
  kind: QuestionStatementKind;
  text: string;
}

export interface QuestionProviderResult {
  answer: string;
  statements: QuestionStatement[];
  usage: { total_tokens: number };
}

export interface QuestionProviderPort {
  answer(
    input: {
      snapshot: QuestionSnapshot;
      history: QuestionTurn[];
      question: string;
    },
    signal: AbortSignal,
  ): Promise<QuestionProviderResult>;
}

export interface QuestionOperation {
  operation_id: string;
  owner_id: string;
  capability: "recipe_question";
  input_hash: string;
}

export interface QuestionMeteringPort {
  reserve(operation: QuestionOperation): Promise<void>;
  settle(operation: QuestionOperation): Promise<void>;
  release(operation: QuestionOperation): Promise<void>;
}

export interface QuestionResponse {
  operation_id: string;
  answer: string;
  statements: QuestionStatement[];
  revision: number;
}

export interface QuestionHandlerDependencies {
  provider: QuestionProviderPort;
  metering: QuestionMeteringPort;
  deadline_ms?: number;
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function unicodeLength(value: string): number {
  return [...value].length;
}

function boundedText(
  value: unknown,
  minimum: number,
  maximum: number,
): value is string {
  if (typeof value !== "string") return false;
  const length = unicodeLength(value);
  return length >= minimum && length <= maximum;
}

function stringList(
  value: unknown,
  maxItems: number,
  maxChars: number,
): value is string[] {
  if (!Array.isArray(value) || value.length > maxItems) return false;
  return value.every((entry) => boundedText(entry, 1, maxChars));
}

function snapshot(value: unknown): QuestionSnapshot | null {
  const record = asRecord(value);
  if (!record) return null;
  if (!boundedText(record.title, 1, MAX_SNAPSHOT_TITLE_CHARS)) return null;
  if (!stringList(record.ingredients, MAX_SNAPSHOT_ITEMS, MAX_SNAPSHOT_ITEM_CHARS)) return null;
  if (!stringList(record.steps, MAX_SNAPSHOT_ITEMS, MAX_SNAPSHOT_ITEM_CHARS)) return null;
  if (record.source !== null && !boundedText(record.source, 1, MAX_SNAPSHOT_SOURCE_CHARS)) return null;
  return {
    title: record.title as string,
    ingredients: record.ingredients as string[],
    steps: record.steps as string[],
    source: record.source as string | null,
  };
}

function turn(value: unknown): QuestionTurn | null {
  const record = asRecord(value);
  if (!record) return null;
  if (!boundedText(record.question, 1, MAX_TURN_CHARS)) return null;
  if (!boundedText(record.answer, 1, MAX_ANSWER_CHARS)) return null;
  return { question: record.question as string, answer: record.answer as string };
}

/**
 * Validates the wire request into a typed, bounded QuestionRequest. Unknown keys are
 * tolerated here because the HTTP body is JSON decoded upstream; every used field is
 * strictly bounded so the provider and metering never see unbounded user data.
 */
export function validateQuestionRequest(value: unknown): QuestionRequest {
  const record = asRecord(value);
  if (!record) {
    throw new AppError("validation_error", "Expected a JSON object", 422);
  }
  if (!isUUID(record.recipe_id)) {
    throw new AppError("validation_error", "recipe_id must be a canonical UUID", 422);
  }
  if (!Number.isSafeInteger(record.revision) || (record.revision as number) < 1) {
    throw new AppError("validation_error", "revision must be a positive integer", 422);
  }
  const parsedSnapshot = snapshot(record.snapshot);
  if (!parsedSnapshot) {
    throw new AppError("validation_error", "snapshot is missing or exceeds bounds", 422);
  }
  if (!boundedText(record.question, 1, MAX_QUESTION_CHARS)) {
    throw new AppError(
      "validation_error",
      `question must be 1..${MAX_QUESTION_CHARS} characters`,
      422,
    );
  }
  if (!Array.isArray(record.history) || record.history.length > MAX_HISTORY_TURNS) {
    throw new AppError(
      "validation_error",
      `history must have at most ${MAX_HISTORY_TURNS} turns`,
      422,
    );
  }
  const history = record.history.map(turn);
  if (history.some((entry) => entry === null)) {
    throw new AppError("validation_error", "history turn is malformed", 422);
  }
  if (!isUUID(record.operation_id)) {
    throw new AppError("validation_error", "operation_id must be a canonical UUID", 422);
  }
  return {
    recipe_id: record.recipe_id as string,
    revision: record.revision as number,
    snapshot: parsedSnapshot,
    question: record.question as string,
    history: history as QuestionTurn[],
    operation_id: record.operation_id as string,
  };
}

/** Lowercase SHA-256 of the canonical request; stable across reserve/settle and detects replay. */
export async function questionInputHash(request: QuestionRequest): Promise<string> {
  return await canonicalHash({
    capability: "recipe_question",
    recipe_id: request.recipe_id,
    revision: request.revision,
    snapshot: request.snapshot,
    question: request.question,
    history: request.history,
  });
}

function statement(value: unknown): QuestionStatement | null {
  const record = asRecord(value);
  if (!record) return null;
  if (record.kind !== "recipe" && record.kind !== "ai") return null;
  if (!boundedText(record.text, 1, MAX_ANSWER_CHARS)) return null;
  return { kind: record.kind, text: record.text as string };
}

/**
 * Validates and bounds the provider result. A malformed or oversized answer is treated
 * as unsafe output: the handler never surfaces it and never settles metering for it.
 */
export function boundAnswer(value: unknown): {
  answer: string;
  statements: QuestionStatement[];
  usage: { total_tokens: number };
} {
  const record = asRecord(value);
  if (!record) {
    throw new AppError("internal_error", "Provider returned an invalid answer", 422);
  }
  if (!boundedText(record.answer, 1, MAX_ANSWER_CHARS)) {
    throw new AppError("internal_error", "Provider answer exceeds bounds", 422);
  }
  if (!Array.isArray(record.statements) || record.statements.length > MAX_STATEMENTS) {
    throw new AppError("internal_error", "Provider statements exceed bounds", 422);
  }
  const statements = record.statements.map(statement);
  if (statements.some((entry) => entry === null)) {
    throw new AppError("internal_error", "Provider statement is malformed", 422);
  }
  const usageRecord = asRecord(record.usage);
  if (
    !usageRecord ||
    !Number.isSafeInteger(usageRecord.total_tokens) ||
    (usageRecord.total_tokens as number) < 0
  ) {
    throw new AppError("internal_error", "Provider usage is malformed", 422);
  }
  return {
    answer: record.answer as string,
    statements: statements as QuestionStatement[],
    usage: { total_tokens: usageRecord.total_tokens as number },
  };
}

/**
 * Bounded Q&A orchestration. The handler is network-free: the provider calls the model,
 * the metering port records the commercial operation, and every failure path releases the
 * reservation so a failed, unsafe or timed-out answer never settles as a successful unit.
 */
export function createQuestionHandler(dependencies: QuestionHandlerDependencies) {
  const deadlineMs = dependencies.deadline_ms ?? DEFAULT_DEADLINE_MS;
  return async function handleQuestion(
    request: QuestionRequest,
    ownerID: string,
  ): Promise<QuestionResponse> {
    const inputHash = await questionInputHash(request);
    const operation: QuestionOperation = {
      operation_id: request.operation_id,
      owner_id: ownerID,
      capability: "recipe_question",
      input_hash: inputHash,
    };
    await dependencies.metering.reserve(operation);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), deadlineMs);
    try {
      const result = await dependencies.provider.answer(
        {
          snapshot: request.snapshot,
          history: request.history,
          question: request.question,
        },
        controller.signal,
      );
      const bounded = boundAnswer(result);
      await dependencies.metering.settle(operation);
      return {
        operation_id: request.operation_id,
        answer: bounded.answer,
        statements: bounded.statements,
        revision: request.revision,
      };
    } catch (error) {
      await dependencies.metering.release(operation);
      if (controller.signal.aborted) {
        throw new AppError(
          "internal_error",
          "The question timed out before an answer was verified.",
          503,
        );
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }
  };
}
