// Developer: gengyun
// Purpose: Durable, owner-scoped recipe-question metering over the DEV-427/438 phase-II ledger RPCs.
// It computes the canonical internal input_hash, fences before the provider, settles exactly once,
// and maps ledger codes to the handler's bounded AppError vocabulary.

import { AppError } from "../_shared/errors.ts";
import {
  computeInternalInputHash,
  finalizeInternal,
  internalSourceForQuestion,
  markDispatchedInternal,
  releaseInternal,
  reserveInternal,
  type InternalUsageRPC,
} from "../_shared/recipeInternalUsage.ts";
import type {
  QuestionMeteringPort,
  QuestionOperation,
} from "./handler.ts";

/** Map a ledger result code to a typed AppError; unknown/missing codes fail closed as 503. */
function fail(code: string | undefined): never {
  if (code === "UPGRADE_REQUIRED") {
    throw new AppError("forbidden", "Premium is required for recipe questions.", 402);
  }
  if (code === "QUOTA_EXCEEDED") {
    throw new AppError("conflict", "Monthly question quota reached.", 402);
  }
  if (code === "IDEMPOTENCY_CONFLICT") {
    throw new AppError("conflict", "Operation id reused with different input.", 409);
  }
  if (code === "NOT_FOUND") {
    throw new AppError("not_found", "The operation was not found.", 404);
  }
  if (code === "INVALID_INPUT") {
    throw new AppError("validation_error", "The metering request is malformed.", 422);
  }
  throw new AppError("internal_error", "The metering service is unavailable.", 503);
}

/**
 * Durable QuestionMeteringPort backed by the service-role phase-II ledger RPCs. The input hash is
 * derived from the frozen internal source {origin: recipe_question, recipe_id, turn_request_id} so a
 * retry with the same operation id replays the same reservation and never re-dispatches the provider.
 */
export function createLedgerQuestionMetering(
  rpc: InternalUsageRPC,
): QuestionMeteringPort {
  const sourceAndHash = async (operation: QuestionOperation) => {
    const source = internalSourceForQuestion(
      operation.recipe_id,
      operation.operation_id,
    );
    const inputHash = await computeInternalInputHash("recipe_question", source);
    return { source, inputHash };
  };

  return {
    async reserve(operation) {
      const { source, inputHash } = await sourceAndHash(operation);
      const result = await reserveInternal(
        rpc,
        operation.owner_id,
        operation.operation_id,
        "recipe_question",
        inputHash,
        source,
      );
      if (result.code === "RESERVED") return "reserved";
      if (result.code === "REPLAY") return "replay";
      fail(result.code);
    },

    async markDispatched(operation) {
      const result = await markDispatchedInternal(
        rpc,
        operation.owner_id,
        operation.operation_id,
      );
      if (result.code !== "DISPATCHED") {
        fail(result.code);
      }
    },

    async finalize(operation, payloadHash, payload, resultId) {
      const { source, inputHash } = await sourceAndHash(operation);
      const result = await finalizeInternal(
        rpc,
        operation.owner_id,
        operation.operation_id,
        "recipe_question",
        inputHash,
        source,
        operation.recipe_id,
        payloadHash,
        payload,
        "answer",
        resultId,
      );
      if (result.code !== "FINALIZED") {
        fail(result.code);
      }
    },

    async release(operation) {
      // Best-effort: a committed/released/expired reservation needs no release; an unknown-outcome
      // fence (dispatched_unknown, null generated_at) is never released by the ledger.
      await releaseInternal(rpc, operation.owner_id, operation.operation_id).catch(
        () => null,
      );
    },
  };
}
