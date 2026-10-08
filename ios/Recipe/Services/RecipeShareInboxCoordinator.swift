// Developer: gengyun
// Purpose: Submits durable share receipts and recovers owner-scoped server job state.

import Foundation
import Observation
import RecipeCore

@Observable @MainActor
final class RecipeShareInboxCoordinator {
    private(set) var pendingReceipts: [RecipeShareReceipt] = []
    private(set) var jobStatuses: [UUID: RecipeImportJobResponse] = [:]
    private(set) var failureMessage: String?
    private var statusOwnerID: UUID?
    private var isSynchronizing = false

    func refresh() {
        do {
            let inbox = try RecipeShareInbox.shared()
            try migrateLegacyInbox(into: inbox)
            let ownerID = currentOwnerID
            if statusOwnerID != ownerID {
                jobStatuses = [:]
                statusOwnerID = ownerID
            }
            pendingReceipts = try inbox.pendingReceipts(for: ownerID)
            failureMessage = nil
        } catch {
            // Never clear the UI or underlying records when an App Group read
            // fails. They remain available for a later retry.
            failureMessage = error.localizedDescription
        }
    }

    /// Submit locally saved sources, poll accepted jobs, and retry only jobs
    /// the API explicitly marks recoverable. Relaunches resume from owner ACKs.
    func synchronize() async {
        guard !isSynchronizing else { return }
        guard let ownerID = currentOwnerID else {
            refresh()
            return
        }

        isSynchronizing = true
        defer { isSynchronizing = false }
        refresh()

        do {
            let inbox = try RecipeShareInbox.shared()
            var firstFailure: String?
            var retryRequests = Set<UUID>()

            for _ in 0..<12 {
                guard currentOwnerID == ownerID else { break }
                var hasActiveJobs = false
                var pending = try inbox.pendingReceipts(for: ownerID)

                for receipt in pending {
                    do {
                        guard try inbox.receivedJobID(
                            for: receipt,
                            ownerID: ownerID
                        ) == nil else {
                            continue
                        }
                        let source = try inbox.source(for: receipt)
                        let response = try await RecipeImportJobService.submit(
                            receipt: receipt,
                            source: source,
                            ownerID: ownerID
                        )
                        try persistServerState(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            inbox: inbox
                        )
                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = true
                    }
                }

                pending = try inbox.pendingReceipts(for: ownerID)
                for receipt in pending {
                    guard let jobID = try inbox.receivedJobID(
                        for: receipt,
                        ownerID: ownerID
                    ) else {
                        continue
                    }
                    do {
                        let response = try await RecipeImportJobService.fetch(
                            jobID: jobID,
                            ownerID: ownerID
                        )
                        try validate(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            expectedJobID: jobID
                        )
                        try persistServerState(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            inbox: inbox
                        )
                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = true
                    }
                }

                for receipt in try inbox.acknowledgedReceipts(for: ownerID) {
                    guard let jobID = try inbox.acknowledgedJobID(
                        for: receipt,
                        ownerID: ownerID
                    ) else {
                        continue
                    }
                    do {
                        var response = try await RecipeImportJobService.fetch(
                            jobID: jobID,
                            ownerID: ownerID
                        )
                        try validate(
                            response,
                            for: receipt,
                            ownerID: ownerID,
                            expectedJobID: jobID
                        )

                        if response.status == .failed,
                           response.error?.recoverable == true,
                           retryRequests.insert(jobID).inserted {
                            response = try await RecipeImportJobService.retry(
                                jobID: jobID,
                                ownerID: ownerID
                            )
                            try validate(
                                response,
                                for: receipt,
                                ownerID: ownerID,
                                expectedJobID: jobID
                            )
                            guard response.isDurablyQueued else {
                                throw RecipeImportJobService.ServiceError.queueNotConfirmed
                            }
                        }

                        jobStatuses[receipt.id] = response
                        hasActiveJobs = hasActiveJobs || response.isActive
                    } catch {
                        firstFailure = firstFailure ?? error.localizedDescription
                        hasActiveJobs = true
                    }
                }

                refresh()
                if !hasActiveJobs { break }
                try await Task.sleep(for: .seconds(5))
            }

            failureMessage = firstFailure
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    func source(for receipt: RecipeShareReceipt) -> String? {
        do {
            return try RecipeShareInbox.shared().source(for: receipt)
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    private var currentOwnerID: UUID? {
        guard case .signedIn(let ownerID, _) = RecipeAuthService.shared.state else {
            return nil
        }
        return ownerID
    }

    private func persistServerState(
        _ response: RecipeImportJobResponse,
        for receipt: RecipeShareReceipt,
        ownerID: UUID,
        inbox: RecipeShareInbox
    ) throws {
        try validate(response, for: receipt, ownerID: ownerID)
        if response.isDurablyQueued {
            guard let queueConfirmedAt = response.queueConfirmedAt else {
                throw RecipeImportJobService.ServiceError.queueNotConfirmed
            }
            try inbox.acknowledge(
                receipt,
                jobID: response.jobID,
                ownerID: ownerID,
                queueConfirmedAt: queueConfirmedAt
            )
        } else if response.status == .received {
            try inbox.recordReceivedJob(
                response.jobID,
                for: receipt,
                ownerID: ownerID
            )
        } else {
            throw RecipeImportJobService.ServiceError.queueNotConfirmed
        }
        jobStatuses[receipt.id] = response
    }

    private func validate(
        _ response: RecipeImportJobResponse,
        for receipt: RecipeShareReceipt,
        ownerID: UUID,
        expectedJobID: UUID? = nil
    ) throws {
        guard currentOwnerID == ownerID,
              response.clientRequestID == receipt.clientRequestID,
              expectedJobID == nil || response.jobID == expectedJobID else {
            if currentOwnerID != ownerID {
                throw RecipeImportJobService.ServiceError.accountChanged
            }
            throw RecipeImportJobService.ServiceError.responseMismatch
        }
        if response.status != .received && !response.isDurablyQueued {
            throw RecipeImportJobService.ServiceError.queueNotConfirmed
        }
    }

    /// The previous release wrote a read-modify-write UserDefaults array.
    /// Migrate every legacy value first and erase both keys only when all
    /// records have been durably persisted in the file-backed inbox.
    private func migrateLegacyInbox(into inbox: RecipeShareInbox) throws {
        guard let defaults = UserDefaults(
            suiteName: RecipeShareInbox.appGroupID
        ) else {
            return
        }

        let keys = ["recipe.shareInbox", "cook.shareInbox"]
        let oldSources = keys.flatMap {
            defaults.stringArray(forKey: $0) ?? []
        }

        for source in Set(oldSources) {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let kind: RecipeShareInputType
            if let components = URLComponents(string: trimmed),
               components.scheme?.lowercased() == "https",
               components.host != nil {
                kind = .url
            } else {
                kind = .text
            }
            try inbox.receive(trimmed, as: kind)
        }

        if !oldSources.isEmpty {
            for key in keys {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private extension RecipeImportJobResponse {
    var isActive: Bool {
        switch status {
        case .received, .queued, .extracting, .parsing, .validating:
            true
        case .completed, .failed:
            false
        }
    }
}
