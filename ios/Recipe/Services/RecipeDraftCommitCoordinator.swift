// Developer: gengyun
// Purpose: Implements the app-level draft commit handoff: durable intent, compose, finalize, local write, acknowledge, and relaunch recovery.

import Foundation
import RecipeCore

/// Re-fetches the draft session, its accepted terminal suggestions, and the approval receipt by ID
/// so relaunch recovery can re-compose after a crash. DEV-429 owns the concrete implementation
/// (reuses RecipeDraftService GET/replay of the persisted turn; never a new persistence type).
typealias RecipeDraftSessionLoader =
    @Sendable (_ sessionID: String, _ turnRequestID: String) async throws
    -> (RecipeDraftSession, [RecipeDraftSuggestion], RecipeDraftApprovalReceipt)

enum RecipeDraftCommitError: Error {
    case invalidRecipeID
}

/// App-level implementation of `RecipeDraftCommitHandoff`. It orchestrates the DEV-428/DEV-434
/// save contract without authoring the recipe or the store write: the compose step is injected
/// (DEV-428), the local write is injected (DEV-434), and finalize/ack use the frozen usage routes.
struct RecipeDraftCommitCoordinator: RecipeDraftCommitHandoff {
    let usage: RecipeUsageService
    let composer: RecipeDraftRecipeComposer
    let writer: RecipeFinalizedRecipeWriter
    let sessionLoader: RecipeDraftSessionLoader?

    func commit(
        session: RecipeDraftSession,
        suggestions: [RecipeDraftSuggestion],
        receipt: RecipeDraftApprovalReceipt,
        ownerID: UUID
    ) async throws {
        let ownerKey = ownerID.uuidString.lowercased()
        let pendingStore = RecipeDraftPendingCommitStore()

        // Durable intent BEFORE finalize. The canonical operation id is the turn's request id,
        // which the backend reserve already used (operation_id == turn_request_id == request_id).
        try pendingStore.save(
            RecipeDraftPendingCommit(
                ownerID: ownerKey,
                sessionID: receipt.sessionID,
                turnRequestID: receipt.turnRequestID,
                requestID: receipt.requestID,
                operationID: receipt.turnRequestID,
                selectedPaths: receipt.selectedPaths,
                status: .awaitingFinalize
            )
        )

        let recipe = try await composer(session, suggestions, receipt, ownerID)
        let finalized = try await finalize(receipt: receipt, ownerID: ownerID)
        guard let recipeID = UUID(uuidString: finalized.recipeID) else {
            throw RecipeDraftCommitError.invalidRecipeID
        }

        try pendingStore.save(
            RecipeDraftPendingCommit(
                ownerID: ownerKey,
                sessionID: receipt.sessionID,
                turnRequestID: receipt.turnRequestID,
                requestID: receipt.requestID,
                operationID: finalized.operationID,
                selectedPaths: receipt.selectedPaths,
                status: .finalized,
                recipeID: finalized.recipeID,
                payloadHash: finalized.payloadHash
            )
        )

        // Local write BEFORE acknowledge.
        try await writer(recipe, recipeID, ownerID)
        _ = try await usage.acknowledge(ownerID: ownerID, operationID: finalized.operationID)
        pendingStore.clear(ownerID: ownerKey)
    }

    /// Re-runs the still-owed part of a pending draft commit after a relaunch. Never mints a new
    /// reservation; finalize/ack are idempotent against the canonical operation id.
    func recoverPendingSettlements(ownerID: UUID) async {
        let ownerKey = ownerID.uuidString.lowercased()
        let pendingStore = RecipeDraftPendingCommitStore()
        guard let pending = pendingStore.load(ownerID: ownerKey), let sessionLoader else {
            return
        }
        do {
            let (session, suggestions, receipt) = try await sessionLoader(
                pending.sessionID, pending.turnRequestID)
            let recipe = try await composer(session, suggestions, receipt, ownerID)
            switch pending.status {
            case .awaitingFinalize:
                let finalized = try await finalize(receipt: receipt, ownerID: ownerID)
                guard let recipeID = UUID(uuidString: finalized.recipeID) else { return }
                try await writer(recipe, recipeID, ownerID)
                _ = try await usage.acknowledge(
                    ownerID: ownerID, operationID: finalized.operationID)
            case .finalized:
                guard let recipeID = UUID(uuidString: pending.recipeID ?? "") else { return }
                try await writer(recipe, recipeID, ownerID)
                _ = try await usage.acknowledge(
                    ownerID: ownerID, operationID: pending.operationID)
            }
            pendingStore.clear(ownerID: ownerKey)
        } catch {
            // Keep the durable intent for the next recovery attempt.
        }
    }

    private func finalize(
        receipt: RecipeDraftApprovalReceipt,
        ownerID: UUID
    ) async throws -> RecipeUsageFinalizeResponse {
        let source = try RecipeUsageSource(
            sessionID: receipt.sessionID, turnRequestID: receipt.turnRequestID)
        let inputHash = try RecipeUsageInputHash.compute(capability: .aiEdit, source: source)
        let request = try RecipeUsageFinalizeRequest(
            capability: .aiEdit, inputHash: inputHash, source: source)
        return try await usage.finalize(
            ownerID: ownerID, operationID: receipt.turnRequestID, request: request)
    }
}
