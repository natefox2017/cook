// Developer: gengyun
// Purpose: Persists owner-scoped import usage operations so an upgrade can resume the original reservation without losing input.

import CryptoKit
import Foundation

/// One candidate reservation in the import usage lifecycle. A multi-candidate selection produces one
/// operation per selected candidate; each settles exactly one unit through the frozen usage routes.
public struct RecipeImportUsageOperation: Codable, Hashable, Sendable, Identifiable {
    public enum State: String, Codable, Hashable, Sendable {
        /// Durable intent persisted before the reserve call; the server answer is not yet known.
        /// Recovery replays the same stable operation ID instead of minting a second reservation.
        case reserving
        /// Reserve hit a 402 quota/upgrade outcome; the input is preserved until the owner upgrades.
        case awaitingUpgrade
        /// Reserve succeeded; finalize/ack is still owed. Never auto-release a dispatched reserve.
        case reserved
        /// Finalize returned the server recipe ID; the local ack is still owed.
        case finalized
    }

    public let operationID: UUID
    public let ownerID: UUID
    public let jobID: UUID
    public let candidateID: String
    public let receiptID: UUID
    public let state: State
    public let reservedUntil: String?
    public let createdAt: Date
    public let updatedAt: Date
    /// Server-authored stable recipe ID, persisted once finalize commits so a crash before the local
    /// recipe save/ack can replay the result instead of settling the quota unit a second time.
    public let recipeID: String?
    /// Server-authored payload hash for the settled recipe; persisted together with `recipeID`.
    public let payloadHash: String?

    public var id: UUID { operationID }

    public init(
        operationID: UUID,
        ownerID: UUID,
        jobID: UUID,
        candidateID: String,
        receiptID: UUID,
        state: State,
        reservedUntil: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        recipeID: String? = nil,
        payloadHash: String? = nil
    ) {
        self.operationID = operationID
        self.ownerID = ownerID
        self.jobID = jobID
        self.candidateID = candidateID
        self.receiptID = receiptID
        self.state = state
        self.reservedUntil = reservedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recipeID = recipeID
        self.payloadHash = payloadHash
    }

    /// Derives a stable operation ID from the owner + job + candidate so a lost-response retry replays
    /// the exact same reservation instead of minting a second one (double charge). The frozen contract's
    /// idempotency key is the operation ID, so it must be canonical and reproducible across retries.
    public static func stableOperationID(ownerID: UUID, jobID: UUID, candidateID: String) -> UUID {
        let key = Data(
            "\(ownerID.uuidString.lowercased()):\(jobID.uuidString.lowercased()):\(candidateID)".utf8)
        let digest = Array(SHA256.hash(data: key))
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            ))
    }

    /// The frozen usage source this operation settles against; recomputed deterministically on recovery.
    public func usageSource() throws -> RecipeUsageSource {
        try RecipeUsageSource(importJobID: jobID.uuidString.lowercased(), candidateIDs: [candidateID])
    }

    public func inputHash() throws -> String {
        try RecipeUsageInputHash.compute(capability: .smartImport, source: usageSource())
    }

    public func marking(state: State, reservedUntil: String? = nil) -> RecipeImportUsageOperation {
        RecipeImportUsageOperation(
            operationID: operationID,
            ownerID: ownerID,
            jobID: jobID,
            candidateID: candidateID,
            receiptID: receiptID,
            state: state,
            reservedUntil: reservedUntil ?? self.reservedUntil,
            createdAt: createdAt,
            updatedAt: .now,
            recipeID: recipeID,
            payloadHash: payloadHash
        )
    }

    /// Records the server-authored settle result so a crash before the local recipe save/ack can
    /// replay the exact same recipe ID and payload hash without settling the quota unit a second time.
    public func markingFinalized(recipeID: String, payloadHash: String) -> RecipeImportUsageOperation {
        RecipeImportUsageOperation(
            operationID: operationID,
            ownerID: ownerID,
            jobID: jobID,
            candidateID: candidateID,
            receiptID: receiptID,
            state: .finalized,
            reservedUntil: reservedUntil,
            createdAt: createdAt,
            updatedAt: .now,
            recipeID: recipeID,
            payloadHash: payloadHash
        )
    }
}

/// File-backed owner-scoped store. The main app is the only writer (the Share Extension never reserves
/// or purchases); each owner gets one atomic file. A shared lock serializes read-modify-write updates
/// so a concurrent multi-candidate selection cannot overwrite a locally tracked operation.
public struct RecipeImportUsageStore: Sendable {
    /// Shared across every value copy of the store (the bridge is a value type), so concurrent
    /// read-modify-write updates serialize instead of dropping an operation to a last-writer-wins race.
    private final class Lock: @unchecked Sendable {
        let nsLock = NSLock()
    }

    private let lock = Lock()
    private let root: URL

    /// The application-support directory is shared with the recipe library and survives relaunch.
    public static func `default`() throws -> RecipeImportUsageStore {
        try RecipeImportUsageStore(
            directory: URL.applicationSupportDirectory
                .appendingPathComponent("Recipe", isDirectory: true)
        )
    }

    public init(directory: URL) throws {
        self.root = directory.appendingPathComponent("import-usage", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func operations(for ownerID: UUID) throws -> [RecipeImportUsageOperation] {
        let file = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        guard !data.isEmpty else { return [] }
        return try decoder().decode([RecipeImportUsageOperation].self, from: data)
    }

    public func save(_ operation: RecipeImportUsageOperation) throws {
        try lock.nsLock.withLock {
            var existing = try operations(for: operation.ownerID)
            existing.removeAll { $0.operationID == operation.operationID }
            existing.append(operation)
            existing.sort { $0.createdAt < $1.createdAt }
            try write(existing, to: fileURL(for: operation.ownerID))
        }
    }

    public func remove(operationID: UUID, ownerID: UUID) throws {
        try lock.nsLock.withLock {
            var existing = try operations(for: ownerID)
            existing.removeAll { $0.operationID == operationID }
            try write(existing, to: fileURL(for: ownerID))
        }
    }

    private func fileURL(for ownerID: UUID) -> URL {
        root.appendingPathComponent(ownerID.uuidString.lowercased() + ".json")
    }

    private func write(_ operations: [RecipeImportUsageOperation], to url: URL) throws {
        let data = try encoder().encode(operations)
        try data.write(to: url, options: .atomic)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
