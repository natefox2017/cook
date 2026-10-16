// Developer: gengyun
// Purpose: Orchestrates the import quota reserve/settle lifecycle and resumes awaiting-upgrade operations by owner.

import Foundation

/// Result of reserving one selected candidate.
public enum RecipeImportUsageReserveOutcome: Sendable {
    case reserved(RecipeReservation)
    case awaitingUpgrade(RecipeImportUsageOperation)
}

/// A recovered operation whose settle already completed. The server-authored recipe ID and payload
/// hash are present so the caller can persist the recipe locally and then acknowledge without
/// re-settling the already-committed quota unit.
public struct RecipeImportUsageFinalizedOperation: Sendable {
    public let operation: RecipeImportUsageOperation
    public let recipeID: String
    public let payloadHash: String

    public init(operation: RecipeImportUsageOperation, recipeID: String, payloadHash: String) {
        self.operation = operation
        self.recipeID = recipeID
        self.payloadHash = payloadHash
    }
}

public struct RecipeImportUsageRecoveryReport: Sendable {
    /// Operations that recovered to `reserved` after the upgrade.
    public let recovered: [RecipeImportUsageOperation]
    /// Operations still blocked by a 402 outcome; the caller keeps them pending.
    public let stillAwaitingUpgrade: [RecipeImportUsageOperation]
    /// Operations whose settle is already committed server-side; the caller persists each recipe
    /// locally and acknowledges without a second finalize.
    public let finalized: [RecipeImportUsageFinalizedOperation]
    /// Operations whose recovery hit a non-quota failure, keyed by operation ID.
    public let failed: [UUID: RecipeUsageFailure]

    public init(
        recovered: [RecipeImportUsageOperation],
        stillAwaitingUpgrade: [RecipeImportUsageOperation],
        finalized: [RecipeImportUsageFinalizedOperation],
        failed: [UUID: RecipeUsageFailure]
    ) {
        self.recovered = recovered
        self.stillAwaitingUpgrade = stillAwaitingUpgrade
        self.finalized = finalized
        self.failed = failed
    }
}

/// The import-specific capability closure: it reserves, settles, and acknowledges exactly one candidate
/// per operation and never authors quota numbers or a second access service. DEV-432's unified
/// AccessStore/UpgradeRouter injects this bridge rather than building a parallel import quota path.
public struct RecipeImportUsageBridge: Sendable {
    public let client: any RecipeUsageClient
    public let store: RecipeImportUsageStore

    public init(client: any RecipeUsageClient, store: RecipeImportUsageStore) {
        self.client = client
        self.store = store
    }

    /// Reserves one candidate. The stable operation ID and its `reserving` intent are persisted before
    /// the network call, so a lost-response retry replays the same ID (idempotent REPLAY) instead of
    /// double-charging. A 402 quota/upgrade outcome transitions the intent to `awaitingUpgrade`.
    public func reserve(
        ownerID: UUID,
        jobID: UUID,
        candidateID: String,
        receiptID: UUID
    ) async throws -> RecipeImportUsageReserveOutcome {
        let operationID = RecipeImportUsageOperation.stableOperationID(
            ownerID: ownerID, jobID: jobID, candidateID: candidateID)
        let source = try RecipeUsageSource(
            importJobID: jobID.uuidString.lowercased(), candidateIDs: [candidateID])
        let inputHash = try RecipeUsageInputHash.compute(capability: .smartImport, source: source)
        let request = try RecipeReservationRequest(
            operationID: operationID.uuidString.lowercased(),
            capability: .smartImport,
            inputHash: inputHash,
            estimatedUnits: 1,
            source: source
        )

        // Durable intent must exist before the network call; a later replay of the same operation ID
        // is the only idempotency key the frozen contract exposes.
        let pending = RecipeImportUsageOperation(
            operationID: operationID,
            ownerID: ownerID,
            jobID: jobID,
            candidateID: candidateID,
            receiptID: receiptID,
            state: .reserving
        )
        try store.save(pending)

        do {
            let reservation = try await client.reserve(ownerID: ownerID, request: request)
            try reconcile(reservation, operationID: operationID)
            let reserved = pending.marking(state: .reserved, reservedUntil: reservation.reservedUntil)
            try store.save(reserved)
            return .reserved(reservation)
        } catch let failure as RecipeUsageFailure where failure.isAwaitingUpgrade {
            let awaiting = pending.marking(state: .awaitingUpgrade)
            try store.save(awaiting)
            return .awaitingUpgrade(awaiting)
        }
    }

    /// Resumes every pending operation for an owner: `reserving`/`awaitingUpgrade` replay their stable
    /// reservation (idempotent REPLAY), while `reserved`/`finalized` replay or restore the server settle
    /// result so the caller can persist the recipe locally and acknowledge without re-settling. It never
    /// rebuilds the import job or re-fetches cached results.
    public func recover(ownerID: UUID) async throws -> RecipeImportUsageRecoveryReport {
        var recovered: [RecipeImportUsageOperation] = []
        var stillAwaitingUpgrade: [RecipeImportUsageOperation] = []
        var finalized: [RecipeImportUsageFinalizedOperation] = []
        var failed: [UUID: RecipeUsageFailure] = [:]

        for operation in try store.operations(for: ownerID) {
            // Media-bundle candidates were reserved atomically by the DEV-78 media save and must be
            // replayed/finalized by RecipeMediaBundlePort, never per-item here (that would drop the
            // media_import unit and break the bundle's atomicity).
            guard operation.mediaBundleJobID == nil else { continue }
            switch operation.state {
            case .reserving, .awaitingUpgrade:
                let source = try operation.usageSource()
                let request = try RecipeReservationRequest(
                    operationID: operation.operationID.uuidString.lowercased(),
                    capability: .smartImport,
                    inputHash: try operation.inputHash(),
                    estimatedUnits: 1,
                    source: source
                )
                do {
                    let reservation = try await client.reserve(ownerID: ownerID, request: request)
                    try reconcile(reservation, operationID: operation.operationID)
                    let updated = operation.marking(state: .reserved, reservedUntil: reservation.reservedUntil)
                    try store.save(updated)
                    recovered.append(updated)
                } catch let failure as RecipeUsageFailure where failure.isAwaitingUpgrade {
                    let awaiting = operation.marking(state: .awaitingUpgrade)
                    try store.save(awaiting)
                    stillAwaitingUpgrade.append(awaiting)
                } catch let failure as RecipeUsageFailure {
                    failed[operation.operationID] = failure
                } catch {
                    failed[operation.operationID] = .transport(error.localizedDescription)
                }
            case .reserved, .finalized:
                do {
                    finalized.append(try await finalizeResult(ownerID: ownerID, operation: operation))
                } catch let failure as RecipeUsageFailure {
                    failed[operation.operationID] = failure
                } catch {
                    failed[operation.operationID] = .transport(error.localizedDescription)
                }
            }
        }

        return RecipeImportUsageRecoveryReport(
            recovered: recovered,
            stillAwaitingUpgrade: stillAwaitingUpgrade,
            finalized: finalized,
            failed: failed
        )
    }

    /// Replays the server settle for a `.reserved`/`.finalized` operation. A `.finalized` operation
    /// that already persisted its recipe ID and payload hash is replayed from the store without a
    /// network call, so the already-committed quota unit is never settled a second time.
    private func finalizeResult(
        ownerID: UUID,
        operation: RecipeImportUsageOperation
    ) async throws -> RecipeImportUsageFinalizedOperation {
        if operation.state == .finalized,
           let recipeID = operation.recipeID,
           let payloadHash = operation.payloadHash {
            return RecipeImportUsageFinalizedOperation(
                operation: operation, recipeID: recipeID, payloadHash: payloadHash)
        }
        let response = try await finalize(ownerID: ownerID, operation: operation)
        return RecipeImportUsageFinalizedOperation(
            operation: operation.markingFinalized(
                recipeID: response.recipeID, payloadHash: response.payloadHash),
            recipeID: response.recipeID,
            payloadHash: response.payloadHash
        )
    }

    /// Reconciles the server reservation against the stable operation it was requested for. A
    /// mismatched operation ID would indicate a server bug or a duplicated request and must never be
    /// persisted as this operation's reservation.
    private func reconcile(_ reservation: RecipeReservation, operationID: UUID) throws {
        guard reservation.operationID == operationID.uuidString.lowercased() else {
            throw RecipeUsageFailure.api(
                .internalError,
                recoverable: true,
                message: "The reservation response did not match the requested operation.",
                requestID: nil
            )
        }
    }

    /// Settles a reserved operation and returns the server-authored stable recipe ID and payload hash.
    /// The settle result is persisted before returning, so a crash before the caller's local recipe
    /// save/acknowledge can be replayed by `recover` without settling the quota unit a second time.
    public func finalize(
        ownerID: UUID,
        operation: RecipeImportUsageOperation
    ) async throws -> RecipeUsageFinalizeResponse {
        let request = try RecipeUsageFinalizeRequest(
            capability: .smartImport,
            inputHash: try operation.inputHash(),
            source: try operation.usageSource()
        )
        let response = try await client.finalize(
            ownerID: ownerID,
            operationID: operation.operationID.uuidString.lowercased(),
            request: request
        )
        try store.save(
            operation.markingFinalized(recipeID: response.recipeID, payloadHash: response.payloadHash)
        )
        return response
    }

    /// Confirms device persistence and removes the settled operation. Idempotent by operation ID.
    public func acknowledge(ownerID: UUID, operation: RecipeImportUsageOperation) async throws {
        _ = try await client.acknowledge(
            ownerID: ownerID,
            operationID: operation.operationID.uuidString.lowercased()
        )
        try store.remove(operationID: operation.operationID, ownerID: ownerID)
    }

    /// Releases a reservation the user abandoned before finalize so it never lingers past its TTL.
    public func cancel(ownerID: UUID, operation: RecipeImportUsageOperation) async throws {
        _ = try await client.release(
            ownerID: ownerID,
            operationID: operation.operationID.uuidString.lowercased()
        )
        try store.remove(operationID: operation.operationID, ownerID: ownerID)
    }
}
