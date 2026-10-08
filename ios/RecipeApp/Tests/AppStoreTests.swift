import XCTest
@testable import Recipe
final class AppStoreTests:XCTestCase{
 func temp()->URL{FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")}
 func testImportRejectsNonHTTP(){let s=AppStore(fileURL:temp());XCTAssertNil(s.importURL("file:///etc/passwd"));XCTAssertNotNil(s.lastError)}
 func testDuplicateURLIsIdempotent(){let s=AppStore(fileURL:temp());let a=s.importURL("https://example.com/r")!;let b=s.importURL("https://example.com/r")!;XCTAssertEqual(a.id,b.id)}
 func testFavoritePersists(){let u=temp();let s=AppStore(fileURL:u);let id=s.recipes[0].id;s.toggleFavorite(id);let expected=s.recipes[0].isFavorite;let reloaded=AppStore(fileURL:u);XCTAssertEqual(reloaded.recipes.first(where:{$0.id==id})?.isFavorite,expected)}
 func testGroceriesDoNotDuplicateSameRecipe(){let s=AppStore(fileURL:temp());let r=s.recipes[0];s.addGroceries(from:r,servings:r.servings);let count=s.groceries.count;s.addGroceries(from:r,servings:r.servings);XCTAssertEqual(s.groceries.count,count)}
}
