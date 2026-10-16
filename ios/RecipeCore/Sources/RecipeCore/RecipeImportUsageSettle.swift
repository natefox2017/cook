// Developer: gengyun
// Purpose: Optional commercial settle port for the normal single-recipe import save; the freeTest path stays unmetered.

import Foundation

@MainActor
public enum RecipeImportUsageSettleOutcome: Sendable {
    /// The server settle committed and the recipe was persisted locally under the server-authored ID.
    case settled(recipeID: UUID, payloadHash: String)
    /// Quota or an upgrade is required; the original receipt is kept and no recipe was saved locally.
    case awaitingUpgrade
}

/// Optional commercial usage port injected into the normal import save. `nil` keeps the freeTest
/// save byte-equivalent and unmetered. The port owns durable reserve, server finalize, the local
/// `persist` (invoked with the server-authored recipe ID), and the final acknowledge; a quota or
/// upgrade outcome returns `.awaitingUpgrade` and never invokes `persist`.
@MainActor
public protocol RecipeImportUsageSettling {
    func settle(
        ownerID: UUID,
        jobID: UUID,
        receiptID: UUID,
        persist: @escaping @MainActor (_ recipeID: UUID) throws -> Void
    ) async throws -> RecipeImportUsageSettleOutcome
}

/// Adapts the low-level `RecipeImportUsageBridge` reserve/finalize/acknowledge lifecycle into the
/// single-shot settle port the normal import save consumes. A single-result import settles the frozen
/// `primary` candidate; the server recomputes the payload from the owned job and authors the recipe ID.
@MainActor
public struct RecipeImportUsageSettleAdapter: RecipeImportUsageSettling {
    /// Frozen DEV-427 candidate identity for a single-result import job (no candidate_recipes list).
    public static let primaryCandidateID = "primary"

    private let bridge: RecipeImportUsageBridge

    public init(bridge: RecipeImportUsageBridge) {
        self.bridge = bridge
    }

    public func settle(
        ownerID: UUID,
        jobID: UUID,
        receiptID: UUID,
        persist: @escaping @MainActor (_ recipeID: UUID) throws -> Void
    ) async throws -> RecipeImportUsageSettleOutcome {
        let outcome = try await bridge.reserve(
            ownerID: ownerID,
            jobID: jobID,
            candidateID: Self.primaryCandidateID,
            receiptID: receiptID
        )
        switch outcome {
        case .awaitingUpgrade:
            return .awaitingUpgrade
        case .reserved(let reservation):
            let operation = RecipeImportUsageOperation(
                operationID: RecipeImportUsageOperation.stableOperationID(
                    ownerID: ownerID,
                    jobID: jobID,
                    candidateID: Self.primaryCandidateID
                ),
                ownerID: ownerID,
                jobID: jobID,
                candidateID: Self.primaryCandidateID,
                receiptID: receiptID,
                state: .reserved,
                reservedUntil: reservation.reservedUntil
            )
            let response = try await bridge.finalize(ownerID: ownerID, operation: operation)
            guard let recipeID = UUID(uuidString: response.recipeID) else {
                throw RecipeAccessContractError.invalidResponse
            }
            try persist(recipeID)
            try await bridge.acknowledge(ownerID: ownerID, operation: operation)
            return .settled(recipeID: recipeID, payloadHash: response.payloadHash)
        }
    }
}
