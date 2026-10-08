// Developer: gengyun
// Purpose: Delivers durable share receipts through the owner-scoped import job lifecycle.

import Foundation

public struct RecipeShareImportReport: Sendable {
    public let jobStatuses: [UUID: RecipeImportJobResponse]
    public let failureMessage: String?

    public init(
        jobStatuses: [UUID: RecipeImportJobResponse],
        failureMessage: String?
    ) {
        self.jobStatuses = jobStatuses
        self.failureMessage = failureMessage
    }
}

public enum RecipeShareImportWorkflowError: LocalizedError {
    case accountChanged
    case queueNotConfirmed
    case responseMismatch
    case localSourceChanged
    case completedResultMissing
    case unsupportedCompletedInput

    public var errorDescription: String? {
        switch self {
        case .accountChanged:
            "Your signed-in account changed. The saved source was kept for the correct account."
        case .queueNotConfirmed:
            "The server has not confirmed durable queue admission. The saved source remains available."
        case .responseMismatch:
            "The server response did not match this saved source. The local receipt was kept."
        case .localSourceChanged:
            "The saved source was removed while it was processing. No recipe was added."
        case .completedResultMissing:
            "The server finished processing without a recipe result. The original source remains saved."
        case .unsupportedCompletedInput:
            "This source type is not supported for recipe saving yet. The original source remains saved."
        }
    }
}

@MainActor
public enum RecipeShareImportWorkflow {
    public static func synchronize(
        inbox: RecipeShareInbox,
        store: RecipeStore,
        client: any RecipeImportJobClient,
        ownerID: UUID,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        maxPollRounds: Int = 12,
        pollInterval: Duration = .seconds(5)
    ) async -> RecipeShareImportReport {
        var jobStatuses: [UUID: RecipeImportJobResponse] = [:]
        var firstFailure: String?
        var retryRequests = Set<UUID>()

        do {
            for _ in 0..<max(1, maxPollRounds) {
                guard currentOwnerID() == ownerID else { break }

                var hasActiveJobs = false
                var pending = try inbox.pendingReceipts(for: ownerID)

                for receipt in pending {
                    guard currentOwnerID() == ownerID else { break }

                    do {
                        guard try inbox.receivedJobID(
                            for: receipt,
                            ownerID: ownerID
                        ) == nil else {
                            continue
                        }

                        let source = try inbox.source(for: receipt)
                        let response = try await client.submit(
                            receipt: receipt,
                            source: source,
                            ownerID: ownerID
                        )
                        try validate(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            currentOwnerID: currentOwnerID
                        )
                        try persistServerState(
                            response,
                            for: receipt,
                            source: source,
                            ownerID: ownerID,
                            inbox: inbox
                        )
                        jobStatuses[receipt.id] = response
                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = true
                    }
                }

                pending = try inbox.pendingReceipts(for: ownerID)
                for receipt in pending {
                    guard currentOwnerID() == ownerID else { break }
                    guard let jobID = try inbox.receivedJobID(
                        for: receipt,
                        ownerID: ownerID
                    ) else {
                        continue
                    }

                    do {
                        let source = try inbox.source(for: receipt)
                        let response = try await client.fetch(
                            jobID: jobID,
                            ownerID: ownerID
                        )
                        try validate(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            expectedJobID: jobID,
                            currentOwnerID: currentOwnerID
                        )
                        try persistServerState(
                            response,
                            for: receipt,
                            source: source,
                            ownerID: ownerID,
                            inbox: inbox
                        )
                        jobStatuses[receipt.id] = response
                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = true
                    }
                }

                for receipt in try inbox.acknowledgedReceipts(for: ownerID) {
                    guard currentOwnerID() == ownerID else { break }
                    guard let jobID = try inbox.acknowledgedJobID(
                        for: receipt,
                        ownerID: ownerID
                    ) else {
                        continue
                    }

                    var fetchedTerminalStatus = false
                    do {
                        let source = try inbox.source(for: receipt)
                        var response = try await client.fetch(
                            jobID: jobID,
                            ownerID: ownerID
                        )
                        try validate(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            expectedJobID: jobID,
                            currentOwnerID: currentOwnerID
                        )
                        fetchedTerminalStatus = !response.isActive

                        if response.status == .failed,
                           response.error?.recoverable == true,
                           retryRequests.insert(jobID).inserted {
                            response = try await client.retry(
                                jobID: jobID,
                                ownerID: ownerID
                            )
                            try validate(
                                response,
                                for: receipt,
                                ownerID: ownerID,
                                expectedJobID: jobID,
                                currentOwnerID: currentOwnerID
                            )
                            fetchedTerminalStatus = !response.isActive
                            guard response.isDurablyQueued else {
                                throw RecipeShareImportWorkflowError.queueNotConfirmed
                            }
                        }

                        jobStatuses[receipt.id] = response
                        guard try inbox.source(for: receipt) == source else {
                            throw RecipeShareImportWorkflowError.localSourceChanged
                        }
                        if response.status == .completed {
                            try saveCompletedTextResult(
                                response,
                                receipt: receipt,
                                source: source,
                                store: store
                            )
                        } else if response.status == .failed {
                            let serverMessage = response.error?.message
                                ?? "The import could not be completed."
                            firstFailure = firstFailure
                                ?? "A shared source failed: \(serverMessage)"
                        }

                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = hasActiveJobs || !fetchedTerminalStatus
                    }
                }

                if !hasActiveJobs {
                    break
                }
                if pollInterval > .zero {
                    try await Task.sleep(for: pollInterval)
                }
            }
        } catch {
            firstFailure = firstFailure ?? error.localizedDescription
        }

        return RecipeShareImportReport(
            jobStatuses: jobStatuses,
            failureMessage: firstFailure
        )
    }

    private static func persistServerState(
        _ response: RecipeImportJobResponse,
        for receipt: RecipeShareReceipt,
        source: String,
        ownerID: UUID,
        inbox: RecipeShareInbox
    ) throws {
        if response.status == .received {
            guard try inbox.source(for: receipt) == source else {
                throw RecipeShareImportWorkflowError.localSourceChanged
            }
            try inbox.recordReceivedJob(
                response.jobID,
                for: receipt,
                ownerID: ownerID
            )
            return
        }

        guard response.isDurablyQueued else {
            throw RecipeShareImportWorkflowError.queueNotConfirmed
        }
        guard try inbox.source(for: receipt) == source else {
            throw RecipeShareImportWorkflowError.localSourceChanged
        }
        guard let queueConfirmedAt = response.queueConfirmedAt else {
            throw RecipeShareImportWorkflowError.queueNotConfirmed
        }
        try inbox.acknowledge(
            receipt,
            jobID: response.jobID,
            ownerID: ownerID,
            queueConfirmedAt: queueConfirmedAt
        )
    }

    private static func validate(
        _ response: RecipeImportJobResponse,
        for receipt: RecipeShareReceipt,
        ownerID: UUID,
        expectedJobID: UUID? = nil,
        currentOwnerID: @MainActor () -> UUID?
    ) throws {
        guard currentOwnerID() == ownerID,
              response.clientRequestID == receipt.clientRequestID,
              expectedJobID == nil || response.jobID == expectedJobID else {
            if currentOwnerID() != ownerID {
                throw RecipeShareImportWorkflowError.accountChanged
            }
            throw RecipeShareImportWorkflowError.responseMismatch
        }
        if response.status != .received && !response.isDurablyQueued {
            throw RecipeShareImportWorkflowError.queueNotConfirmed
        }
    }

    private static func saveCompletedTextResult(
        _ response: RecipeImportJobResponse,
        receipt: RecipeShareReceipt,
        source: String,
        store: RecipeStore
    ) throws {
        guard receipt.inputType == .text else {
            throw RecipeShareImportWorkflowError.unsupportedCompletedInput
        }
        guard let result = response.result else {
            throw RecipeShareImportWorkflowError.completedResultMissing
        }
        guard result.source.inputType == "text",
              response.recipeID == nil || response.recipeID == result.recipeID,
              response.existingRecipeID == nil
                || response.existingRecipeID == result.recipeID else {
            throw RecipeShareImportWorkflowError.responseMismatch
        }

        // A replay must never replace a locally edited recipe. The server ID
        // is stable across job retries; exact source text catches cross-job duplicates.
        guard store.recipe(id: result.recipeID) == nil,
              !store.recipes.contains(where: { $0.sourceText == source }) else {
            return
        }

        var title = "Imported recipe"
        if let rawTitle = result.fields["title"]?.rawValue {
            let trimmedTitle = rawTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmedTitle.isEmpty {
                title = trimmedTitle
            }
        }
        var recipe = RecipeDocumentParser.recipe(
            fromText: source,
            title: title
        )
        recipe.id = result.recipeID
        recipe.sourceText = source
        recipe.sourceURL = result.source.originalURL
            ?? result.source.canonicalURL
        recipe.sourceName = result.source.sourceTitle
            ?? result.source.authorName
            ?? result.source.platform
            ?? "Shared text"
        try store.upsert(recipe)
    }
}
