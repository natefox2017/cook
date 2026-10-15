// Developer: gengyun
// Purpose: Typed candidate-save boundary for the document batch scan.

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

/// The candidate-save seam the DEV-427/432 wiring fills. The batch sheet
/// resolves a confirmed selection into this boundary; the wiring builds the
/// smart_import usage settle (`RecipeUsageFinalizeRequest`) from the stable
/// candidate IDs and performs the local recipe write. Until wired it fails
/// closed so a confirmed batch never saves unmetered.
@MainActor
public protocol RecipeDocumentBatchSaveBoundary: Sendable {
    func save(
        _ candidates: [RecipeDocumentBatchSaveCandidate],
        batchID: UUID,
        ownerID: UUID
    ) async throws
}

public enum RecipeDocumentBatchSaveError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            RecipeLanguage.localized(
                "Saving scanned recipes isn't available yet. The candidates stay available for review.")
        }
    }
}

/// Fail-closed default until the DEV-427/432 wiring supplies the real
/// smart_import settle. A confirmed selection can never save unmetered through
/// this boundary.
@MainActor
public struct RecipeDocumentBatchUnavailableSaveBoundary: RecipeDocumentBatchSaveBoundary {
    public init() {}

    public func save(
        _ candidates: [RecipeDocumentBatchSaveCandidate],
        batchID: UUID,
        ownerID: UUID
    ) async throws {
        throw RecipeDocumentBatchSaveError.unavailable
    }
}
