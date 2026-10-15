// Developer: gengyun
// Purpose: Bounded, session-scoped recipe Q&A client for the recipe-questions Edge Function.

import Foundation
import RecipeCore
import Supabase

enum RecipeQuestionError: LocalizedError {
    case notSignedIn
    case invalidConfiguration
    case questionTooLong
    case staleGeneration
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return RecipeLanguage.localized("Sign in to ask about this recipe.")
        case .invalidConfiguration:
            return RecipeLanguage.localized("The question service is not configured.")
        case .questionTooLong:
            return RecipeLanguage.localized("Keep the question under 1000 characters.")
        case .staleGeneration:
            return RecipeLanguage.localized("This answer belongs to a previous session.")
        case .transport(let message):
            return message
        }
    }
}

struct RecipeQuestionStatement: Decodable, Hashable, Sendable {
    enum Kind: String, Decodable, Hashable, Sendable {
        case recipe
        case ai
    }

    let kind: Kind
    let text: String
}

struct RecipeQuestionAnswer: Decodable, Hashable, Sendable {
    let operationID: UUID
    let answer: String
    let statements: [RecipeQuestionStatement]
    let revision: Int

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case answer
        case statements
        case revision
    }
}

/// A single in-memory question/answer exchange. Q&A history is session-scoped
/// and intentionally never persisted to the recipe library or a chat store.
struct RecipeQuestionTurn: Hashable, Sendable {
    let question: String
    let answer: String
}

@MainActor
final class RecipeQuestionService {
    /// HTTP transport seam kept injectable so tests can pause and resume
    /// responses without touching the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Session seam kept injectable so tests can drive auth without a real Supabase session.
    typealias SessionProvider = @Sendable () async throws -> (accessToken: String, userID: UUID)

    private let baseURL: URL
    private let publishableKey: String
    private let transport: Transport
    private let sessionProvider: SessionProvider

    /// Latest five exchanges of the current session, oldest first.
    private(set) var history: [RecipeQuestionTurn] = []
    /// Bumped on sign-out or account switch so stale in-flight answers are discarded.
    private(set) var generation: UUID = UUID()

    private static let maximumHistoryTurns = 5
    private static let maximumQuestionCharacters = 1000

    convenience init(
        bundle: Bundle = .main,
        transport: Transport? = nil,
        sessionProvider: SessionProvider? = nil
    ) throws {
        guard
            let origin = bundle.object(
                forInfoDictionaryKey: "RecipeSupabaseURL"
            ) as? String,
            let url = URL(string: origin),
            url.scheme == "https",
            let host = url.host,
            host.hasSuffix(".supabase.co"),
            let key = bundle.object(
                forInfoDictionaryKey: "RecipeSupabasePublishableKey"
            ) as? String,
            !key.isEmpty
        else {
            throw RecipeQuestionError.invalidConfiguration
        }
        self.init(
            baseURL: url.appendingPathComponent("functions/v1/recipe-questions"),
            publishableKey: key,
            transport: transport ?? { request in
                try await URLSession.shared.data(for: request)
            },
            sessionProvider: sessionProvider ?? {
                let session = try await RecipeSupabase.client.auth.session
                return (session.accessToken, session.user.id)
            }
        )
    }

    /// Test seam: inject the resolved endpoint and closures directly.
    init(
        baseURL: URL,
        publishableKey: String,
        transport: @escaping Transport,
        sessionProvider: @escaping SessionProvider
    ) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.transport = transport
        self.sessionProvider = sessionProvider
    }

    func ask(recipe: Recipe, question: String) async throws -> RecipeQuestionAnswer {
        guard question.unicodeScalars.count <= Self.maximumQuestionCharacters else {
            throw RecipeQuestionError.questionTooLong
        }
        let session: (accessToken: String, userID: UUID)
        do {
            session = try await sessionProvider()
        } catch {
            throw RecipeQuestionError.notSignedIn
        }

        let capturedGeneration = generation
        let operationID = UUID()
        let snapshot = Self.snapshot(for: recipe)
        let revision = Self.revision(for: recipe)

        let body: [String: Any] = [
            "recipe_id": recipe.id.uuidString.lowercased(),
            "revision": revision,
            "snapshot": [
                "title": snapshot.title,
                "ingredients": snapshot.ingredients,
                "steps": snapshot.steps,
                "source": snapshot.source.map { $0 as Any } ?? NSNull(),
            ],
            "question": question,
            "history": history.map { ["question": $0.question, "answer": $0.answer] },
            "operation_id": operationID.uuidString.lowercased(),
        ]
        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "Bearer " + session.accessToken,
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let answer: RecipeQuestionAnswer
        do {
            answer = try await Self.decode(
                transport: transport,
                request: request,
                expectedGeneration: capturedGeneration,
                generation: generation
            )
        } catch {
            // A failed exchange never mutates session history.
            throw error
        }

        history.append(
            RecipeQuestionTurn(question: question, answer: answer.answer)
        )
        if history.count > Self.maximumHistoryTurns {
            history.removeFirst(history.count - Self.maximumHistoryTurns)
        }
        return answer
    }

    /// Clears session history and invalidates in-flight answers. Called on
    /// sign-out, account switch, and sheet dismissal.
    func close() {
        generation = UUID()
        history.removeAll()
    }

    private static func decode(
        transport: Transport,
        request: URLRequest,
        expectedGeneration: UUID,
        generation: UUID
    ) async throws -> RecipeQuestionAnswer {
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else {
            throw RecipeQuestionError.transport(
                RecipeLanguage.localized("The question service did not respond.")
            )
        }
        guard expectedGeneration == generation else {
            throw RecipeQuestionError.staleGeneration
        }
        guard (200...299).contains(response.statusCode) else {
            if let server = try? JSONDecoder().decode(
                RecipeQuestionServerError.self, from: data
            ) {
                throw RecipeQuestionError.transport(server.error.message)
            }
            throw RecipeQuestionError.transport(
                RecipeLanguage.localized("Could not answer that question right now.")
            )
        }
        return try JSONDecoder().decode(RecipeQuestionAnswer.self, from: data)
    }

    private struct RecipeQuestionServerError: Decodable {
        let error: Payload

        struct Payload: Decodable {
            let code: String
            let message: String
        }
    }

    private static func snapshot(for recipe: Recipe) -> (
        title: String, ingredients: [String], steps: [String], source: String?
    ) {
        let ingredients = recipe.ingredients.map { ingredient in
            ingredient.amountText.isEmpty
                ? ingredient.name
                : "\(ingredient.amountText) \(ingredient.name)"
        }
        let steps = recipe.steps.map { step in
            step.title.isEmpty
                ? step.instruction
                : "\(step.title): \(step.instruction)"
        }
        return (
            title: recipe.title,
            ingredients: ingredients,
            steps: steps,
            source: recipe.sourceURL ?? recipe.sourceName
        )
    }

    private static func revision(for recipe: Recipe) -> Int {
        max(1, Int(recipe.updatedAt.timeIntervalSince1970))
    }
}
