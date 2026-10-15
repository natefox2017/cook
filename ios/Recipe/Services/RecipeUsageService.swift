// Developer: gengyun
// Purpose: Implements the frozen commercial usage routes through Supabase Edge Functions for the import quota bridge.

import Foundation
import RecipeCore
import Supabase

/// Concrete `RecipeUsageClient` backed by the authenticated `recipe-access` and `recipe-usage`
/// Edge Functions. It only ever forwards server-owned values; quota and entitlement are never authored here.
struct RecipeUsageService: RecipeUsageClient {
    private static var clientStage: String {
        RecipeMonetization.isEnabled
            ? RecipeReleaseStage.commercial.rawValue
            : RecipeReleaseStage.freeTest.rawValue
    }

    private static var stageHeaders: [String: String] {
        ["x-recipe-pals-stage": clientStage]
    }

    func access(ownerID: UUID) async throws -> RecipeAccessResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke("recipe-access", options: FunctionInvokeOptions(method: .get))
    }

    func reserve(
        ownerID: UUID,
        request: RecipeReservationRequest
    ) async throws -> RecipeReservation {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-usage/reservations",
            options: FunctionInvokeOptions(
                method: .post,
                headers: Self.stageHeaders,
                body: request
            )
        )
    }

    func finalize(
        ownerID: UUID,
        operationID: String,
        request: RecipeUsageFinalizeRequest
    ) async throws -> RecipeUsageFinalizeResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-usage/\(operationID)/finalize",
            options: FunctionInvokeOptions(
                method: .post,
                headers: Self.stageHeaders,
                body: request
            )
        )
    }

    func acknowledge(
        ownerID: UUID,
        operationID: String
    ) async throws -> RecipeUsageAckResponse {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-usage/\(operationID)/ack",
            options: FunctionInvokeOptions(
                method: .post,
                headers: Self.stageHeaders
            )
        )
    }

    func release(
        ownerID: UUID,
        operationID: String
    ) async throws -> RecipeReservation {
        try await verifySession(ownerID: ownerID)
        return try await invoke(
            "recipe-usage/\(operationID)/release",
            options: FunctionInvokeOptions(
                method: .post,
                headers: Self.stageHeaders
            )
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

    private static func failure(from error: Error) -> RecipeUsageFailure {
        if let functionsError = error as? FunctionsError,
            case let .httpError(_, data) = functionsError,
            let apiError = try? JSONDecoder().decode(RecipeUsageAPIError.self, from: data)
        {
            return RecipeUsageFailure(apiError: apiError)
        }
        return .transport(error.localizedDescription)
    }

    private func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw RecipeUsageFailure.api(
                .ownerMismatch, recoverable: false, message: nil, requestID: nil)
        }
    }
}
