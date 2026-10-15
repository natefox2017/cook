// Developer: gengyun
// Purpose: Tests the real per-owner pending draft commit persistence under the recipe.* namespace.

import Foundation
import Testing
@testable import RecipeCore

@Suite struct RecipeDraftPersistenceTests {
    private func makeStore() -> (RecipeDraftPendingCommitStore, UserDefaults) {
        let suite = "RecipeDraftPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (RecipeDraftPendingCommitStore(defaults: defaults), defaults)
    }

    private func commit(ownerID: String = UUID().uuidString.lowercased()) throws
        -> RecipeDraftPendingCommit
    {
        try RecipeDraftPendingCommit(
            ownerID: ownerID,
            sessionID: UUID().uuidString.lowercased(),
            turnRequestID: UUID().uuidString.lowercased(),
            requestID: UUID().uuidString.lowercased(),
            operationID: UUID().uuidString.lowercased(),
            selectedPaths: ["title", "ingredients[0].name"]
        )
    }

    @Test func saveAndLoadRoundTrip() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: "RecipeDraftPersistenceTests") }

        let pending = try commit()
        try store.save(pending)

        #expect(store.load(ownerID: pending.ownerID) == pending)
        #expect(store.ownerIDs() == [pending.ownerID])
    }

    @Test func perOwnerIsolation() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: "RecipeDraftPersistenceTests") }

        let first = try commit()
        let second = try commit()
        try store.save(first)
        try store.save(second)

        #expect(store.load(ownerID: first.ownerID) == first)
        #expect(store.load(ownerID: second.ownerID) == second)
        #expect(Set(store.ownerIDs()) == Set([first.ownerID, second.ownerID]))
    }

    @Test func clearRemovesOnlyTargetedOwner() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: "RecipeDraftPersistenceTests") }

        let first = try commit()
        let second = try commit()
        try store.save(first)
        try store.save(second)

        store.clear(ownerID: first.ownerID)

        #expect(store.load(ownerID: first.ownerID) == nil)
        #expect(store.load(ownerID: second.ownerID) == second)
        #expect(store.ownerIDs() == [second.ownerID])
    }

    @Test func loadRejectsMismatchedOwnerPayload() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: "RecipeDraftPersistenceTests") }

        let pending = try commit()
        try store.save(pending)
        let otherOwner = UUID().uuidString.lowercased()

        #expect(store.load(ownerID: otherOwner) == nil)
    }

    @Test func finalizedCommitRequiresRecipeAndHash() throws {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: "RecipeDraftPersistenceTests") }

        let finalized = try RecipeDraftPendingCommit(
            ownerID: UUID().uuidString.lowercased(),
            sessionID: UUID().uuidString.lowercased(),
            turnRequestID: UUID().uuidString.lowercased(),
            requestID: UUID().uuidString.lowercased(),
            operationID: UUID().uuidString.lowercased(),
            selectedPaths: ["steps[0].instruction"],
            status: .finalized,
            recipeID: UUID().uuidString.lowercased(),
            payloadHash: String(repeating: "a", count: 64)
        )
        try store.save(finalized)
        #expect(store.load(ownerID: finalized.ownerID) == finalized)

        #expect(throws: RecipeDraftPersistenceError.invalidCommit) {
            try RecipeDraftPendingCommit(
                ownerID: UUID().uuidString.lowercased(),
                sessionID: UUID().uuidString.lowercased(),
                turnRequestID: UUID().uuidString.lowercased(),
                requestID: UUID().uuidString.lowercased(),
                operationID: UUID().uuidString.lowercased(),
                selectedPaths: ["title"],
                status: .finalized,
                recipeID: nil,
                payloadHash: nil
            )
        }
    }

    @Test func emptySelectedPathsRejected() throws {
        #expect(throws: RecipeDraftPersistenceError.invalidCommit) {
            try RecipeDraftPendingCommit(
                ownerID: UUID().uuidString.lowercased(),
                sessionID: UUID().uuidString.lowercased(),
                turnRequestID: UUID().uuidString.lowercased(),
                requestID: UUID().uuidString.lowercased(),
                operationID: UUID().uuidString.lowercased(),
                selectedPaths: []
            )
        }
    }
}
