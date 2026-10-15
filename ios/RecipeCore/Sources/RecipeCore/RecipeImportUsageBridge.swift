// Developer: gengyun
// Purpose: Orchestrates the import quota reserve/settle lifecycle and resumes awaiting-upgrade operations by owner.

import Foundation

/// Result of reserving one selected candidate.
public enum RecipeImportUsageReserveOutcome: Sendable {
    case reserved(RecipeReservation)
    case awaitingUpgrade(RecipeImportUsageOperation)
}

public struct RecipeImportUsageRecoveryReport: Sendable {
    /// Operations that recovered to `reserved` after the upgrade.
    public let recovered: [RecipeImportUsageOperation]
    /// Operations still blocked by a 402 outcome; the caller keeps them pending.
    public let stillAwaitingUpgrade: [RecipeImportUsageOperation]
    /// Operations whose recovery hit a non-quota failure, keyed by operation ID.
    public let failed: [UUID: RecipeUsageFailure]

    public init(
        recovered: [RecipeImportUsageOperation],
        stillAwaitingUpgrade: [RecipeImportUsageOperation],
        failed: [UUID: RecipeUsageFailure]
    ) {
        self.recovered = recovered
        self.stillAwaitingUpgrade = stillAwaitingUpgrade
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

    /// Reserves one candidate. A 402 quota/upgrade outcome persists an `awaitingUpgrade` operation so
    /// the input is never lost; other failures propagate for a normal retry without state change.
    public func reserve(
        ownerID: UUID,
        jobID: UUID,
        candidateID: String,
        receiptID: UUID
    ) async throws -> RecipeImportUsageReserveOutcome {
        let source = try RecipeUsageSource(
            importJobID: jobID.uuidString.lowercased(), candidateIDs: [candidateID])
        let inputHash = try RecipeUsageInputHash.compute(capability: .smartImport, source: source)
        let operationID = UUID()
        let request = try RecipeReservationRequest(
            operationID: operationID.uuidString.lowercased(),
            capability: .smartImport,
            inputHash: inputHash,
            estimatedUnits: 1,
            source: source
        )
        do {
            let reservation = try await client.reserve(ownerID: ownerID, request: request)
            let operation = RecipeImportUsageOperation(
                operationID: operationID,
                ownerID: ownerID,
                jobID: jobID,
                candidateID: candidateID,
                receiptID: receiptID,
                state: .reserved,
                reservedUntil: reservation.reservedUntil
            )
            try store.save(operation)
            return .reserved(reservation)
        } catch let failure as RecipeUsageFailure where failure.isAwaitingUpgrade {
            let operation = RecipeImportUsageOperation(
                operationID: operationID,
                ownerID: ownerID,
                jobID: jobID,
                candidateID: candidateID,
                receiptID: receiptID,
                state: .awaitingUpgrade
            )
            try store.save(operation)
            return .awaitingUpgrade(operation)
        }
    }

    /// Re-reserves every `awaitingUpgrade` operation for an owner using its original operation ID
    /// (idempotent REPLAY). It never rebuilds the import job or re-fetches cached results.
    public func recover(ownerID: UUID) async throws -> RecipeImportUsageRecoveryReport {
        var recovered: [RecipeImportUsageOperation] = []
        var stillAwaitingUpgrade: [RecipeImportUsageOperation] = []
        var failed: [UUID: RecipeUsageFailure] = [:]

        for operation in try store.operations(for: ownerID)
        where operation.state == .awaitingUpgrade {
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
                let updated = operation.marking(state: .reserved, reservedUntil: reservation.reservedUntil)
                try store.save(updated)
                recovered.append(updated)
            } catch let failure as RecipeUsageFailure where failure.isAwaitingUpgrade {
                stillAwaitingUpgrade.append(operation)
            } catch let failure as RecipeUsageFailure {
                failed[operation.operationID] = failure
            } catch {
                failed[operation.operationID] = .transport(error.localizedDescription)
            }
        }

        return RecipeImportUsageRecoveryReport(
            recovered: recovered,
            stillAwaitingUpgrade: stillAwaitingUpgrade,
            failed: failed
        )
    }

    /// Settles a reserved operation and returns the server-authored stable recipe ID and payload hash.
    /// The local recipe save is the caller's step; it must happen before `acknowledge`.
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
        try store.save(operation.marking(state: .finalized))
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
