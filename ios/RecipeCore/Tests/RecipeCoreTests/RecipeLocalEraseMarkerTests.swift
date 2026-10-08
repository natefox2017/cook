// Developer: gengyun
// Purpose: Exercise durable local-erase recovery markers and write failure safety.

import Foundation
import Testing
@testable import RecipeCore

private func eraseTestRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecipeLocalErase-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func markerPersistsAcrossRestartAndIndependentCacheCleanup() throws {
    let root = try eraseTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let recipeDir = root.appendingPathComponent("Recipe", isDirectory: true)
    let marker = recipeDir.appendingPathComponent(".localErasePending")
    let syncDir = recipeDir.appendingPathComponent("Sync", isDirectory: true)
    try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
    try Data("old cloud base".utf8)
        .write(to: syncDir.appendingPathComponent("old-account.json"))

    try RecipeLocalEraseMarker.persist(at: marker)
    #expect(RecipeLocalEraseMarker.isPresent(at: marker))
    // A second caller after process restart sees the persisted file on disk.
    #expect(FileManager.default.fileExists(atPath: marker.path))

    // Cleaning Sync caches must not remove the crash-recovery marker.
    try FileManager.default.removeItem(at: syncDir)
    #expect(RecipeLocalEraseMarker.isPresent(at: marker))
    try RecipeLocalEraseMarker.clear(at: marker)
    #expect(!RecipeLocalEraseMarker.isPresent(at: marker))
}

@Test @MainActor
func markerWriteFailureAbortsBeforeTheLocalLibraryChanges() throws {
    let root = try eraseTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let libraryURL = root.appendingPathComponent("Recipe/library.json")
    let store = RecipeStore(fileURL: libraryURL)
    let recipe = Recipe(title: "Do not delete", steps: [.init(instruction: "Keep.")])
    try store.upsert(recipe)
    let original = try Data(contentsOf: libraryURL)

    // A file occupying the parent path guarantees that marker creation
    // fails independently of filesystem permission policies or root users.
    let blockedParent = root.appendingPathComponent("blocked")
    try Data("not a directory".utf8).write(to: blockedParent)
    #expect(throws: (any Error).self) {
        try RecipeLocalEraseMarker.persist(
            at: blockedParent.appendingPathComponent(".localErasePending")
        )
        try store.clearLocalLibraryOnly()
    }
    #expect(store.recipe(id: recipe.id) != nil)
    #expect(try Data(contentsOf: libraryURL) == original)
}

@Test @MainActor
func interruptedEmptyLibraryRetainsMarkerUntilConfirmedCloudRecovery() throws {
    let root = try eraseTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let recipeDir = root.appendingPathComponent("Recipe", isDirectory: true)
    let marker = recipeDir.appendingPathComponent(".localErasePending")
    let libraryURL = recipeDir.appendingPathComponent("library.json")
    let store = RecipeStore(fileURL: libraryURL)
    let localRecipe = Recipe(title: "Original", steps: [.init(instruction: "Save.")])
    try store.upsert(localRecipe)

    try RecipeLocalEraseMarker.persist(at: marker)
    try store.clearLocalLibraryOnly()
    let restarted = RecipeStore(fileURL: libraryURL)
    #expect(restarted.recipes.isEmpty)
    #expect(RecipeLocalEraseMarker.isPresent(at: marker))
    // An old cached base could remain, but is not authoritative while this
    // independent marker exists; CloudSyncCoordinator refuses to load it.

    let downloaded = RecipeLibrarySnapshot(
        recipes: [Recipe(title: "Cloud still exists", steps: [.init(instruction: "Stir.")])]
    )
    try restarted.replaceLibrary(with: downloaded)
    // This clear models the coordinator's confirmed-cloud-success path only.
    try RecipeLocalEraseMarker.clear(at: marker)
    #expect(!RecipeLocalEraseMarker.isPresent(at: marker))
    #expect(restarted.recipes.count == 1)
}
