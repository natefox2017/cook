// Developer: gengyun
// Purpose: Persists share receipts in an App Group without concurrent array overwrites.

import CryptoKit
import Darwin
import Foundation

public enum RecipeShareInputType: String, Codable, Sendable {
    case url
    case text
}

public enum RecipeShareReceiptState: String, Codable, Sendable {
    case received
}

/// Immutable durable source reference. The server's queued/completed states
/// are different and must never be inferred from this local receipt.
public struct RecipeShareReceipt: Codable, Sendable, Identifiable, Equatable {
    public struct Payload: Codable, Sendable, Equatable {
        public let reference: String
    }

    public let receiptID: UUID
    public let clientRequestID: UUID
    public let inputType: RecipeShareInputType
    public let receivedAt: Date
    public let localState: RecipeShareReceiptState
    public let payload: Payload

    public var id: UUID { receiptID }

    private enum CodingKeys: String, CodingKey {
        case receiptID = "receipt_id"
        case clientRequestID = "client_request_id"
        case inputType = "input_type"
        case receivedAt = "received_at"
        case localState = "local_state"
        case payload
    }
}

public enum RecipeShareInboxError: LocalizedError {
    case appGroupUnavailable
    case invalidInput
    case sourceMissing

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "RecipePouch's shared storage is not available. Check App Group signing."
        case .invalidInput:
            "Share a public HTTPS link or readable text to RecipePouch."
        case .sourceMissing:
            "The original shared text is missing. Share the source again."
        }
    }
}

/// Per-source immutable files remove the cross-process read-modify-write race
/// of an array in UserDefaults. Source bytes are written before the receipt;
/// an acknowledgement is a separate immutable file, written only after the
/// authenticated backend confirms a durable job. No ack is created here.
public struct RecipeShareInbox: Sendable {
    public static let appGroupID = "group.com.modelhub.cook"

    private let root: URL

    public static func shared() throws -> RecipeShareInbox {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw RecipeShareInboxError.appGroupUnavailable
        }
        return try RecipeShareInbox(containerURL: container)
    }

    /// The explicit container initializer allows local filesystem tests
    /// without signing/provisioning an App Group on the test runner.
    public init(containerURL: URL) throws {
        self.root = containerURL.appendingPathComponent(
            "RecipeShareInbox-v1",
            isDirectory: true
        )
        for name in ["sources", "receipts", "acknowledgements"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    @discardableResult
    public func receive(
        _ rawSource: String,
        as type: RecipeShareInputType
    ) throws -> RecipeShareReceipt {
        let original = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .url:
            guard original.utf8.count <= 8192,
                  let url = URLComponents(string: original),
                  url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else {
                throw RecipeShareInboxError.invalidInput
            }
        case .text:
            guard !original.isEmpty, original.count <= 100_000 else {
                throw RecipeShareInboxError.invalidInput
            }
        }

        // Stable per-device key also deduplicates rapid concurrent shares and
        // preserves the same client_request_id when a failed upload retries.
        let fingerprint = Array(SHA256.hash(data: Data(
            (type.rawValue + "\n" + original).utf8
        )))
        let hex = fingerprint.map { String(format: "%02x", $0) }.joined()
        var uuidBytes = Array(fingerprint.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        let idHex = uuidBytes.map { String(format: "%02x", $0) }.joined()
        let idString = String(idHex.prefix(8)) + "-"
            + String(idHex.dropFirst(8).prefix(4)) + "-"
            + String(idHex.dropFirst(12).prefix(4)) + "-"
            + String(idHex.dropFirst(16).prefix(4)) + "-"
            + String(idHex.dropFirst(20))
        guard let identifier = UUID(uuidString: idString) else {
            throw RecipeShareInboxError.invalidInput
        }

        let sourceRef = "sources/" + hex + ".txt"
        try writeOnce(
            Data(original.utf8),
            to: root.appendingPathComponent(sourceRef)
        )

        let receipt = RecipeShareReceipt(
            receiptID: identifier,
            clientRequestID: identifier,
            inputType: type,
            receivedAt: .now,
            localState: .received,
            payload: .init(reference: sourceRef)
        )
        let receiptURL = receiptFile(for: identifier)
        try writeOnce(try encoder().encode(receipt), to: receiptURL)
        return try decoder().decode(
            RecipeShareReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
    }

    /// Unacknowledged sources remain available after an app or extension exit.
    public func pendingReceipts(for ownerID: UUID? = nil) throws -> [RecipeShareReceipt] {
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("receipts"),
            includingPropertiesForKeys: nil
        )
        let results = try files
            .filter { $0.pathExtension == "json" }
            .map {
                try decoder().decode(
                    RecipeShareReceipt.self,
                    from: Data(contentsOf: $0)
                )
            }
            .filter { receipt in
                // A source acknowledged for account A must remain pending
                // for account B. Signed-out devices keep their local source.
                guard let ownerID else { return true }
                return !FileManager.default.fileExists(
                    atPath: acknowledgementFile(for: receipt.id, ownerID: ownerID).path
                )
            }
        return results.sorted { $0.receivedAt < $1.receivedAt }
    }

    /// User-confirmed local erasure must also clear pending private source
    /// text and acknowledged receipt metadata in the App Group container.
    /// Errors propagate so the app never reports a full deletion while
    /// shared personal source files remain.
    public func eraseAllLocalReceipts() throws {
        for name in ["receipts", "acknowledgements", "sources"] {
            let directory = root.appendingPathComponent(
                name, isDirectory: true
            )
            for file in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    public func source(for receipt: RecipeShareReceipt) throws -> String {
        let ref = receipt.payload.reference
        guard ref.hasPrefix("sources/") else {
            throw RecipeShareInboxError.sourceMissing
        }
        let name = String(ref.dropFirst("sources/".count))
        guard name.range(
            of: "^[0-9a-f]{64}\\.txt$",
            options: .regularExpression
        ) != nil else {
            throw RecipeShareInboxError.sourceMissing
        }
        let url = root.appendingPathComponent(ref)
        guard let source = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw RecipeShareInboxError.sourceMissing
        }
        return source
    }

    /// Call only after the owner-authenticated server confirms a durable job.
    /// Do not ACK merely because the Share UI or host App has opened.
    public func acknowledge(
        _ receipt: RecipeShareReceipt,
        jobID: UUID,
        ownerID: UUID
    ) throws {
        let payload = ServerAcknowledgement(
            jobID: jobID,
            ownerID: ownerID,
            acknowledgedAt: .now
        )
        try writeOnce(
            try encoder().encode(payload),
            to: acknowledgementFile(for: receipt.id, ownerID: ownerID)
        )
    }

    /// After a crash, the host can query the server job for the same owner
    /// instead of resubmitting or treating a queued job as a finished recipe.
    public func acknowledgedJobID(
        for receipt: RecipeShareReceipt,
        ownerID: UUID
    ) throws -> UUID? {
        let file = acknowledgementFile(for: receipt.id, ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        let record = try decoder().decode(
            ServerAcknowledgement.self,
            from: Data(contentsOf: file)
        )
        guard record.ownerID == ownerID else {
            return nil
        }
        return record.jobID
    }

    private struct ServerAcknowledgement: Codable {
        let jobID: UUID
        let ownerID: UUID
        let acknowledgedAt: Date
    }

    private func receiptFile(for id: UUID) -> URL {
        root.appendingPathComponent("receipts")
            .appendingPathComponent(id.uuidString + ".json")
    }

    private func acknowledgementFile(for id: UUID, ownerID: UUID) -> URL {
        root.appendingPathComponent("acknowledgements")
            .appendingPathComponent(id.uuidString + "-" + ownerID.uuidString + ".json")
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

    /// Write, flush and hard-link the immutable file into place. Hard-linking
    /// is atomic and refuses replacement, so two processes never clobber an
    /// existing receipt or source and a reader never observes a partial file.
    private func writeOnce(_ data: Data, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("." + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try data.write(to: temporary, options: .atomic)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()

        do {
            try FileManager.default.linkItem(at: temporary, to: destination)
        } catch {
            // Another process may have won exactly the same immutable key.
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw error
            }
        }

        // Persist the new directory entry before claiming local receipt ACK.
        let folder = destination.deletingLastPathComponent()
        let descriptor = Darwin.open(folder.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
