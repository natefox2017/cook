// Developer: gengyun
// Purpose: Verifies collection indexing, deduplication, and membership lookups.

import XCTest
@testable import RecipeCore

final class RecipeCollectionIndexTests: XCTestCase {
    func testMembershipsAreIndexedByCollectionAndRecipe() {
        let firstRecipe = UUID()
        let secondRecipe = UUID()
        let firstCollection = UUID()
        let secondCollection = UUID()

        let index = RecipeCollectionIndex(memberships: [
            RecipeCollectionMembership(recipeID: firstRecipe, collectionID: firstCollection),
            RecipeCollectionMembership(recipeID: firstRecipe, collectionID: secondCollection),
            RecipeCollectionMembership(recipeID: secondRecipe, collectionID: firstCollection),
            RecipeCollectionMembership(recipeID: firstRecipe, collectionID: firstCollection)
        ])

        // Duplicate input must not inflate collection counts.
        XCTAssertEqual(index.count(inCollection: firstCollection), 2)
        XCTAssertEqual(index.count(inCollection: secondCollection), 1)
        XCTAssertEqual(
            index.recipeIDs(inCollection: firstCollection),
            Set([firstRecipe, secondRecipe])
        )
        XCTAssertEqual(
            index.collectionIDs(forRecipe: firstRecipe),
            Set([firstCollection, secondCollection])
        )
        XCTAssertTrue(index.contains(recipeID: firstRecipe, inCollection: secondCollection))
        XCTAssertFalse(index.contains(recipeID: secondRecipe, inCollection: secondCollection))
    }

    func testEmptyAndUnknownMembershipsReturnEmptyResults() {
        let index = RecipeCollectionIndex(memberships: [])
        let recipeID = UUID()
        let collectionID = UUID()

        XCTAssertEqual(index.count(inCollection: collectionID), 0)
        XCTAssertTrue(index.recipeIDs(inCollection: collectionID).isEmpty)
        XCTAssertTrue(index.collectionIDs(forRecipe: recipeID).isEmpty)
        XCTAssertFalse(index.contains(recipeID: recipeID, inCollection: collectionID))
    }
}
