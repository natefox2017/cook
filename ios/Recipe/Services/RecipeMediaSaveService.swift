// Developer: gengyun
// Purpose: Implements the DEV-78 recipe-media-save endpoints through Supabase Edge Functions.

import Foundation
import RecipeCore
import Supabase

/// Concrete `RecipeMediaSaveClient` backed by the authenticated `recipe-media-save` Edge Function.
/// It sends only `{job_id}` for finalize/release; the server derives the payload/hash from the owned
/// persisted job result, so the client never authors the media payload.
struct RecipeMediaSaveService: RecipeMediaSaveClient {
    private struct ReserveBody: Encodable {
        let jobID: UUID
        let candidateIDs: [String]

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case candidateIDs = "candidate_ids"
        }
    }

    private struct JobBody: Encodable {
        let jobID: UUID

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
        }
    }

    func reserveMediaBundle(
        ownerID: UUID,
        jobID: UUID,
        candidateIDs: [String]
    ) async throws -> RecipeMediaBundleReserveResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-media-save/reserve",
            options: FunctionInvokeOptions(
                method: .post,
                body: ReserveBody(jobID: jobID, candidateIDs: candidateIDs)
            )
        )
    }

    func finalizeMedia(
        ownerID: UUID,
        jobID: UUID
    ) async throws -> RecipeMediaActionResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-media-save/finalize",
            options: FunctionInvokeOptions(method: .post, body: JobBody(jobID: jobID))
        )
    }

    func releaseMedia(
        ownerID: UUID,
        jobID: UUID
    ) async throws -> RecipeMediaActionResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-media-save/release",
            options: FunctionInvokeOptions(method: .post, body: JobBody(jobID: jobID))
        )
    }

    private func invoke<T: Decodable>(
        _ function: String,
        options: FunctionInvokeOptions
    ) async throws -> T {
        do {
            return try await RecipeSupabase.client.functions.invoke(function, options: options)
        } catch {
            throw Self.failure(from: error)
        }
    }

    private static func failure(from error: Error) -> RecipeMediaSaveAPIError {
        if let functionsError = error as? FunctionsError,
            case let .httpError(_, data) = functionsError,
            let apiError = try? JSONDecoder().decode(RecipeMediaSaveAPIError.self, from: data)
        {
            return apiError
        }
        return RecipeMediaSaveAPIError(code: "TRANSPORT", message: error.localizedDescription)
    }

    private func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw RecipeMediaSaveAPIError(
                code: "OWNER_MISMATCH", message: "The signed-in account changed.")
        }
    }
}
