// Developer: gengyun
// Purpose: Typed candidate-save boundary and canonical usage hash for the document batch scan.

import CryptoKit
import Foundation

/// One confirmed batch candidate, keyed by its stable worker candidate ID for
/// the smart_import settle (origin import_job, exactly one candidate per op).
public struct RecipeDocumentBatchSaveCandidate: Sendable, Hashable {
    public let candidateID: String
    public let title: String?
    public let ingredients: [String]
    public let steps: [String]

    public init(
        candidateID: String,
        title: String?,
        ingredients: [String],
        steps: [String]
    ) {
        self.candidateID = candidateID
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
    }
}

/// The candidate-save boundary the AddRecipeView wiring fills. Each confirmed
/// candidate is settled through the smart_import usage contract (reserve →
/// finalize → local Store write → ACK) against the batch's persisted import
/// job; one candidate is settled per operation.
@MainActor
public protocol RecipeDocumentBatchSaveBoundary: Sendable {
    func save(
        jobID: UUID,
        candidates: [RecipeDocumentBatchSaveCandidate],
        ownerID: UUID
    ) async throws
}

/// Canonical DEV-427 usage hashing. `importInputHash` mirrors the server's
/// `computeInputHash({ capability: "smart_import", source })`, where the source
/// is the normalized `import_job` shape with null session/turn members and
/// exactly one candidate, so a client and the ledger never disagree on the
/// immutable operation key.
public enum RecipeUsageHash {
    public static func importInputHash(jobID: String, candidateID: String) -> String {
        let canonical =
            #"{"capability":"smart_import","source":{"candidate_ids":["\#(candidateID)"],"job_id":"\#(jobID)","origin":"import_job","session_id":null,"turn_request_id":null}}"#
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical ai_edit usage hashing mirroring the server's
    /// `computeInputHash({ capability: "ai_edit", source })` for a draft-approval source
    /// (null job/candidate members, session and turn request set), so a client and the
    /// ledger never disagree on the immutable operation key. UUIDs must be lowercase.
    public static func aiEditInputHash(sessionID: String, turnRequestID: String) -> String {
        let canonical =
            #"{"capability":"ai_edit","source":{"candidate_ids":null,"job_id":null,"origin":"draft_approval","session_id":"\#(sessionID)","turn_request_id":"\#(turnRequestID)"}}"#
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
