// Developer: gengyun
// Purpose: Persist per-owner pending draft approval commits under the recipe.* key namespace.

import Foundation

public enum RecipeDraftPersistenceError: Error, Equatable, Sendable {
    case invalidCommit
}

private func draftPersistenceUUID(_ value: String) -> Bool {
    value.range(
        of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
        options: .regularExpression) == value.startIndex..<value.endIndex
}

private func draftPersistenceHash(_ value: String) -> Bool {
    value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) == value
        .startIndex..<value.endIndex
}

/// A locally persisted approval intent that survives a crash between the
/// server finalize and the local recipe write. It never stores recipe payloads
/// or other-owner data, and it is keyed per owner so resume only ever loads
/// the signed-in owner's own operation.
public struct RecipeDraftPendingCommit: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case awaitingFinalize
        case finalized
    }

    public let ownerID: String
    public let sessionID: String
    public let turnRequestID: String
    public let requestID: String
    public let operationID: String
    public let selectedPaths: [String]
    public let status: Status
    public let recipeID: String?
    public let payloadHash: String?

    public init(
        ownerID: String,
        sessionID: String,
        turnRequestID: String,
        requestID: String,
        operationID: String,
        selectedPaths: [String],
        status: Status = .awaitingFinalize,
        recipeID: String? = nil,
        payloadHash: String? = nil
    ) throws {
        guard
            draftPersistenceUUID(ownerID) && draftPersistenceUUID(sessionID)
                && draftPersistenceUUID(turnRequestID) && draftPersistenceUUID(requestID)
                && draftPersistenceUUID(operationID)
        else {
            throw RecipeDraftPersistenceError.invalidCommit
        }
        guard Set(selectedPaths).count == selectedPaths.count, !selectedPaths.isEmpty else {
            throw RecipeDraftPersistenceError.invalidCommit
        }
        switch status {
        case .awaitingFinalize:
            guard recipeID == nil && payloadHash == nil else {
                throw RecipeDraftPersistenceError.invalidCommit
            }
        case .finalized:
            guard
                let recipeID, let payloadHash,
                draftPersistenceUUID(recipeID), draftPersistenceHash(payloadHash)
            else {
                throw RecipeDraftPersistenceError.invalidCommit
            }
        }
        self.ownerID = ownerID
        self.sessionID = sessionID
        self.turnRequestID = turnRequestID
        self.requestID = requestID
        self.operationID = operationID
        self.selectedPaths = selectedPaths
        self.status = status
        self.recipeID = recipeID
        self.payloadHash = payloadHash
    }
}

/// A real UserDefaults-backed store for pending commits. Each owner has exactly
/// one pending commit, stored under `recipe.draft.pending.commit.<owner-id>`.
/// The owning UserDefaults is injected so tests can use an isolated suite while
/// the app uses the standard defaults container.
public struct RecipeDraftPendingCommitStore {
    private static let keyPrefix = "recipe.draft.pending.commit."
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ commit: RecipeDraftPendingCommit) throws {
        let data = try JSONEncoder().encode(commit)
        defaults.set(data, forKey: Self.key(for: commit.ownerID))
    }

    public func load(ownerID: String) -> RecipeDraftPendingCommit? {
        guard
            let data = defaults.data(forKey: Self.key(for: ownerID)),
            let commit = try? JSONDecoder().decode(RecipeDraftPendingCommit.self, from: data),
            commit.ownerID == ownerID
        else {
            return nil
        }
        return commit
    }

    public func clear(ownerID: String) {
        defaults.removeObject(forKey: Self.key(for: ownerID))
    }

    /// The set of owners with a persisted pending commit, for resume scans that
    /// must only surface the signed-in owner's own operation.
    public func ownerIDs() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.keyPrefix) }
            .compactMap { key in
                let raw = String(key.dropFirst(Self.keyPrefix.count))
                return draftPersistenceUUID(raw) ? raw : nil
            }
    }

    private static func key(for ownerID: String) -> String {
        keyPrefix + ownerID
    }
}
