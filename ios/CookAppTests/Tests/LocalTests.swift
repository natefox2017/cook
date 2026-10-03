import Foundation
import Testing
@testable import CookLocal

@Test func uncertainAmountsStayUncertain() {
    for amount in ["to taste", "a pinch", "1/2", "unknown"] {
        #expect(IngredientRecord(name: "Salt", amount: amount).displayedAmount(for: 8, originalServings: 2) == amount)
    }
    #expect(IngredientRecord(name: "Flour", amount: "100", unit: "g").displayedAmount(for: 4, originalServings: 2) == "200 g")
    #expect(IngredientRecord(name: "Flour", amount: "100", unit: "g").displayedAmount(for: 4, originalServings: nil) == "100 g")
}

@Test @MainActor func persistsSourcesAndCombinesOnlyEqualUnits() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = CookStore(directory: dir)
    let source = URL(string: "https://example.com/recipe?original=1")!
    let recipe = RecipeRecord(title: "Bread", ingredients: [
        IngredientRecord(name: "Flour", amount: "100", unit: "g"),
        IngredientRecord(name: "Flour", amount: "1", unit: "cup"),
        IngredientRecord(name: "Salt", amount: "to taste")], sourceURL: source, sourceAuthor: "Original author")
    try store.save(recipe)
    try store.addGroceries(from: recipe, servings: 4)
    try store.addGroceries(from: recipe, servings: 2)
    #expect(store.snapshot.groceries.count == 4)
    #expect(store.snapshot.groceries.first?.amount == "300")
    #expect(store.snapshot.groceries.first?.sourceRecipeIDs == [recipe.id])
    let first = try store.captureURL(source.absoluteString)
    #expect(try store.captureURL(source.absoluteString).id == first.id)
    let restored = CookStore(directory: dir)
    #expect(restored.snapshot == store.snapshot)
    #expect(restored.snapshot.recipes.first?.sourceURL == source)
}

@Test @MainActor func corruptDataCannotBeOverwritten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("collection.json")
    let original = Data("broken collection".utf8)
    try original.write(to: file)
    let store = CookStore(directory: dir)
    #expect(!store.loaded)
    #expect(throws: (any Error).self) { try store.save(RecipeRecord(title: "New")) }
    #expect(try Data(contentsOf: file) == original)
}

@Test func timerCatchesUpAndPausePreservesRemaining() {
    let start = Date(timeIntervalSince1970: 100)
    var timer = CookingTimer(seconds: 60)
    timer.start(at: start)
    timer.pause(at: start.addingTimeInterval(10))
    #expect(timer.remaining(at: start.addingTimeInterval(100)) == 50)
    timer.start(at: start.addingTimeInterval(100))
    timer.tick(at: start.addingTimeInterval(200))
    #expect(timer.finished)
    #expect(timer.remaining(at: start.addingTimeInterval(200)) == 0)
    timer.reset()
    #expect(timer.pausedRemaining == 60)
}

@Test @MainActor func futureVersionAndFailedWritesPreserveState() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("collection.json")
    var future = LocalSnapshot()
    future.version = 2
    let original = try JSONEncoder().encode(future)
    try original.write(to: file)
    let blocked = CookStore(directory: dir)
    #expect(!blocked.loaded)
    #expect(throws: (any Error).self) { try blocked.captureText("Recipe") }
    #expect(try Data(contentsOf: file) == original)
    try FileManager.default.removeItem(at: file)
    let writable = CookStore(directory: dir)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    #expect(throws: (any Error).self) { try writable.save(RecipeRecord(title: "Unsaved")) }
    #expect(writable.snapshot.recipes.isEmpty)
    #expect(throws: (any Error).self) { try writable.captureAttachment(Data([1,2,3]), kind: .file, extension: "pdf") }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["collection.json"])
}
