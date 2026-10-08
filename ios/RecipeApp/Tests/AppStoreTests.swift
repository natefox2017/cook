// Developer: gengyun
// Purpose: Tests persistence and basic behavior in the legacy RecipeApp prototype.

import XCTest

@testable import Recipe

final class AppStoreTests: XCTestCase {
    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
    }

    func testImportRejectsNonHTTP() {
        let store = AppStore(fileURL: temporaryStateURL())

        XCTAssertNil(store.importURL("file:///etc/passwd"))
        XCTAssertNotNil(store.lastError)
    }

    func testDuplicateURLIsIdempotent() {
        let store = AppStore(fileURL: temporaryStateURL())

        let first = store.importURL("https://example.com/r")!
        let second = store.importURL("https://example.com/r")!

        XCTAssertEqual(first.id, second.id)
    }

    func testFavoritePersists() {
        let url = temporaryStateURL()
        let store = AppStore(fileURL: url)
        let id = store.recipes[0].id

        store.toggleFavorite(id)
        let expected = store.recipes[0].isFavorite

        let reloaded = AppStore(fileURL: url)
        XCTAssertEqual(
            reloaded.recipes.first(where: { $0.id == id })?.isFavorite,
            expected
        )
    }

    func testGroceriesDoNotDuplicateSameRecipe() {
        let store = AppStore(fileURL: temporaryStateURL())
        let recipe = store.recipes[0]

        store.addGroceries(
            from: recipe,
            servings: recipe.servings
        )
        let count = store.groceries.count

        store.addGroceries(
            from: recipe,
            servings: recipe.servings
        )

        XCTAssertEqual(store.groceries.count, count)
    }
}
