// Developer: gengyun
// Purpose: Verifies crash-safe, idempotent and concurrent shared receipt storage.

import Foundation
import Testing
@testable import RecipeCore

private func temporaryShareContainer() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("RecipeShareInboxTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

@Test func sharedURLReceiptSurvivesRestartAndIsIdempotent() throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let inbox = try RecipeShareInbox(containerURL: container)
    let link = "https://example.org/recipe?source=notes"
    let first = try inbox.receive(link, as: .url)
    let again = try inbox.receive(link, as: .url)

    #expect(first == again)
    #expect(first.id == first.clientRequestID)
    #expect(first.localState == .received)
    #expect(try inbox.source(for: first) == link)
    #expect(try inbox.pendingReceipts().map(\.id) == [first.id])

    // A new instance models the main App opening after Share was terminated.
    let reopened = try RecipeShareInbox(containerURL: container)
    #expect(try reopened.pendingReceipts() == [first])
    #expect(try reopened.source(for: first) == link)

    // Merely reopening is not a server ACK.
    #expect(try reopened.pendingReceipts().count == 1)
    let ownerID = UUID()
    let jobID = UUID()
    try reopened.acknowledge(first, jobID: jobID, ownerID: ownerID)
    #expect(try reopened.pendingReceipts(for: ownerID).isEmpty)
    #expect(try reopened.acknowledgedJobID(for: first, ownerID: ownerID) == jobID)
    // No authenticated owner must never be treated as cloud-acknowledged.
    #expect(try reopened.pendingReceipts(for: nil) == [first])
}

@Test func sharedReceiptKeepsAmbiguousAndUnicodeText() throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let inbox = try RecipeShareInbox(containerURL: container)
    let text = "盐适量, 砂糖少许. Simmer until tender; no exact duration."
    let receipt = try inbox.receive(text, as: .text)
    #expect(receipt.inputType == .text)
    #expect(try inbox.source(for: receipt) == text)
}

@Test func sharedReceiptRefusesInvalidInputsWithoutAcknowledgement() throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let inbox = try RecipeShareInbox(containerURL: container)
    #expect(throws: RecipeShareInboxError.self) {
        try inbox.receive("http://127.0.0.1/", as: .url)
    }
    #expect(throws: RecipeShareInboxError.self) {
        try inbox.receive(" ", as: .text)
    }
    #expect(try inbox.pendingReceipts().isEmpty)
}

@Test func concurrentIdenticalSharesDoNotOverwriteOneAnother() async throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }
    let inbox = try RecipeShareInbox(containerURL: container)

    let results = await withTaskGroup(of: UUID?.self, returning: [UUID?].self) {
        group in
        for _ in 0..<16 {
            group.addTask {
                try? inbox.receive("https://example.org/recipe", as: .url).id
            }
        }
        var values: [UUID?] = []
        for await value in group {
            values.append(value)
        }
        return values
    }

    #expect(results.count == 16)
    #expect(results.allSatisfy { $0 != nil })
    #expect(Set(results.compactMap { $0 }).count == 1)
    #expect(try inbox.pendingReceipts().count == 1)
}

@Test func concurrentDifferentSharesAllSurvive() async throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }
    let inbox = try RecipeShareInbox(containerURL: container)

    let results = await withTaskGroup(of: UUID?.self, returning: [UUID?].self) {
        group in
        for index in 0..<12 {
            group.addTask {
                try? inbox.receive(
                    "https://example.org/recipe/\(index)",
                    as: .url
                ).id
            }
        }
        var values: [UUID?] = []
        for await value in group {
            values.append(value)
        }
        return values
    }

    #expect(results.count == 12)
    #expect(results.allSatisfy { $0 != nil })
    #expect(Set(results.compactMap { $0 }).count == 12)
    #expect(try inbox.pendingReceipts().count == 12)
}

@Test func localDeletionClearsPendingAndAcknowledgedSourceFiles() throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let inbox = try RecipeShareInbox(containerURL: container)
    let pending = try inbox.receive("https://example.org/private-recipe", as: .url)
    let acknowledged = try inbox.receive("Salt to taste", as: .text)
    let ownerID = UUID()
    try inbox.acknowledge(acknowledged, jobID: UUID(), ownerID: ownerID)

    #expect(try inbox.pendingReceipts(for: ownerID).map(\.id) == [pending.id])
    try inbox.eraseAllLocalReceipts()

    #expect(try inbox.pendingReceipts().isEmpty)
    #expect(throws: (any Error).self) {
        try inbox.source(for: pending)
    }
    #expect(throws: (any Error).self) {
        try inbox.source(for: acknowledged)
    }
}

@Test func acknowledgementBelongsToAccountNotSourceAlone() throws {
    let container = try temporaryShareContainer()
    defer { try? FileManager.default.removeItem(at: container) }

    let inbox = try RecipeShareInbox(containerURL: container)
    let receipt = try inbox.receive("https://example.org/shared", as: .url)
    let accountA = UUID()
    let accountB = UUID()
    let jobID = UUID()

    try inbox.acknowledge(receipt, jobID: jobID, ownerID: accountA)
    #expect(try inbox.pendingReceipts(for: accountA).isEmpty)
    #expect(try inbox.acknowledgedJobID(for: receipt, ownerID: accountA) == jobID)

    // Another signed-in account must not inherit A's queue acknowledgement.
    #expect(try inbox.acknowledgedJobID(for: receipt, ownerID: accountB) == nil)
    #expect(try inbox.pendingReceipts(for: accountB).map(\.id) == [receipt.id])
    #expect(try inbox.source(for: receipt) == "https://example.org/shared")
}
