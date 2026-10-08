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
    try reopened.acknowledge(first, jobID: UUID())
    #expect(try reopened.pendingReceipts().isEmpty)
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
