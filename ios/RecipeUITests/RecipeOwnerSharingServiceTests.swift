// Developer: gengyun
// Purpose: Verifies App auth, bounded HTTP, owner lookup, and safe deletion using synthetic sessions.

import Foundation
import RecipeCore
import Supabase
import XCTest

@testable import Recipe

@MainActor
final class RecipeOwnerSharingServiceTests: XCTestCase {
    func testUnavailableDoesNotSendOrDelete() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        let service = RecipeOwnerSharingService(auth: fixture.auth, client: fixture.client)
        let state = service.consentState(recipeID: fixture.recipe.id, store: fixture.store)
        XCTAssertFalse(service.isConfiguredForOwnerSharing)
        XCTAssertFalse(state.isAvailable)
        await state.confirm()
        XCTAssertEqual(state.errorKey, "Sharing is unavailable. Try again later.")
        do {
            try await service.deleteRecipe(recipeID: fixture.recipe.id, store: fixture.store)
            XCTFail("Unavailable service must preserve the recipe")
        } catch {
            XCTAssertEqual(error as? RecipeSharePublishingError, .invalidConfiguration)
        }
        XCTAssertEqual(fixture.store.recipes.count, 1)
        XCTAssertTrue(
            SharingFixtureHTTP.requests.filter { $0.url?.path.contains("functions") == true }
                .isEmpty)
    }

    func testCurrentSessionLoadsServerCopyBeforeConfirmation() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        let state = fixture.service.consentState(recipeID: fixture.recipe.id, store: fixture.store)
        XCTAssertTrue(fixture.service.isConfiguredForOwnerSharing)
        await state.confirm()
        XCTAssertTrue(SharingFixtureHTTP.shareRequests.isEmpty)
        await state.loadOwnerRecords()
        XCTAssertTrue(state.hasLoadedOwnerRecords)
        XCTAssertEqual(state.share?.shareID, SharingFixtureHTTP.shareIDs[0])
        XCTAssertNotNil(state.publicURL)
        let request = try XCTUnwrap(SharingFixtureHTTP.shareRequests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-owner-token")
        XCTAssertEqual(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
            [URLQueryItem(name: "sourceRecipeID", value: fixture.recipe.id.uuidString.lowercased())]
        )
    }

    func testRevokeEveryCopyBeforeLocalDeletion() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        try await fixture.service.deleteRecipe(recipeID: fixture.recipe.id, store: fixture.store)
        XCTAssertTrue(fixture.store.recipes.isEmpty)
        XCTAssertEqual(
            SharingFixtureHTTP.shareRequests.map(\.httpMethod), ["GET", "DELETE", "DELETE"])
    }

    func testFailedRevocationKeepsRecipe() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        SharingFixtureHTTP.deleteStatus = 503
        do {
            try await fixture.service.deleteRecipe(
                recipeID: fixture.recipe.id, store: fixture.store)
            XCTFail("503 must not delete private recipe")
        } catch {
            XCTAssertEqual(error as? RecipeSharePublishingError, .httpStatus(503))
        }
        XCTAssertEqual(fixture.store.recipes.count, 1)
    }

    func testReloginSameAccountInvalidatesOldConsent() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        let state = fixture.service.consentState(recipeID: fixture.recipe.id, store: fixture.store)
        await state.loadOwnerRecords()
        XCTAssertNotNil(state.publicURL)
        try await fixture.auth.signOut()
        try await fixture.auth.signIn(email: "synthetic@example.test", password: "synthetic-only")
        XCTAssertTrue(state.accountChanged)
        XCTAssertNil(state.publicURL)
        let count = SharingFixtureHTTP.shareRequests.count
        await state.confirm()
        XCTAssertEqual(SharingFixtureHTTP.shareRequests.count, count)
    }

    func testAccountSwitchDuringLookupRejectsResponseAndKeepsRecipe() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharingFixtureHTTP.self]
        let service = RecipeOwnerSharingService(
            auth: fixture.auth, client: fixture.client,
            verifiedManagementEndpoint: URL(
                string: "https://sharing.test.invalid/functions/v1/recipe-share-manage")!,
            send: { request in
                let response = try await RecipeShareHTTPTransport.send(
                    request, configuration: configuration)
                try await fixture.auth.signOut()
                SharingFixtureHTTP.switchOwner()
                try await fixture.auth.signIn(
                    email: "synthetic@example.test", password: "synthetic-only")
                return response
            }
        )
        do {
            try await service.deleteRecipe(recipeID: fixture.recipe.id, store: fixture.store)
            XCTFail("Owner B cannot consume owner A lookup")
        } catch {
            XCTAssertEqual(error as? RecipeSharePublishingError, .accountChanged)
        }
        XCTAssertEqual(fixture.store.recipes.count, 1)
        XCTAssertEqual(SharingFixtureHTTP.shareRequests.map(\.httpMethod), ["GET"])
    }

    func testCanceledDeletionDoesNotSendOrDelete() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        let task = Task { @MainActor in
            try await fixture.service.deleteRecipe(
                recipeID: fixture.recipe.id, store: fixture.store)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Canceled deletion must not succeed")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(fixture.store.recipes.count, 1)
        XCTAssertTrue(SharingFixtureHTTP.shareRequests.isEmpty)
    }

    func testFullPageRefusesDeletion() async throws {
        let fixture = try await SharingFixture.make()
        defer { fixture.cleanUp() }
        SharingFixtureHTTP.listCount = 200
        do {
            try await fixture.service.deleteRecipe(
                recipeID: fixture.recipe.id, store: fixture.store)
            XCTFail("Truncated list must fail closed")
        } catch {
            XCTAssertEqual(error as? RecipeSharePublishingError, .invalidResponse)
        }
        XCTAssertEqual(fixture.store.recipes.count, 1)
        XCTAssertEqual(SharingFixtureHTTP.shareRequests.map(\.httpMethod), ["GET"])
    }
}

@MainActor
private struct SharingFixture {
    let auth: RecipeAuthService
    let client: SupabaseClient
    let store: RecipeStore
    let recipe: Recipe
    let suite: String

    var service: RecipeOwnerSharingService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharingFixtureHTTP.self]
        return RecipeOwnerSharingService(
            auth: auth, client: client,
            verifiedManagementEndpoint: URL(
                string: "https://sharing.test.invalid/functions/v1/recipe-share-manage")!,
            send: { request in
                try await RecipeShareHTTPTransport.send(request, configuration: configuration)
            }
        )
    }

    static func make() async throws -> SharingFixture {
        SharingFixtureHTTP.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SharingFixtureHTTP.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://sharing.test.invalid")!,
            supabaseKey: "sb_publishable_synthetic_only",
            options: .init(
                auth: .init(storage: SharingMemoryStorage(), autoRefreshToken: false),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
        let suite = "recipe.sharing-tests.\(UUID())"
        let auth = RecipeAuthService(client: client, defaults: UserDefaults(suiteName: suite)!)
        for _ in 0..<100 {
            if auth.state == .signedOut { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await auth.signIn(email: "synthetic@example.test", password: "synthetic-only")
        let recipe = Recipe(title: "Synthetic soup")
        let store = RecipeStore(fileURL: nil)
        try store.upsert(recipe)
        return SharingFixture(
            auth: auth, client: client, store: store, recipe: recipe, suite: suite)
    }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
}

private final class SharingMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func remove(key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

private final class SharingFixtureHTTP: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var ownerID = UUID()
    static let shareIDs = [UUID(), UUID()]
    nonisolated(unsafe) private static var storedRequests: [URLRequest] = []
    nonisolated(unsafe) private static var storedDeleteStatus = 204
    nonisolated(unsafe) private static var storedListCount = 2

    static var requests: [URLRequest] { lock.withLock { storedRequests } }
    static var shareRequests: [URLRequest] {
        requests.filter { $0.url?.path.contains("functions") == true }
    }
    static var deleteStatus: Int {
        get { lock.withLock { storedDeleteStatus } }
        set { lock.withLock { storedDeleteStatus = newValue } }
    }
    static var listCount: Int {
        get { lock.withLock { storedListCount } }
        set { lock.withLock { storedListCount = newValue } }
    }

    static func switchOwner() {
        lock.withLock { ownerID = UUID() }
    }

    static func reset() {
        lock.withLock {
            storedRequests = []
            storedDeleteStatus = 204
            storedListCount = 2
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.storedRequests.append(request) }
        let path = request.url!.path
        var status = 200
        var body: [String: Any] = [:]
        if path == "/auth/v1/token" {
            body = [
                "access_token": "synthetic-owner-token", "token_type": "bearer",
                "expires_in": 3600,
                "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
                "refresh_token": "synthetic-refresh-token",
                "user": [
                    "id": Self.lock.withLock { Self.ownerID.uuidString }, "aud": "authenticated",
                    "role": "authenticated",
                    "email": "synthetic@example.test", "app_metadata": [:], "user_metadata": [:],
                    "created_at": "2026-10-10T00:00:00Z", "updated_at": "2026-10-10T00:00:00Z",
                ],
            ]
        } else if path == "/auth/v1/logout" {
            status = 204
        } else if request.httpMethod == "DELETE" {
            status = Self.deleteStatus
        } else if path == "/functions/v1/recipe-share-manage" && request.httpMethod == "GET" {
            body = [
                "shares": (0..<Self.listCount).map { index in
                    [
                        "shareID": Self.shareIDs[index % 2].uuidString,
                        "slug": "synthetic_slug_\(index)",
                        "shareVersion": 1, "scope": "summaryAndSource",
                        "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-10T00:00:00Z",
                        "revokedAt": NSNull(),
                        "publicURL": "https://sharing.test.invalid/r/synthetic_slug_\(index)",
                    ] as [String: Any]
                }
            ]
        } else {
            status = 500
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: status == 204 ? Data() : try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
