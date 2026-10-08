// Developer: gengyun
// Purpose: Submits and retrieves authenticated import jobs without losing original source evidence.

import Foundation
import RecipeCore
import Supabase

enum RecipeRemoteImportError: LocalizedError {
    case notSignedIn
    case invalidConfiguration
    case transport(String)
    case jobNotReady

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in before sending a recipe to cloud processing."
        case .invalidConfiguration:
            "The RecipePouch import service is not configured."
        case .transport(let message):
            message
        case .jobNotReady:
            "The recipe has not finished processing. Your original source is still saved."
        }
    }
}

struct RecipeRemoteImportJob: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case received, queued, extracting, parsing, validating, completed, failed
    }

    struct Field: Decodable, Sendable {
        let rawValue: String?
        let userConfirmed: Bool?

        enum CodingKeys: String, CodingKey {
            case rawValue = "raw_value"
            case userConfirmed = "user_confirmed"
        }
    }

    struct Result: Decodable, Sendable {
        let recipeID: UUID
        let status: String
        let fields: [String: Field]
        let reviewFields: [String]

        enum CodingKeys: String, CodingKey {
            case recipeID = "recipe_id"
            case status, fields
            case reviewFields = "review_fields"
        }
    }

    let jobID: UUID
    let clientRequestID: UUID
    let status: Status
    let recipeID: UUID?
    let recipeStatus: String?
    let result: Result?
    let error: ServerError?

    struct ServerError: Decodable, Sendable {
        let code: String
        let message: String
        let recoverable: Bool
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status, result, error
        case recipeID = "recipe_id"
        case recipeStatus = "recipe_status"
    }
}

/// This adapter deliberately does not depend on the draft #30 Share receipt
/// implementation. Its stable UUID/source arguments can later be passed from
/// that inbox without introducing a second idempotency model.
@MainActor
struct RecipeRemoteImportService {
    private let baseURL: URL
    private let publishableKey: String

    init(bundle: Bundle = .main) throws {
        guard let origin = bundle.object(
            forInfoDictionaryKey: "RecipeSupabaseURL"
        ) as? String,
              let url = URL(string: origin),
              url.scheme == "https",
              let host = url.host,
              host.hasSuffix(".supabase.co"),
              let key = bundle.object(
                  forInfoDictionaryKey: "RecipeSupabasePublishableKey"
              ) as? String,
              !key.isEmpty else {
            throw RecipeRemoteImportError.invalidConfiguration
        }

        baseURL = url.appendingPathComponent(
            "functions/v1/recipe-imports"
        )
        publishableKey = key
    }

    func createJob(
        clientRequestID: UUID,
        inputType: String,
        originalSource: String
    ) async throws -> RecipeRemoteImportJob {
        guard ["url", "text"].contains(inputType) else {
            throw RecipeRemoteImportError.transport(
                "Cloud media uploads are not yet available. Share a link or text."
            )
        }

        // Keep the original text unchanged; the server expects a source field
        // named exactly "url" or "text".
        var body = [
            "client_request_id": clientRequestID.uuidString,
            "input_type": inputType
        ]
        body[inputType] = originalSource
        let data = try JSONEncoder().encode(body)
        return try await send(
            method: "POST",
            destination: baseURL,
            body: data
        )
    }

    func getJob(_ identifier: UUID) async throws -> RecipeRemoteImportJob {
        try await send(
            method: "GET",
            destination: baseURL.appendingPathComponent(identifier.uuidString),
            body: nil
        )
    }

    func retryJob(_ identifier: UUID) async throws -> RecipeRemoteImportJob {
        try await send(
            method: "POST",
            destination: baseURL
                .appendingPathComponent(identifier.uuidString)
                .appendingPathComponent("retry"),
            body: nil
        )
    }

    private func send(
        method: String,
        destination: URL,
        body: Data?
    ) async throws -> RecipeRemoteImportJob {
        let session: Session
        do {
            session = try await RecipeSupabase.client.auth.session
        } catch {
            throw RecipeRemoteImportError.notSignedIn
        }

        var request = URLRequest(url: destination)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(
            "Bearer " + session.accessToken,
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RecipeRemoteImportError.transport(
                "The cloud import service did not return an HTTP response."
            )
        }

        if (200...299).contains(response.statusCode) {
            return try JSONDecoder().decode(RecipeRemoteImportJob.self, from: data)
        }

        if let error = try? JSONDecoder().decode(
            RecipeRemoteImportJob.ServerError.self,
            from: data
        ) {
            throw RecipeRemoteImportError.transport(error.message)
        }

        throw RecipeRemoteImportError.transport(
            "Cloud import unavailable (HTTP \(response.statusCode)). The source is still saved on this iPhone."
        )
    }

    /// A completed text job can be mapped into the existing local Recipe
    /// model. It never replaces a recipe already edited on this device.
    /// Full backend evidence remains on the server until a future native
    /// evidence model is defined; original text is always preserved locally.
    static func saveCompletedTextJob(
        _ job: RecipeRemoteImportJob,
        originalSource: String,
        into store: RecipeStore
    ) throws -> Recipe? {
        guard job.status == .completed,
              let result = job.result,
              let recipeID = job.recipeID,
              recipeID == result.recipeID else {
            throw RecipeRemoteImportError.jobNotReady
        }
        if store.recipe(id: recipeID) != nil {
            return nil
        }

        let title = result.fields["title"]?.rawValue
            ?? "Imported recipe"
        var parsed = RecipeDocumentParser.recipe(
            fromText: originalSource, title: title
        )
        parsed.id = recipeID
        parsed.sourceText = originalSource
        parsed.sourceName = "RecipePouch import"
        parsed.servings = nil
        try store.upsert(parsed)
        return parsed
    }
}
