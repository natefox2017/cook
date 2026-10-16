// Developer: gengyun
// Purpose: DEV-78 media-import save orchestration over the recipe-media-save client, persisting the
//          per-candidate durable intent in the existing operation store before the bundle RPC.

import Foundation

@MainActor
public enum RecipeMediaBundleReserveOutcome: Sendable {
    /// The bundle reserved (media + one smart_import unit per candidate). `operations` are the stored
    /// `.reserved` candidate operations the View finalizes through the existing DEV-430 bridge.
    case reserved(response: RecipeMediaBundleReserveResponse, operations: [RecipeImportUsageOperation])
    /// Quota or an upgrade is required; the receipt is kept, the intents stay `awaitingUpgrade`, and
    /// nothing was charged.
    case awaitingUpgrade
}

/// Thin bundle port the View/integration consumes. `reserveBundle` persists each child's stable
/// `.reserving` intent in the existing operation store before the bundle RPC, maps the `.reserved`
/// responses back onto those operations, and returns them so the View never raw-client reserves or
/// reconstructs a lost operation. Per-candidate smart_import finalize/ACK stays the DEV-430 flow;
/// only the media_import unit is finalized/released here.
@MainActor
public struct RecipeMediaBundlePort {
    public let client: any RecipeMediaSaveClient
    public let store: RecipeImportUsageStore

    public init(client: any RecipeMediaSaveClient, store: RecipeImportUsageStore) {
        self.client = client
        self.store = store
    }

    /// Reserves the media bundle for the given selected candidates. A 402/409 quota/upgrade block
    /// returns `.awaitingUpgrade` without charging; other failures propagate and leave the `.reserving`
    /// intents in place so a retry replays the same stable operation IDs.
    public func reserveBundle(
        ownerID: UUID,
        jobID: UUID,
        candidateIDs: [String],
        receiptID: UUID,
        currentOwner: @escaping @MainActor () -> (ownerID: UUID?, generation: Int)
    ) async throws -> RecipeMediaBundleReserveOutcome {
        let start = currentOwner()
        guard start.ownerID == ownerID else {
            throw RecipeUsageFailure.api(
                .ownerMismatch, recoverable: false,
                message: "The signed-in account changed while reserving the import.", requestID: nil)
        }
        let startGeneration = start.generation

        // Durable intent must exist before the network call so a crash/replay derives the same
        // operation IDs and the existing store can recover each child.
        var pending: [RecipeImportUsageOperation] = []
        for candidateID in candidateIDs {
            let operation = RecipeImportUsageOperation(
                operationID: RecipeImportUsageOperation.stableOperationID(
                    ownerID: ownerID, jobID: jobID, candidateID: candidateID),
                ownerID: ownerID,
                jobID: jobID,
                candidateID: candidateID,
                receiptID: receiptID,
                state: .reserving
            )
            try store.save(operation)
            pending.append(operation)
        }

        do {
            let response = try await client.reserveMediaBundle(
                ownerID: ownerID, jobID: jobID, candidateIDs: candidateIDs)
            try requireOwner(ownerID, generation: startGeneration, currentOwner: currentOwner)

            var reserved: [RecipeImportUsageOperation] = []
            for candidate in response.candidates {
                guard let candidateID = candidate.candidateID else { continue }
                let operation = RecipeImportUsageOperation(
                    operationID: RecipeImportUsageOperation.stableOperationID(
                        ownerID: ownerID, jobID: jobID, candidateID: candidateID),
                    ownerID: ownerID,
                    jobID: jobID,
                    candidateID: candidateID,
                    receiptID: receiptID,
                    state: .reserved,
                    reservedUntil: candidate.reservedUntil
                )
                try store.save(operation)
                reserved.append(operation)
            }
            return .reserved(response: response, operations: reserved)
        } catch let error as RecipeMediaSaveAPIError
            where error.code == "UPGRADE_REQUIRED" || error.code == "QUOTA_EXCEEDED"
        {
            for operation in pending {
                try store.save(operation.marking(state: .awaitingUpgrade))
            }
            return .awaitingUpgrade
        }
    }

    /// Settles the reserved media_import unit. The server derives the payload/hash from the owned
    /// persisted job result, so the client sends only the job id and never authors the payload. The
    /// returned `code` is authoritative (`FINALIZED` means settled).
    public func finalizeMedia(
        ownerID: UUID,
        jobID: UUID,
        currentOwner: @escaping @MainActor () -> (ownerID: UUID?, generation: Int)
    ) async throws -> RecipeMediaActionResponse {
        let start = currentOwner()
        guard start.ownerID == ownerID else {
            throw RecipeUsageFailure.api(
                .ownerMismatch, recoverable: false,
                message: "The signed-in account changed while finalizing the import.", requestID: nil)
        }
        let startGeneration = start.generation
        try requireOwner(ownerID, generation: startGeneration, currentOwner: currentOwner)
        let response = try await client.finalizeMedia(ownerID: ownerID, jobID: jobID)
        try requireOwner(ownerID, generation: startGeneration, currentOwner: currentOwner)
        return response
    }

    /// Best-effort release of a reserved media_import unit that will not be settled.
    public func releaseMedia(ownerID: UUID, jobID: UUID) async throws -> RecipeMediaActionResponse {
        try await client.releaseMedia(ownerID: ownerID, jobID: jobID)
    }

    private func requireOwner(
        _ ownerID: UUID,
        generation boundGeneration: Int,
        currentOwner: @MainActor () -> (ownerID: UUID?, generation: Int)
    ) throws {
        let current = currentOwner()
        guard current.ownerID == ownerID, current.generation == boundGeneration else {
            throw RecipeUsageFailure.api(
                .ownerMismatch,
                recoverable: false,
                message: "The signed-in account changed while saving the import.",
                requestID: nil
            )
        }
    }
}
