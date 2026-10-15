// Developer: gengyun
// Purpose: Idempotent, owner-scoped recipe-question metering honoring settle-once semantics.

import { AppError } from "../_shared/errors.ts";
import type { QuestionMeteringPort, QuestionOperation } from "./handler.ts";

type MeteringState = "reserved" | "settled" | "released";

interface MeteringRecord {
  owner_id: string;
  input_hash: string;
  state: MeteringState;
}

/**
 * Bounded in-memory metering used by the handler and its tests. It enforces owner
 * scoping, replay detection and settle-once idempotency but deliberately does NOT
 * enforce the Premium 100-answers/month quota. Durable quota persistence is wired by
 * the unified ledger owner per DEV-425 and must not be claimed or bypassed here.
 */
export function createInMemoryQuestionMetering(): QuestionMeteringPort {
  const records = new Map<string, MeteringRecord>();

  function ownedRecord(operation: QuestionOperation): MeteringRecord | undefined {
    const record = records.get(operation.operation_id);
    if (!record) return undefined;
    if (record.owner_id !== operation.owner_id) {
      throw new AppError("forbidden", "Operation belongs to another owner", 403);
    }
    return record;
  }

  return {
    async reserve(operation: QuestionOperation): Promise<void> {
      const existing = records.get(operation.operation_id);
      if (!existing) {
        records.set(operation.operation_id, {
          owner_id: operation.owner_id,
          input_hash: operation.input_hash,
          state: "reserved",
        });
        return;
      }
      if (existing.owner_id !== operation.owner_id) {
        throw new AppError("forbidden", "Operation belongs to another owner", 403);
      }
      if (existing.input_hash !== operation.input_hash) {
        throw new AppError(
          "conflict",
          "Operation id reused with different input",
          409,
        );
      }
      // Idempotent replay of the same owner and input is a no-op.
    },

    async settle(operation: QuestionOperation): Promise<void> {
      const record = ownedRecord(operation);
      if (!record) return;
      // Settling an already-settled operation never double-counts.
      record.state = "settled";
    },

    async release(operation: QuestionOperation): Promise<void> {
      const record = ownedRecord(operation);
      if (!record) return;
      if (record.state !== "settled") record.state = "released";
    },
  };
}
