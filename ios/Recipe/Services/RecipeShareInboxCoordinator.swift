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

    /// Submit local sources, recover owner-scoped jobs, and store completed text results.
    func synchronize(store: RecipeStore) async {
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
            let report = await RecipeShareImportWorkflow.synchronize(
                inbox: inbox,
                store: store,
                client: RecipeImportJobService(),
                ownerID: ownerID,
                currentOwnerID: { self.currentOwnerID }
            )
            jobStatuses = report.jobStatuses
            refresh()
            failureMessage = report.failureMessage
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
