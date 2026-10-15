// Developer: gengyun
// Purpose: Verifies bounded recipe Q&A session history and stale-generation handling without network.

import Foundation
import RecipeCore
import XCTest

@testable import Recipe

private let questionBaseURL = URL(
    string: "https://example.supabase.co/functions/v1/recipe-questions"
)!

private func answerData() throws -> Data {
    let json = """
    {
        "operation_id": "\(UUID().uuidString)",
        "answer": "Simmer until soft.",
        "statements": [
            { "kind": "recipe", "text": "Simmer the tomatoes." },
            { "kind": "ai", "text": "Adding cream is not stated." }
        ],
        "revision": 1
    }
    """
    return Data(json.utf8)
}

private func httpResponse(statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: questionBaseURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

/// Suspends each call until the test resumes it, so generation changes can land
/// while an ask is in flight.
private actor PausableTransport {
    private var continuation:
        CheckedContinuation<(Data, URLResponse), any Error>?
    private var wasCalled = false

    func call(_ request: URLRequest) async throws -> (Data, URLResponse) {
        wasCalled = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilCalled() async {
        while !wasCalled {
            await Task.yield()
        }
    }

    func complete(with result: Result<(Data, URLResponse), any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
final class RecipeQuestionServiceTests: XCTestCase {
    private var recipe: Recipe {
        SampleRecipes.recipes[0]
    }

    private func makeService(
        transport: @escaping RecipeQuestionService.Transport,
        sessionProvider: @escaping RecipeQuestionService.SessionProvider = {
            ("test-token", UUID())
        }
    ) -> RecipeQuestionService {
        RecipeQuestionService(
            baseURL: questionBaseURL,
            publishableKey: "sb_publishable_test",
            transport: transport,
            sessionProvider: sessionProvider
        )
    }

    func testSuccessfulAskAppendsHistoryAndCapsAtFive() async throws {
        let data = try answerData()
        let response = httpResponse()
        let service = makeService { _ in (data, response) }

        for index in 0..<6 {
            _ = try await service.ask(
                recipe: recipe,
                question: "Question \(index)?"
            )
        }

        XCTAssertEqual(service.history.count, 5)
        XCTAssertEqual(service.history[0].question, "Question 1?")
        XCTAssertEqual(service.history[4].question, "Question 5?")
    }

    func testFailedAskDoesNotAppendHistory() async throws {
        let service = makeService { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await service.ask(recipe: recipe, question: "How long?")
            XCTFail("Expected the ask to fail.")
        } catch {
            // The failure path is the subject; the specific error is not.
        }

        XCTAssertTrue(service.history.isEmpty)
    }

    func testCloseClearsHistoryAndBumpsGeneration() async throws {
        let data = try answerData()
        let response = httpResponse()
        let service = makeService { _ in (data, response) }

        _ = try await service.ask(recipe: recipe, question: "How long?")
        XCTAssertFalse(service.history.isEmpty)

        let generation = service.generation
        service.close()

        XCTAssertTrue(service.history.isEmpty)
        XCTAssertNotEqual(service.generation, generation)
    }

    func testStaleGenerationDiscardsInFlightAnswer() async throws {
        let gate = PausableTransport()
        let service = makeService { request in
            try await gate.call(request)
        }

        let task = Task { try await service.ask(recipe: recipe, question: "How long?") }
        await gate.waitUntilCalled()

        // Account switch or sheet dismissal invalidates the in-flight answer.
        service.close()

        let data = try answerData()
        await gate.complete(with: .success((data, httpResponse())))

        do {
            _ = try await task.value
            XCTFail("Expected a stale-generation failure.")
        } catch let error as RecipeQuestionError {
            guard case .staleGeneration = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        XCTAssertTrue(service.history.isEmpty)
    }

    func testQuestionOverLimitIsRejectedBeforeTransport() async throws {
        let service = makeService { _ in
            throw URLError(.notConnectedToInternet)
        }
        let question = String(repeating: "x", count: 1001)

        do {
            _ = try await service.ask(recipe: recipe, question: question)
            XCTFail("Expected the over-limit question to be rejected.")
        } catch let error as RecipeQuestionError {
            guard case .questionTooLong = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        XCTAssertTrue(service.history.isEmpty)
    }
}
