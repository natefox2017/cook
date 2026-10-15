// Developer: gengyun
// Purpose: Uploads and scans bounded document batches through the recipe-document-batch endpoint.

import CryptoKit
import Foundation
import RecipeCore
import Supabase

struct RecipeDocumentBatchService {
    private struct UploadRequest: Encodable {
        let clientRequestID: UUID
        let inputType: String
        let mimeType: String
        let sizeBytes: Int

        enum CodingKeys: String, CodingKey {
            case clientRequestID = "client_request_id"
            case inputType = "input_type"
            case mimeType = "mime_type"
            case sizeBytes = "size_bytes"
        }
    }

    private struct UploadIntent: Decodable {
        struct Artifact: Decodable {
            let artifactID: UUID
            let state: String

            enum CodingKeys: String, CodingKey {
                case artifactID = "artifact_id"
                case state
            }
        }

        let artifact: Artifact
        let uploadPath: String?
        let uploadToken: String?

        enum CodingKeys: String, CodingKey {
            case artifact
            case uploadPath = "upload_path"
            case uploadToken = "upload_token"
        }
    }

    private struct ScanRequest: Encodable {
        struct Item: Encodable {
            let id: String
            let inputType: String
            let mimeType: String
            let sizeBytes: Int
            let pageCount: Int

            enum CodingKeys: String, CodingKey {
                case id
                case inputType = "input_type"
                case mimeType = "mime_type"
                case sizeBytes = "size_bytes"
                case pageCount = "page_count"
            }
        }

        let items: [Item]
    }

    private struct ScanResponse: Decodable {
        struct Candidate: Decodable {
            let candidateID: String
            let title: String?
            let ingredients: [String]
            let steps: [String]

            enum CodingKeys: String, CodingKey {
                case candidateID = "candidate_id"
                case title
                case ingredients
                case steps
            }
        }

        let jobID: UUID
        let candidates: [Candidate]
        let hasMore: Bool
        let unprocessed: Int

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case candidates
            case hasMore = "has_more"
            case unprocessed
        }
    }

    private struct CompleteResponse: Decodable {
        struct Artifact: Decodable {
            let artifactID: UUID

            enum CodingKeys: String, CodingKey {
                case artifactID = "artifact_id"
            }
        }

        let artifact: Artifact
    }

    func upload(
        data: Data,
        inputType: RecipeDocumentBatchInputType,
        mimeType: String,
        ownerID: UUID
    ) async throws -> UUID {
        try await verifySession(ownerID: ownerID)
        let intent: UploadIntent = try await RecipeSupabase.client.functions.invoke(
            "recipe-document-batch/upload",
            options: FunctionInvokeOptions(
                method: .post,
                body: UploadRequest(
                    clientRequestID: stableRequestID(
                        data: data, inputType: inputType, mimeType: mimeType),
                    inputType: inputType.rawValue,
                    mimeType: mimeType,
                    sizeBytes: data.count
                )
            )
        )
        if intent.artifact.state == "available" {
            return intent.artifact.artifactID
        }
        guard let path = intent.uploadPath, let token = intent.uploadToken else {
            throw RecipeRemoteImportError.transport(
                RecipeLanguage.localized("The file upload could not be resumed."))
        }
        do {
            try await RecipeSupabase.client.storage
                .from("recipe-import-artifacts")
                .uploadToSignedURL(
                    path,
                    token: token,
                    data: data,
                    options: FileOptions(contentType: mimeType, upsert: false)
                )
        } catch {
            // A connection loss can happen after Storage accepted all bytes.
            return try await complete(intent.artifact.artifactID)
        }
        return try await complete(intent.artifact.artifactID)
    }

    func scan(
        items: [RecipeDocumentBatchItem],
        ownerID: UUID
    ) async throws -> (jobID: UUID, outcome: RecipeDocumentBatchOutcome) {
        try await verifySession(ownerID: ownerID)
        let response: ScanResponse = try await RecipeSupabase.client.functions.invoke(
            "recipe-document-batch",
            options: FunctionInvokeOptions(
                method: .post,
                body: ScanRequest(
                    items: items.map {
                        ScanRequest.Item(
                            id: $0.id,
                            inputType: $0.inputType.rawValue,
                            mimeType: $0.mimeType,
                            sizeBytes: $0.sizeBytes,
                            pageCount: $0.pageCount
                        )
                    }
                )
            )
        )
        return (
            jobID: response.jobID,
            outcome: RecipeDocumentBatchOutcome(
                candidates: response.candidates.map {
                    RecipeDocumentBatchCandidate(
                        candidateID: $0.candidateID,
                        title: $0.title,
                        ingredients: $0.ingredients,
                        steps: $0.steps
                    )
                },
                hasMore: response.hasMore,
                unprocessed: response.unprocessed
            )
        )
    }

    private func complete(_ artifactID: UUID) async throws -> UUID {
        let response: CompleteResponse = try await RecipeSupabase.client.functions.invoke(
            "recipe-document-batch/upload/\(artifactID.uuidString.lowercased())/complete",
            options: FunctionInvokeOptions(method: .post)
        )
        return response.artifact.artifactID
    }

    private func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw RecipeShareImportWorkflowError.accountChanged
        }
    }

    /// Derives a stable upload request ID from the source bytes so a retried
    /// upload of identical content resumes the same artifact instead of
    /// minting an orphaned intent.
    private func stableRequestID(
        data: Data,
        inputType: RecipeDocumentBatchInputType,
        mimeType: String
    ) -> UUID {
        var identity = Data((inputType.rawValue + "\n" + mimeType + "\n").utf8)
        identity.append(data)
        let digest = Array(SHA256.hash(data: identity))
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            )
        )
    }
}

/// HTTP client for the DEV-427 commercial usage ledger. It only settles one
/// unit per operation and never authors quota or entitlement locally.
struct RecipeUsageService {
    func reserve(_ request: RecipeReservationRequest) async throws -> RecipeReservation {
        try await RecipeSupabase.client.functions.invoke(
            "recipe-usage/reservations",
            options: FunctionInvokeOptions(method: .post, body: request)
        )
    }

    func finalize(
        operationID: String,
        _ request: RecipeUsageFinalizeRequest
    ) async throws -> RecipeUsageFinalizeResponse {
        try await RecipeSupabase.client.functions.invoke(
            "recipe-usage/\(operationID)/finalize",
            options: FunctionInvokeOptions(method: .post, body: request)
        )
    }

    func ack(operationID: String) async throws -> RecipeUsageAckResponse {
        try await RecipeSupabase.client.functions.invoke(
            "recipe-usage/\(operationID)/ack",
            options: FunctionInvokeOptions(method: .post)
        )
    }
}

/// Real candidate-save boundary: one smart_import settle per confirmed candidate
/// (reserve → finalize → local Store write → ACK). Each candidate is a separate
/// usage operation keyed by its stable candidate ID, never a fabricated job.
@MainActor
struct RecipeDocumentBatchUsageSaveBoundary: RecipeDocumentBatchSaveBoundary {
    private let usage: RecipeUsageService
    private let store: RecipeStore

    init(usage: RecipeUsageService = RecipeUsageService(), store: RecipeStore) {
        self.usage = usage
        self.store = store
    }

    func save(
        jobID: UUID,
        candidates: [RecipeDocumentBatchSaveCandidate],
        ownerID: UUID
    ) async throws {
        for candidate in candidates {
            try await settle(candidate, jobID: jobID)
        }
    }

    private func settle(
        _ candidate: RecipeDocumentBatchSaveCandidate,
        jobID: UUID
    ) async throws {
        let jobIDText = jobID.uuidString.lowercased()
        let source = try RecipeUsageSource(
            importJobID: jobIDText, candidateIDs: [candidate.candidateID])
        let inputHash = RecipeUsageHash.importInputHash(
            jobID: jobIDText, candidateID: candidate.candidateID)
        let operationID = UUID().uuidString.lowercased()

        _ = try await usage.reserve(
            try RecipeReservationRequest(
                operationID: operationID,
                capability: .smartImport,
                inputHash: inputHash,
                estimatedUnits: 1,
                source: source
            )
        )
        let finalized = try await usage.finalize(
            operationID: operationID,
            try RecipeUsageFinalizeRequest(
                capability: .smartImport, inputHash: inputHash, source: source)
        )
        try writeFinalized(candidate, jobID: jobID, recipeID: finalized.recipeID)
        _ = try await usage.ack(operationID: operationID)
    }

    /// Writes the settled recipe using the server-produced stable recipe ID, so
    /// a replay or a second operation for the same candidate never duplicates a
    /// dish or overwrites a locally edited recipe.
    private func writeFinalized(
        _ candidate: RecipeDocumentBatchSaveCandidate,
        jobID: UUID,
        recipeID: String
    ) throws {
        guard let targetID = UUID(uuidString: recipeID) else { return }
        // A retry after the user deleted the recipe must not resurrect it.
        guard !store.hasRecipeDeletionTombstone(id: targetID) else { return }
        // A replay (idempotent finalize returns the same recipe id) or a locally
        // edited recipe must never be overwritten.
        guard store.recipe(id: targetID) == nil else { return }
        let title = candidate.title ?? "Untitled Recipe"
        let content =
            title
            + "\n\nIngredients\n" + candidate.ingredients.joined(separator: "\n")
            + "\n\nInstructions\n" + candidate.steps.joined(separator: "\n")
        var recipe = RecipeDocumentParser.recipe(fromText: content, title: title)
        recipe.id = targetID

        var fields: [String: RecipeImportJobResponse.Field] = [:]
        fields["title"] = .init(rawValue: title)
        for (index, raw) in candidate.ingredients.enumerated() {
            let field = RecipeImportJobResponse.Field(rawValue: raw)
            fields["ingredients[\(index)].raw_text"] = field
            fields["ingredients[\(index)].amount"] = field
        }
        for (index, instruction) in candidate.steps.enumerated() {
            fields["steps[\(index)].instruction"] = .init(rawValue: instruction)
        }
        let result = RecipeImportJobResponse.Result(
            recipeID: targetID,
            status: "needs_review",
            source: RecipeImportJobResponse.Source(inputType: "image"),
            fields: fields,
            evidence: [],
            reviewFields: []
        )
        recipe.importRecord = RecipeImportRecord(
            jobID: jobID,
            result: result,
            selectedCandidateID: candidate.candidateID
        )
        try store.upsert(recipe)
    }
}
