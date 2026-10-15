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
        updatedAt: Date = .now
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
            updatedAt: .now
        )
    }
}

/// File-backed owner-scoped store. The main app is the only writer (the Share Extension never reserves
/// or purchases), so a single atomic file per owner is sufficient and race-free.
public struct RecipeImportUsageStore: Sendable {
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
        var existing = try operations(for: operation.ownerID)
        existing.removeAll { $0.operationID == operation.operationID }
        existing.append(operation)
        existing.sort { $0.createdAt < $1.createdAt }
        try write(existing, to: fileURL(for: operation.ownerID))
    }

    public func remove(operationID: UUID, ownerID: UUID) throws {
        var existing = try operations(for: ownerID)
        existing.removeAll { $0.operationID == operationID }
        try write(existing, to: fileURL(for: ownerID))
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
