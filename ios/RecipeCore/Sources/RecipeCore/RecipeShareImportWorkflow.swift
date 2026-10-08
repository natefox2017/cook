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
                try Task.checkCancellation()
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
                        // A cancelled import is not a failed recipe source.
                        if error is CancellationError { throw error }
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
                        // A cancelled import is not a failed recipe source.
                        if error is CancellationError { throw error }
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
                            try saveCompletedResult(
                                response,
                                receipt: receipt,
                                source: source,
                                store: store
                            )
                        } else if response.status == .failed {
                            let serverMessage = response.error?.message
                                ?? "The import could not be completed."
                            let suggestedAction = nonempty(
                                response.error?.suggestedAction
                            )
                            let detail = [serverMessage, suggestedAction]
                                .compactMap { $0 }
                                .joined(separator: " ")
                            firstFailure = firstFailure
                                ?? "A shared source failed: \(detail)"
                        }

                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        if error is CancellationError { throw error }
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
        } catch is CancellationError {
            // Dismissing or replacing a view must not surface a false failure.
            // Durable receipts remain available for the next synchronization.
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

    private static func saveCompletedResult(
        _ response: RecipeImportJobResponse,
        receipt: RecipeShareReceipt,
        source: String,
        store: RecipeStore
    ) throws {
        guard let result = response.result else {
            throw RecipeShareImportWorkflowError.completedResultMissing
        }
        guard result.source.inputType == receipt.inputType.rawValue,
              let resultStatus = result.resultStatus,
              response.recipeID == nil || response.recipeID == result.recipeID,
              response.recipeStatus == nil
                || response.recipeStatus == resultStatus.rawValue,
              response.existingRecipeID == nil
                || response.existingRecipeID == result.recipeID else {
            throw RecipeShareImportWorkflowError.responseMismatch
        }

        // Server IDs and normalized source URLs prevent retries from replacing
        // locally edited recipes or creating duplicate imports.
        guard store.recipe(id: result.recipeID) == nil,
              !isDuplicate(
                result: result,
                source: source,
                receipt: receipt,
                recipes: store.recipes
              ) else {
            return
        }

        let title = nonempty(result.fields["title"]?.rawValue)
            ?? "Imported recipe"
        var structuredText = title
        let rawIngredients = indexedValues(
            result.fields,
            pattern: #"^ingredients\[(\d+)\]\.raw_text$"#
        )
        let ingredients = rawIngredients.isEmpty
            ? indexedValues(
                result.fields,
                pattern: #"^ingredients\[(\d+)\]\.amount$"#
            )
            : rawIngredients
        let steps = indexedValues(
            result.fields,
            pattern: #"^steps\[(\d+)\]\.instruction$"#
        )
        if !ingredients.isEmpty {
            structuredText += "\n\nIngredients\n" + ingredients.joined(separator: "\n")
        }
        if !steps.isEmpty {
            structuredText += "\n\nInstructions\n" + steps.joined(separator: "\n")
        }
        var recipe = RecipeDocumentParser.recipe(
            fromText: structuredText,
            title: title
        )
        recipe.id = result.recipeID
        recipe.servings = nil
        recipe.sourceText = receipt.inputType == .text ? source : nil
        let sharedURL = receipt.inputType == .url
            ? validatedURL(source)?.absoluteString
            : nil
        recipe.sourceURL = sharedURL
            ?? validatedURL(result.source.originalURL)?.absoluteString
            ?? validatedURL(result.source.canonicalURL)?.absoluteString
        recipe.sourceName = nonempty(result.source.sourceTitle)
            ?? nonempty(result.source.authorName)
            ?? nonempty(result.source.platform)
            ?? defaultSourceName(for: receipt.inputType)
        recipe.importRecord = RecipeImportRecord(
            jobID: response.jobID,
            result: result
        )
        try store.upsert(recipe)
    }

    private static func indexedValues(
        _ fields: [String: RecipeImportJobResponse.Field],
        pattern: String
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return fields.compactMap { entry -> (Int, String)? in
            let (key, field) = entry
            let range = NSRange(key.startIndex..., in: key)
            guard let match = expression.firstMatch(in: key, range: range),
                  let indexRange = Range(match.range(at: 1), in: key),
                  let index = Int(key[indexRange]),
                  let value = nonempty(field.rawValue) else {
                return nil
            }
            return (index, value)
        }
        .sorted { $0.0 < $1.0 }
        .map { $0.1 }
    }

    private static func defaultSourceName(
        for inputType: RecipeShareInputType
    ) -> String {
        switch inputType {
        case .url:
            "Recipe website"
        case .text:
            "Shared text"
        case .image:
            "Shared image"
        case .file:
            "Shared document"
        }
    }

    private static func isDuplicate(
        result: RecipeImportJobResponse.Result,
        source: String,
        receipt: RecipeShareReceipt,
        recipes: [Recipe]
    ) -> Bool {
        if receipt.inputType == .text,
           recipes.contains(where: { $0.sourceText == source }) {
            return true
        }

        var importedURLs = [result.source.originalURL, result.source.canonicalURL]
            .compactMap(validatedURL)
        if receipt.inputType == .url, let sourceURL = validatedURL(source) {
            importedURLs.append(sourceURL)
        }
        let importedKeys = Set(importedURLs.map {
            RecipeDocumentParser.sourceKey($0)
        })
        guard !importedKeys.isEmpty else { return false }
        return recipes.contains { recipe in
            guard let sourceURL = recipe.sourceURL,
                  let existingURL = validatedURL(sourceURL) else {
                return false
            }
            return importedKeys.contains(RecipeDocumentParser.sourceKey(existingURL))
        }
    }

    private static func validatedURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return RecipeDocumentParser.validatedSourceURL(value)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
