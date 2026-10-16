// Developer: gengyun
// Purpose: DEV-78 media-import save orchestration over the recipe-media-save client, with the same
//          owner/generation fence and fail-closed blocking as the DEV-430 settle port.

import Foundation

@MainActor
public enum RecipeMediaBundleReserveOutcome: Sendable {
    /// The bundle reserved (media + one smart_import unit per candidate).
    case reserved(RecipeMediaBundleReserveResponse)
    /// Quota or an upgrade is required; the receipt is kept and nothing was charged.
    case awaitingUpgrade
}

/// Thin bundle port the View/integration consumes. It reserves the media bundle atomically, then
/// finalizes or releases only the media_import unit; per-candidate smart_import finalize/ACK stays
/// the existing DEV-430 recipe-usage flow. No new queue or ledger is introduced.
@MainActor
public struct RecipeMediaBundlePort {
    public let client: any RecipeMediaSaveClient

    public init(client: any RecipeMediaSaveClient) {
        self.client = client
    }

    /// Reserves the media bundle for the given selected candidates. A 402/409 quota/upgrade block
    /// returns `.awaitingUpgrade` without charging; other failures propagate for a normal retry.
    public func reserveBundle(
        ownerID: UUID,
        jobID: UUID,
        candidateIDs: [String],
        currentOwner: @escaping @MainActor () -> (ownerID: UUID?, generation: Int)
    ) async throws -> RecipeMediaBundleReserveOutcome {
        let start = currentOwner()
        guard start.ownerID == ownerID else {
            throw RecipeUsageFailure.api(
                .ownerMismatch, recoverable: false,
                message: "The signed-in account changed while reserving the import.", requestID: nil)
        }
        let startGeneration = start.generation

        do {
            let response = try await client.reserveMediaBundle(
                ownerID: ownerID, jobID: jobID, candidateIDs: candidateIDs)
            try requireOwner(ownerID, generation: startGeneration, currentOwner: currentOwner)
            return .reserved(response)
        } catch let error as RecipeMediaSaveAPIError
            where error.code == "UPGRADE_REQUIRED" || error.code == "QUOTA_EXCEEDED"
        {
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
