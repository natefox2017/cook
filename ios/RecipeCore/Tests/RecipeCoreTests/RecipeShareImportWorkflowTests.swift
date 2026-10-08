// Developer: gengyun
// Purpose: Verifies owner-safe durable share submission and completed import handling.

import Foundation
import Testing
@testable import RecipeCore

@MainActor
private final class StubRecipeImportJobClient: RecipeImportJobClient {
    var submitResponse: RecipeImportJobResponse
    var fetchResponses: [RecipeImportJobResponse]
    var retryResponses: [RecipeImportJobResponse]
    var submitCount = 0
    var fetchCount = 0
    var retryCount = 0
    var submittedRequestIDs: [UUID] = []
    var submittedSources: [String] = []
    var onSubmit: (() throws -> Void)?

    init(
        submitResponse: RecipeImportJobResponse,
        fetchResponses: [RecipeImportJobResponse] = [],
        retryResponses: [RecipeImportJobResponse] = []
    ) {
        self.submitResponse = submitResponse
        self.fetchResponses = fetchResponses
        self.retryResponses = retryResponses
    }

    func submit(
        receipt: RecipeShareReceipt,
        source: String,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        submitCount += 1
        submittedRequestIDs.append(receipt.clientRequestID)
        submittedSources.append(source)
        try onSubmit?()
        return submitResponse
    }

    func fetch(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        fetchCount += 1
        guard !fetchResponses.isEmpty else {
            throw StubError.missingResponse
        }
        if fetchResponses.count == 1 {
            return fetchResponses[0]
        }
        return fetchResponses.removeFirst()
    }

    func retry(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse {
        retryCount += 1
        guard !retryResponses.isEmpty else {
            throw StubError.missingResponse
        }
        if retryResponses.count == 1 {
            return retryResponses[0]
        }
        return retryResponses.removeFirst()
    }

    private enum StubError: Error {
        case missingResponse
    }
}

@MainActor
private struct ShareWorkflowFixture {
    let containerURL: URL
    let libraryURL: URL
    let inbox: RecipeShareInbox
    let store: RecipeStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeShareImportWorkflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        containerURL = directory.appendingPathComponent("group", isDirectory: true)
        libraryURL = directory.appendingPathComponent("library.json")
        inbox = try RecipeShareInbox(containerURL: containerURL)
        store = RecipeStore(fileURL: libraryURL)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: containerURL.deletingLastPathComponent())
    }
}

private func jobResponse(
    receipt: RecipeShareReceipt,
    jobID: UUID,
    status: RecipeImportJobResponse.Status,
    queueConfirmedAt: String? = nil,
    recipeID: UUID? = nil,
    result: RecipeImportJobResponse.Result? = nil,
    error: RecipeImportJobResponse.Failure? = nil
) -> RecipeImportJobResponse {
    RecipeImportJobResponse(
        jobID: jobID,
        clientRequestID: receipt.clientRequestID,
        status: status,
        attemptCount: 1,
        queueConfirmedAt: queueConfirmedAt,
        recipeID: recipeID,
        result: result,
        error: error
    )
}

private func completedResult(
    recipeID: UUID,
    inputType: String,
    title: String
) -> RecipeImportJobResponse.Result {
    RecipeImportJobResponse.Result(
        recipeID: recipeID,
        status: "needs_review",
        source: .init(
            inputType: inputType,
            originalURL: inputType == "url" ? "https://example.org/recipe" : nil,
            platform: "shared",
            sourceTitle: "Shared source"
        ),
        fields: ["title": .init(rawValue: title)],
        evidence: []
    )
}

@Test
func importJobResponseDecodesFrozenTextResultWithOptionalReviewFields() throws {
    let jobID = UUID(uuidString: "6c970725-d87a-4864-aee7-bfe743796916")!
    let requestID = UUID(uuidString: "5fc04a2e-a59b-4f41-9ed2-f92b3513f9fb")!
    let recipeID = UUID(uuidString: "5a555950-29fa-48b8-8083-e3864b7defa6")!
    let evidenceID = UUID(uuidString: "4c274cfe-701e-4cc3-9ba4-10cf5d10e807")!
    let json = """
    {
      "job_id": "\(jobID)",
      "client_request_id": "\(requestID)",
      "status": "completed",
      "attempt_count": 1,
      "queue_confirmed_at": "2026-10-08T00:00:00Z",
      "recipe_id": "\(recipeID)",
      "result": {
        "recipe_id": "\(recipeID)",
        "status": "needs_review",
        "source": { "input_type": "text" },
        "fields": {
          "title": {
            "raw_value": "Soup",
            "normalized_value": null,
            "evidence_ids": ["\(evidenceID)"],
            "confidence": 1,
            "user_confirmed": false,
            "origin": "extracted",
            "updated_at": "2026-10-08T00:00:00Z"
          }
        },
        "evidence": [{
          "id": "\(evidenceID)",
          "source_type": "user",
          "origin": "user",
          "excerpt": "Soup",
          "confidence": 1,
          "captured_at": "2026-10-08T00:00:00Z"
        }]
      }
    }
    """

    let response = try JSONDecoder().decode(
        RecipeImportJobResponse.self,
        from: Data(json.utf8)
    )

    #expect(response.isDurablyQueued)
    #expect(response.result?.recipeID == recipeID)
    #expect(response.result?.reviewFields == nil)
    #expect(response.result?.fields["title"]?.rawValue == "Soup")
    #expect(response.result?.evidence.first?.id == evidenceID)
}

@Test @MainActor
func receivedJobPersistsOriginalRequestIDWithoutQueueAcknowledgement() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    let receipt = try fixture.inbox.receive("Lemon dressing", as: .text)
    let jobID = UUID()
    let received = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .received
    )
    let client = StubRecipeImportJobClient(
        submitResponse: received,
        fetchResponses: [received]
    )

    let report = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    #expect(report.jobStatuses[receipt.id]?.status == .received)
    #expect(client.submittedRequestIDs == [receipt.clientRequestID])
    #expect(client.submittedSources == ["Lemon dressing"])
    #expect(try fixture.inbox.receivedJobID(for: receipt, ownerID: ownerID) == jobID)
    #expect(try fixture.inbox.acknowledgedJobID(for: receipt, ownerID: ownerID) == nil)
    #expect(try fixture.inbox.pendingReceipts(for: ownerID) == [receipt])
}

@Test @MainActor
func completedTextIsSavedWithSourceAndReplayPreservesUserEdits() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    let source = "Lemon dressing\nIngredients:\nOlive oil, about a little\nSalt to taste\nDirections:\nMix and serve."
    let receipt = try fixture.inbox.receive(source, as: .text)
    let jobID = UUID()
    let recipeID = UUID()
    let queued = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .queued,
        queueConfirmedAt: "2026-10-08T00:00:00Z"
    )
    let completed = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .completed,
        queueConfirmedAt: "2026-10-08T00:00:00Z",
        recipeID: recipeID,
        result: completedResult(
            recipeID: recipeID,
            inputType: "text",
            title: "Lemon dressing"
        )
    )
    let client = StubRecipeImportJobClient(
        submitResponse: queued,
        fetchResponses: [completed]
    )

    _ = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    let imported = try #require(fixture.store.recipe(id: recipeID))
    #expect(imported.sourceText == source)
    #expect(imported.sourceName == "Shared source")
    #expect(imported.ingredients.map(\.name) == [
        "Olive oil, about a little",
        "Salt to taste"
    ])
    #expect(imported.ingredients.allSatisfy { $0.quantity == nil })

    var edited = imported
    edited.title = "My edited dressing"
    try fixture.store.upsert(edited)
    _ = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    #expect(fixture.store.recipes.count == 1)
    #expect(fixture.store.recipe(id: recipeID)?.title == "My edited dressing")
}

@Test @MainActor
func recoverableFailureRetriesSameJobOnceAndCanLaterComplete() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    let receipt = try fixture.inbox.receive("Lemon dressing", as: .text)
    let jobID = UUID()
    let recipeID = UUID()
    let queued = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .queued,
        queueConfirmedAt: "2026-10-08T00:00:00Z"
    )
    let failed = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .failed,
        queueConfirmedAt: "2026-10-08T00:00:00Z",
        error: .init(code: "temporary", message: "Try again", recoverable: true)
    )
    let requeued = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .queued,
        queueConfirmedAt: "2026-10-08T00:00:00Z"
    )
    let completed = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .completed,
        queueConfirmedAt: "2026-10-08T00:00:00Z",
        recipeID: recipeID,
        result: completedResult(recipeID: recipeID, inputType: "text", title: "Lemon dressing")
    )
    let client = StubRecipeImportJobClient(
        submitResponse: queued,
        fetchResponses: [failed, completed],
        retryResponses: [requeued]
    )

    _ = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )
    #expect(client.retryCount == 1)
    #expect(try fixture.inbox.acknowledgedJobID(for: receipt, ownerID: ownerID) == jobID)

    _ = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )
    #expect(client.retryCount == 1)
    #expect(fixture.store.recipe(id: recipeID)?.sourceText == "Lemon dressing")
}

@Test @MainActor
func accountSwitchDuringSubmitDoesNotAcknowledgeOrSave() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    var activeOwnerID: UUID? = ownerID
    let receipt = try fixture.inbox.receive("Lemon dressing", as: .text)
    let jobID = UUID()
    let client = StubRecipeImportJobClient(
        submitResponse: jobResponse(
            receipt: receipt,
            jobID: jobID,
            status: .queued,
            queueConfirmedAt: "2026-10-08T00:00:00Z"
        )
    )
    client.onSubmit = { activeOwnerID = UUID() }

    let report = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { activeOwnerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    #expect(report.failureMessage?.contains("account changed") == true)
    #expect(try fixture.inbox.acknowledgedJobID(for: receipt, ownerID: ownerID) == nil)
    #expect(fixture.store.recipes.isEmpty)
}

@Test @MainActor
func localDeletionDuringSubmitPreventsAcknowledgementAndRecipeSave() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    let receipt = try fixture.inbox.receive("Lemon dressing", as: .text)
    let client = StubRecipeImportJobClient(
        submitResponse: jobResponse(
            receipt: receipt,
            jobID: UUID(),
            status: .queued,
            queueConfirmedAt: "2026-10-08T00:00:00Z"
        )
    )
    client.onSubmit = { try fixture.inbox.eraseAllLocalReceipts() }

    _ = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    #expect(try fixture.inbox.acknowledgedJobID(for: receipt, ownerID: ownerID) == nil)
    #expect(fixture.store.recipes.isEmpty)
    #expect(try fixture.inbox.pendingReceipts().isEmpty)
}

@Test @MainActor
func completedURLResultIsReportedAndNeverSavedAsARecipe() async throws {
    let fixture = try ShareWorkflowFixture()
    defer { fixture.removeFiles() }
    let ownerID = UUID()
    let receipt = try fixture.inbox.receive("https://example.org/recipe", as: .url)
    let jobID = UUID()
    let recipeID = UUID()
    let queued = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .queued,
        queueConfirmedAt: "2026-10-08T00:00:00Z"
    )
    let completed = jobResponse(
        receipt: receipt,
        jobID: jobID,
        status: .completed,
        queueConfirmedAt: "2026-10-08T00:00:00Z",
        recipeID: recipeID,
        result: completedResult(
            recipeID: recipeID,
            inputType: "url",
            title: "Unsupported URL recipe"
        )
    )
    let client = StubRecipeImportJobClient(
        submitResponse: queued,
        fetchResponses: [completed]
    )

    let report = await RecipeShareImportWorkflow.synchronize(
        inbox: fixture.inbox,
        store: fixture.store,
        client: client,
        ownerID: ownerID,
        currentOwnerID: { ownerID },
        maxPollRounds: 1,
        pollInterval: .zero
    )

    #expect(report.failureMessage?.contains("not supported") == true)
    #expect(report.jobStatuses[receipt.id]?.status == .completed)
    #expect(client.fetchCount == 1)
    #expect(fixture.store.recipes.isEmpty)
    #expect(try fixture.inbox.acknowledgedJobID(for: receipt, ownerID: ownerID) == jobID)
}
