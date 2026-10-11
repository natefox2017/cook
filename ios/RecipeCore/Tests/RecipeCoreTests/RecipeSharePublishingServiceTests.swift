// Developer: gengyun
// Purpose: Exercises owner publishing contracts with injected credentials and a network-free HTTP fake.

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Testing
@testable import RecipeCore

@MainActor
private final class SharePublishingFake {
    let ownerID = UUID()
    let shareID = UUID()
    var credentials: RecipeSharePublishingSession?
    var requests: [URLRequest] = []
    var status = 201
    var version = 1
    var responseID: UUID?
    var responseURL = "https://recipes.example.org/r/opaque_share_slug"
    var createdAt = "2026-10-10T11:00:00Z"
    var updatedAt = "2026-10-10T11:00:00.123Z"
    var revokedAt: String?
    var afterSend: (() -> Void)?
    var transportError: Error?
    var sessionReads = 0
    var cancelOnSessionRead: Int?

    init() {
        credentials = RecipeSharePublishingSession(ownerID: ownerID, accessToken: "fake.jwt.token")
    }

    func service() throws -> RecipeSharePublishingService {
        try RecipeSharePublishingService(
            managementEndpoint: URL(string: "https://api.example.org/functions/v1/recipe-share-manage")!,
            session: {
                self.sessionReads += 1
                await Task.yield()
                if self.sessionReads == self.cancelOnSessionRead {
                    withUnsafeCurrentTask { task in
                        task?.cancel()
                    }
                }
                return self.credentials
            },
            send: { request in
                self.requests.append(request)
                if let error = self.transportError {
                    throw error
                }
                self.afterSend?()
                let body: [String: Any] = [
                    "shareID": (self.responseID ?? self.shareID).uuidString,
                    "slug": "opaque_share_slug",
                    "shareVersion": self.version,
                    "scope": "summaryAndSource",
                    "createdAt": self.createdAt,
                    "updatedAt": self.updatedAt,
                    "revokedAt": self.revokedAt.map { $0 as Any } ?? NSNull(),
                    "publicURL": self.responseURL,
                ]
                return (
                    try JSONSerialization.data(withJSONObject: body),
                    HTTPURLResponse(url: request.url!, statusCode: self.status,
                        httpVersion: nil, headerFields: nil)!
                )
            }
        )
    }
}

private func shareApproval(_ recipe: Recipe) -> RecipeShareApproval {
    RecipeShareApproval(
        recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .summaryAndSource, hasDistributionRights: false
    )
}

@Test @MainActor
func publishingPostUsesExactAllowlistUTCAndStableRetryKey() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup", notes: "Never transmit this note")
    let approval = shareApproval(recipe)
    let key = UUID()
    let first = try await service.create(
        recipe: recipe, approval: approval, ownerID: fake.ownerID, idempotencyKey: key
    )
    fake.status = 200
    let retry = try await service.create(
        recipe: recipe, approval: approval, ownerID: fake.ownerID, idempotencyKey: key
    )
    #expect(first.shareID == retry.shareID)
    #expect(first.publicURL == retry.publicURL)
    #expect(first.authenticatedOwnerID == fake.ownerID)
    #expect(fake.requests.count == 2)
    #expect(fake.requests[0].httpBody == fake.requests[1].httpBody)
    let request = fake.requests[0]
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake.jwt.token")
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    let data = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(body.keys) == Set([
        "idempotencyKey", "sourceRecipeID", "sourceRecipeUpdatedAt",
        "scope", "hasDistributionRights", "snapshot",
    ]))
    #expect(body["idempotencyKey"] as? String == key.uuidString)
    #expect((body["sourceRecipeUpdatedAt"] as? String)?.hasSuffix("Z") == true)
    let snapshot = try #require(body["snapshot"] as? [String: Any])
    #expect(Set(snapshot.keys) == Set([
        "title", "summary", "sourceURL", "servings", "prepMinutes",
        "cookMinutes", "ingredients", "steps",
    ]))
    #expect(snapshot["sourceURL"] is NSNull)
    #expect((snapshot["ingredients"] as? [Any])?.isEmpty == true)
    #expect((snapshot["steps"] as? [Any])?.isEmpty == true)
    #expect(!String(decoding: data, as: UTF8.self).contains(recipe.notes))
}

@Test @MainActor
func publishingPreflightRejectsMissingOwnerRightsAndStaleSourceWithoutHTTP() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    fake.credentials = nil
    await #expect(throws: RecipeSharePublishingError.notSignedIn) {
        try await service.create(recipe: recipe, approval: shareApproval(recipe),
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    fake.credentials = RecipeSharePublishingSession(ownerID: UUID(), accessToken: "other.jwt")
    await #expect(throws: RecipeSharePublishingError.accountChanged) {
        try await service.create(recipe: recipe, approval: shareApproval(recipe),
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    let denied = RecipeShareApproval(recipeID: recipe.id, expectedUpdatedAt: recipe.updatedAt,
        scope: .fullInstructions, hasDistributionRights: false)
    await #expect(throws: RecipeShareValidationError.rightsNotConfirmed) {
        try await service.create(recipe: recipe, approval: denied,
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    let stale = RecipeShareApproval(recipeID: recipe.id,
        expectedUpdatedAt: recipe.updatedAt.addingTimeInterval(-1),
        scope: .summaryAndSource, hasDistributionRights: false)
    await #expect(throws: RecipeShareValidationError.staleRecipe) {
        try await service.create(recipe: recipe, approval: stale,
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    #expect(fake.requests.isEmpty)
}

@Test @MainActor
func publishingUpdateUsesShareVersionAndNoCreateKey() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    var recipe = Recipe(title: "Soup")
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    recipe.title = "Updated soup"
    fake.status = 200
    fake.version = 2
    let updated = try await service.update(share, recipe: recipe, approval: shareApproval(recipe))
    #expect(updated.shareVersion == 2)
    let request = try #require(fake.requests.last)
    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "If-Match") == "\"v1\"")
    #expect(request.url?.lastPathComponent == share.shareID.uuidString.lowercased())
    let requestBody = try #require(request.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(body["idempotencyKey"] == nil)
    #expect(body.keys.count == 5)
    fake.status = 409
    await #expect(throws: RecipeSharePublishingError.httpStatus(409)) {
        try await service.update(share, recipe: recipe, approval: shareApproval(recipe))
    }
    #expect(recipe.title == "Updated soup")
    #expect(share.shareVersion == 1)
}

@Test @MainActor
func publishingRevokeRequires204AndCanRepeat() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    for status in [200, 202, 401, 403, 404, 409, 413, 429, 503] {
        fake.status = status
        await #expect(throws: RecipeSharePublishingError.httpStatus(status)) {
            try await service.revoke(share)
        }
    }
    fake.status = 204
    try await service.revoke(share)
    try await service.revoke(share)
    #expect(fake.requests.last?.httpMethod == "DELETE")
    #expect(fake.requests.last?.httpBody == nil)
}

@Test @MainActor
func publishingRejectsAccountSwitchOrLogoutDuringResponse() async throws {
    for logout in [false, true] {
        let fake = SharePublishingFake()
        let service = try fake.service()
        let recipe = Recipe(title: "Soup")
        fake.afterSend = {
            fake.credentials = logout ? nil
                : RecipeSharePublishingSession(ownerID: UUID(), accessToken: "other.jwt")
        }
        let error: RecipeSharePublishingError = logout ? .notSignedIn : .accountChanged
        await #expect(throws: error) {
            try await service.create(recipe: recipe, approval: shareApproval(recipe),
                ownerID: fake.ownerID, idempotencyKey: UUID())
        }
    }
}

@Test @MainActor
func publishingRejectsUnsafeOrMismatchedServerMetadata() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    for url in [
        "http://recipes.example.org/r/opaque_share_slug",
        "https://127.0.0.1/r/opaque_share_slug",
        "https://recipes.example.org/r/different_slug",
        "https://recipes.example.org/r/opaque_share_slug?token=secret",
    ] {
        fake.responseURL = url
        await #expect(throws: RecipeSharePublishingError.invalidResponse) {
            try await service.create(recipe: recipe, approval: shareApproval(recipe),
                ownerID: fake.ownerID, idempotencyKey: UUID())
        }
    }
    fake.responseURL = "https://recipes.example.org/r/opaque_share_slug"
    fake.version = 0
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.create(recipe: recipe, approval: shareApproval(recipe),
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    fake.version = 1
    fake.status = 200
    fake.responseID = UUID()
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.get(shareID: fake.shareID, ownerID: fake.ownerID)
    }
}

@Test @MainActor
func publishingOfflineDoesNotReportSuccessfulRevoke() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    fake.transportError = URLError(.notConnectedToInternet)
    do {
        try await service.revoke(share)
        Issue.record("Offline revoke must throw")
    } catch let error as URLError {
        #expect(error.code == .notConnectedToInternet)
    }
    #expect(recipe.title == "Soup")
}

@Test @MainActor
func publishingReusesCoreUTF16BoundsBeforeSending() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: String(repeating: "😀", count: 91))
    await #expect(throws: RecipeShareValidationError.contentTooLarge) {
        try await service.create(recipe: recipe, approval: shareApproval(recipe),
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    #expect(fake.requests.isEmpty)
}

@Test @MainActor
func publishingRejectsStaleHandlesAfterAccountSwitchBeforeHTTP() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    fake.requests.removeAll()
    fake.credentials = RecipeSharePublishingSession(ownerID: UUID(), accessToken: "other.jwt")
    await #expect(throws: RecipeSharePublishingError.accountChanged) {
        try await service.revoke(share)
    }
    await #expect(throws: RecipeSharePublishingError.accountChanged) {
        try await service.update(share, recipe: recipe, approval: shareApproval(recipe))
    }
    #expect(fake.requests.isEmpty)
}

@Test @MainActor
func publishingGetRebindsOwnerAndRejectsRevokedCreateReplay() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    fake.status = 200
    let share = try await service.get(shareID: fake.shareID, ownerID: fake.ownerID)
    #expect(share.authenticatedOwnerID == fake.ownerID)
    #expect(fake.requests.last?.httpMethod == "GET")
    #expect(fake.requests.last?.httpBody == nil)
    fake.revokedAt = "2026-10-10T12:00:00Z"
    let revoked = try await service.get(shareID: fake.shareID, ownerID: fake.ownerID)
    #expect(revoked.revokedAt != nil)
    let recipe = Recipe(title: "Soup")
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.create(recipe: recipe, approval: shareApproval(recipe),
            ownerID: fake.ownerID, idempotencyKey: UUID())
    }
    let requestCount = fake.requests.count
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.update(revoked, recipe: recipe, approval: shareApproval(recipe))
    }
    #expect(fake.requests.count == requestCount)
}

@Test @MainActor
func publishingDoesNotAcceptUnchangedUpdateVersionOrHideCancellation() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let recipe = Recipe(title: "Soup")
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    fake.status = 200
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.update(share, recipe: recipe, approval: shareApproval(recipe))
    }
    fake.transportError = CancellationError()
    await #expect(throws: CancellationError.self) {
        try await service.revoke(share)
    }
}

@Test @MainActor
func publishingCancellationDuringSessionLookupPreventsSendOrSuccess() async throws {
    for sessionRead in [1, 2] {
        let fake = SharePublishingFake()
        let service = try fake.service()
        let recipe = Recipe(title: "Soup")
        fake.cancelOnSessionRead = sessionRead
        // Cancel a separate task so the remaining assertions and next vector stay active.
        let operation = Task { @MainActor in
            try await service.create(recipe: recipe, approval: shareApproval(recipe),
                ownerID: fake.ownerID, idempotencyKey: UUID())
        }
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
        #expect(fake.requests.count == sessionRead - 1)
    }
}

@Test @MainActor
func publishingAcceptsPostgRESTUTCMetadataAndRejectsNonUTCOffsets() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    fake.status = 200
    fake.createdAt = "2026-10-10T11:00:00+00:00"
    fake.updatedAt = "2026-10-10T11:00:00.123+00:00"
    fake.revokedAt = "2026-10-10T12:00:00+00:00"
    let share = try await service.get(shareID: fake.shareID, ownerID: fake.ownerID)
    #expect(abs(share.updatedAt.timeIntervalSince(share.createdAt) - 0.123) < 0.000001)
    let revokedAt = try #require(share.revokedAt)
    #expect(revokedAt.timeIntervalSince(share.createdAt) == 3_600)

    fake.createdAt = "2026-10-10T11:00:00+01:00"
    await #expect(throws: RecipeSharePublishingError.invalidResponse) {
        try await service.get(shareID: fake.shareID, ownerID: fake.ownerID)
    }
}

@Test @MainActor
func publishingPreservesSourceTimestampMillisecondsOnCreateAndUpdate() async throws {
    let fake = SharePublishingFake()
    let service = try fake.service()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var recipe = Recipe(title: "Soup")
    recipe.updatedAt = try #require(formatter.date(from: "2026-10-10T11:00:00.123Z"))
    let share = try await service.create(recipe: recipe, approval: shareApproval(recipe),
        ownerID: fake.ownerID, idempotencyKey: UUID())
    fake.status = 200
    fake.version = 2
    _ = try await service.update(share, recipe: recipe, approval: shareApproval(recipe))
    for request in fake.requests {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["sourceRecipeUpdatedAt"] as? String == "2026-10-10T11:00:00.123Z")
    }
    #expect(fake.requests.count == 2)
}
