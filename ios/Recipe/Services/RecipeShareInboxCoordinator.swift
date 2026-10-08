// Developer: gengyun
// Purpose: Reads durable shared receipts without falsely reporting cloud ingestion.

import Foundation
import Observation
import RecipeCore

@Observable @MainActor
final class RecipeShareInboxCoordinator {
    private(set) var pendingReceipts: [RecipeShareReceipt] = []
    private(set) var failureMessage: String?

    func refresh() {
        do {
            let inbox = try RecipeShareInbox.shared()
            try migrateLegacyInbox(into: inbox)
            pendingReceipts = try inbox.pendingReceipts()
            failureMessage = nil
        } catch {
            // Never clear the UI or underlying records when an App Group read
            // fails. They remain available for a later retry.
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
