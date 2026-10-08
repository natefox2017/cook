// Developer: gengyun
// Purpose: Calls the frozen authenticated Recipe Import API for durable job lifecycle operations.

import Foundation
import RecipeCore
import Supabase

struct RecipeImportJobService: RecipeImportJobClient {
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

    func submit(
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

    func fetch(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        try await verifySession(ownerID: ownerID)
        return try await RecipeSupabase.client.functions.invoke(
            "recipe-imports/\(jobID.uuidString.lowercased())",
            options: FunctionInvokeOptions(method: .get)
        )
    }

    func retry(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        try await verifySession(ownerID: ownerID)
        return try await RecipeSupabase.client.functions.invoke(
            "recipe-imports/\(jobID.uuidString.lowercased())/retry",
            options: FunctionInvokeOptions(method: .post)
        )
    }

    private func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw RecipeShareImportWorkflowError.accountChanged
        }
    }
}
