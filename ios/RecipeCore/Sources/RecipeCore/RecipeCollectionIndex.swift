// Developer: gengyun
// Purpose: Indexes collection memberships once for efficient library and picker rendering.

import Foundation

/// Immutable snapshot of collection membership for a single UI render.
/// Keeping the index ephemeral avoids stale caches when RecipeStore publishes changes.
public struct RecipeCollectionIndex: Sendable {
    private let recipeIDsByCollection: [UUID: Set<UUID>]
    private let collectionIDsByRecipe: [UUID: Set<UUID>]

    public init(memberships: [RecipeCollectionMembership]) {
        var recipes: [UUID: Set<UUID>] = [:]
        var collections: [UUID: Set<UUID>] = [:]

        for membership in memberships {
            recipes[membership.collectionID, default: []].insert(membership.recipeID)
            collections[membership.recipeID, default: []].insert(membership.collectionID)
        }

        recipeIDsByCollection = recipes
        collectionIDsByRecipe = collections
    }

    public func recipeIDs(inCollection id: UUID) -> Set<UUID> {
        recipeIDsByCollection[id] ?? []
    }

    public func collectionIDs(forRecipe id: UUID) -> Set<UUID> {
        collectionIDsByRecipe[id] ?? []
    }

    public func count(inCollection id: UUID) -> Int {
        recipeIDsByCollection[id]?.count ?? 0
    }

    public func contains(recipeID: UUID, inCollection collectionID: UUID) -> Bool {
        recipeIDsByCollection[collectionID]?.contains(recipeID) ?? false
    }
}
