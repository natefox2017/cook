// Developer: gengyun
// Purpose: Verifies collection indexing, deduplication, and membership lookups.

import Foundation
import Testing

@testable import RecipeCore

@Test
func membershipsAreIndexedByCollectionAndRecipe() {
    let firstRecipe = UUID()
    let secondRecipe = UUID()
    let firstCollection = UUID()
    let secondCollection = UUID()

    let index = RecipeCollectionIndex(memberships: [
        RecipeCollectionMembership(recipeID: firstRecipe, collectionID: firstCollection),
        RecipeCollectionMembership(recipeID: firstRecipe, collectionID: secondCollection),
        RecipeCollectionMembership(recipeID: secondRecipe, collectionID: firstCollection),
        RecipeCollectionMembership(recipeID: firstRecipe, collectionID: firstCollection),
    ])

    // Duplicate input must not inflate collection counts.
    #expect(index.count(inCollection: firstCollection) == 2)
    #expect(index.count(inCollection: secondCollection) == 1)
    #expect(index.recipeIDs(inCollection: firstCollection) == Set([firstRecipe, secondRecipe]))
    #expect(
        index.collectionIDs(forRecipe: firstRecipe) == Set([firstCollection, secondCollection]))
    #expect(index.contains(recipeID: firstRecipe, inCollection: secondCollection))
    #expect(!index.contains(recipeID: secondRecipe, inCollection: secondCollection))
}

@Test
func unknownMembershipsReturnEmptyResults() {
    let index = RecipeCollectionIndex(memberships: [])
    let recipeID = UUID()
    let collectionID = UUID()

    #expect(index.count(inCollection: collectionID) == 0)
    #expect(index.recipeIDs(inCollection: collectionID).isEmpty)
    #expect(index.collectionIDs(forRecipe: recipeID).isEmpty)
    #expect(!index.contains(recipeID: recipeID, inCollection: collectionID))
}
