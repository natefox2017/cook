// Developer: gengyun
// Purpose: Calls the frozen authenticated Recipe Import API for durable job lifecycle operations.

import Foundation
import RecipeCore
import Supabase

struct RecipeImportJobResponse: Decodable, Sendable {
    enum Status: String, Decodable, Equatable, Sendable {
        case received
        case queued
        case extracting
        case parsing
        case validating
        case completed
        case failed
    }

    struct Failure: Decodable, Sendable {
        let code: String
        let message: String
        let recoverable: Bool?
        let suggestedAction: String?

        private enum CodingKeys: String, CodingKey {
            case code
            case message
            case recoverable
            case suggestedAction = "suggested_action"
        }
    }

    let jobID: UUID
    let clientRequestID: UUID
    let status: Status
    let stage: String?
    let attemptCount: Int
    let queueConfirmedAt: String?
    let recipeID: UUID?
    let recipeStatus: String?
    let existingRecipeID: UUID?
    let reviewCount: Int?
    let error: Failure?

    var isDurablyQueued: Bool {
        guard status != .received, let queueConfirmedAt else {
            return false
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if fractionalFormatter.date(from: queueConfirmedAt) != nil {
            return true
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: queueConfirmedAt) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status
        case stage
        case attemptCount = "attempt_count"
        case queueConfirmedAt = "queue_confirmed_at"
        case recipeID = "recipe_id"
        case recipeStatus = "recipe_status"
        case existingRecipeID = "existing_recipe_id"
        case reviewCount = "review_count"
        case error
    }
}

enum RecipeImportJobService {
    enum ServiceError: LocalizedError {
        case accountChanged
        case queueNotConfirmed
        case responseMismatch

        var errorDescription: String? {
            switch self {
            case .accountChanged:
                "Your signed-in account changed. The saved source was kept for the correct account."
            case .queueNotConfirmed:
                "The server has not confirmed durable queue admission. The saved source remains available."
            case .responseMismatch:
                "The server response did not match this saved source. The local receipt was kept."
            }
        }
    }

    private struct Submission: Encodable {
        let clientRequestID: UUID
        let inputType: RecipeShareInputType
        let url: String?
        let text: String?

        private enum CodingKeys: String, CodingKey {
            case clientRequestID = "client_request_id"
            case inputType = "input_type"
            case url
            case text
        }

        init(receipt: RecipeShareReceipt, source: String) {
            clientRequestID = receipt.clientRequestID
            inputType = receipt.inputType
            url = receipt.inputType == .url ? source : nil
            text = receipt.inputType == .text ? source : nil
        }
    }

    static func submit(
        receipt: RecipeShareReceipt,
        source: String,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        try await verifySession(ownerID: ownerID)
        return try await RecipeSupabase.client.functions.invoke(
            "recipe-imports",
            options: FunctionInvokeOptions(
                method: .post,
                body: Submission(receipt: receipt, source: source)
            )
        )
    }

    static func fetch(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        try await verifySession(ownerID: ownerID)
        return try await RecipeSupabase.client.functions.invoke(
            "recipe-imports/\(jobID.uuidString.lowercased())",
            options: FunctionInvokeOptions(method: .get)
        )
    }

    static func retry(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        try await verifySession(ownerID: ownerID)
        return try await RecipeSupabase.client.functions.invoke(
            "recipe-imports/\(jobID.uuidString.lowercased())/retry",
            options: FunctionInvokeOptions(method: .post)
        )
    }

    private static func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw ServiceError.accountChanged
        }
    }
}
