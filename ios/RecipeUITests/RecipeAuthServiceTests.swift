// Developer: gengyun
// Purpose: Verifies Recipe Auth email, session, and password recovery behavior with a local HTTP stub.

import AuthenticationServices
import Foundation
import RecipeCore
import Supabase
import XCTest

@testable import Recipe

@MainActor
final class RecipeAuthServiceTests: XCTestCase {
    private var defaultsSuiteName: String?

    override func tearDown() {
        AuthMockURLProtocol.clearHandler()
        if let defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
        super.tearDown()
    }

    func testCloudUploadRequiresAccountDownloadAndConflictResolution() {
        // A download in progress or failed download must not silently
        // upload a locally linked library to another Recipe Pals account.
        XCTAssertFalse(CloudSyncCoordinatorState.syncing.permitsUpload)
        XCTAssertFalse(CloudSyncCoordinatorState.error("offline").permitsUpload)
        XCTAssertFalse(CloudSyncCoordinatorState.conflicts([]).permitsUpload)
        XCTAssertTrue(CloudSyncCoordinatorState.localOnly.permitsUpload)
        XCTAssertTrue(CloudSyncCoordinatorState.synced(.now).permitsUpload)
    }

    func testOldCloudDownloadCannotApplyAfterReloginToSameUser() async throws {
        let service = PausedCloudSyncService()
        let store = RecipeStore()
        let coordinator = try makeCloudCoordinator(service: service)
        let userID = UUID()
        let oldLogin = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await coordinator.authenticationChanged(.signedOut)
        let newLogin = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)

        let oldCloud = RecipeStore()
        try oldCloud.upsert(Recipe(title: "Old session soup", steps: [.init(instruction: "Simmer.")]))
        await service.completeDownload(1, with: .success(try cloudEnvelope(store: oldCloud)))
        await oldLogin.value
        XCTAssertTrue(store.recipes.isEmpty)
        XCTAssertEqual(coordinator.state, .syncing)
        XCTAssertFalse(coordinator.state.permitsUpload)
        XCTAssertNil(coordinator.lastSyncedAt)

        await service.completeDownload(2, with: .success(nil))
        await newLogin.value
        XCTAssertEqual(coordinator.state, .localOnly)
        let uploads = await service.uploadCount
        XCTAssertEqual(uploads, 0)
    }

    func testOldCloudDownloadErrorCannotReplaceNewSessionState() async throws {
        let service = PausedCloudSyncService()
        let store = RecipeStore()
        let coordinator = try makeCloudCoordinator(service: service)
        let userID = UUID()
        let oldLogin = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await coordinator.authenticationChanged(.signedOut)
        let newLogin = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)

        await service.completeDownload(1, with: .failure(URLError(.notConnectedToInternet)))
        await oldLogin.value
        XCTAssertEqual(coordinator.state, .syncing)
        XCTAssertFalse(coordinator.state.permitsUpload)
        await service.completeDownload(2, with: .success(nil))
        await newLogin.value
        XCTAssertEqual(coordinator.state, .localOnly)
    }

    func testOldCloudUploadCannotMarkReloggedSessionSynced() async throws {
        try await verifyStaleUploadCompletion(isConflict: false)
    }

    func testOldCloudConflictCannotDownloadOrRetryUnderReloggedSession() async throws {
        try await verifyStaleUploadCompletion(isConflict: true)
    }

    // These fake-service cases cover coordinator sync state and its caller's
    // result only. They do not exercise Supabase's deletion or local sign-out.
    func testOldCoordinatorDeletionCannotClearReloggedSyncState() async throws {
        try await verifyStaleDeletionCompletion(isFailure: false)
    }

    func testOldCoordinatorDeletionErrorReportsCancellation() async throws {
        try await verifyStaleDeletionCompletion(isFailure: true)
    }

    private func verifyStaleDeletionCompletion(isFailure: Bool) async throws {
        let service = PausedCloudSyncService()
        let coordinator = try makeCloudCoordinator(service: service)
        let store = RecipeStore()
        let userID = UUID()
        let login = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await login.value
        let deletion = Task {
            do {
                try await coordinator.deleteAccountAndCloudData()
                return false
            } catch is CancellationError {
                return true
            }
        }
        try await service.waitForRequests(deletions: 1)
        await coordinator.authenticationChanged(.signedOut)
        let newLogin = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)

        if isFailure {
            await service.completeDeletion(with: .failure(URLError(.notConnectedToInternet)))
        } else {
            await service.completeDeletion(with: .success(()))
        }
        let wasCancelled = try await deletion.value
        XCTAssertTrue(wasCancelled, "An obsolete deletion must not report success to a new session.")
        XCTAssertEqual(coordinator.state, .syncing)
        await service.completeDownload(2, with: .success(nil))
        await newLogin.value
        XCTAssertEqual(coordinator.state, .localOnly)
        let sync = Task {
            await coordinator.syncNow()
        }
        try await service.waitForRequests(downloads: 3)
        await service.completeDownload(3, with: .success(nil))
        await sync.value
    }

    func testCurrentCloudSessionStillAppliesConfirmedDownload() async throws {
        let service = PausedCloudSyncService()
        let coordinator = try makeCloudCoordinator(service: service)
        let store = RecipeStore()
        let cloud = RecipeStore()
        let recipe = Recipe(title: "Current session soup", steps: [.init(instruction: "Simmer.")])
        try cloud.upsert(recipe)
        let userID = UUID()
        let login = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        // An unchanged signed-in notification represents the same continuous
        // session, not a sign-out/relogin boundary that cancels valid work.
        await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        let envelope = try cloudEnvelope(store: cloud)
        await service.completeDownload(1, with: .success(envelope))
        await login.value
        XCTAssertEqual(store.recipes.map(\.id), [recipe.id])
        let serverTime = try XCTUnwrap(envelope.serverUpdatedAt)
        XCTAssertEqual(coordinator.state, .synced(serverTime))
    }

    func testOldCloudDownloadCannotApplyAfterRebindingStore() async throws {
        let service = PausedCloudSyncService()
        let coordinator = try makeCloudCoordinator(service: service)
        let oldStore = RecipeStore()
        let newStore = RecipeStore()
        let userID = UUID()
        let oldBinding = Task {
            await coordinator.bind(store: oldStore, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        let newBinding = Task {
            await coordinator.bind(store: newStore, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)
        let cloud = RecipeStore()
        try cloud.upsert(Recipe(title: "Old binding soup", steps: [.init(instruction: "Simmer.")]))
        await service.completeDownload(1, with: .success(try cloudEnvelope(store: cloud)))
        await oldBinding.value
        XCTAssertTrue(oldStore.recipes.isEmpty)
        XCTAssertTrue(newStore.recipes.isEmpty)
        XCTAssertEqual(coordinator.state, .syncing)
        await service.completeDownload(2, with: .success(nil))
        await newBinding.value
        XCTAssertEqual(coordinator.state, .localOnly)
    }

    private func verifyStaleUploadCompletion(isConflict: Bool) async throws {
        // A pre-fix conflict retry must fail the assertion, not suspend forever
        // on a third download while this test awaits the original upload task.
        let service = PausedCloudSyncService(maximumDownloads: 2)
        let coordinator = try makeCloudCoordinator(service: service)
        let store = RecipeStore()
        let recipe = Recipe(title: "Private local soup", steps: [.init(instruction: "Simmer.")])
        try store.upsert(recipe)
        let userID = UUID()
        let login = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await login.value
        let upload = Task {
            await coordinator.chooseInitialSync(.mergeLibraries)
        }
        try await service.waitForRequests(uploads: 1)
        await coordinator.authenticationChanged(.signedOut)
        let newLogin = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)

        if isConflict {
            await service.completeUpload(with: .failure(RecipeCloudSyncError.revisionConflict))
        } else {
            await service.completeUpload(with: .success(try cloudEnvelope(store: store)))
        }
        await upload.value
        XCTAssertEqual(coordinator.state, .syncing)
        XCTAssertNil(coordinator.lastSyncedAt)
        XCTAssertEqual(store.recipes.map(\.id), [recipe.id])
        let downloads = await service.downloadCount
        let uploads = await service.uploadCount
        XCTAssertEqual(downloads, 2)
        XCTAssertEqual(uploads, 1)

        await service.completeDownload(2, with: .success(nil))
        await newLogin.value
        if case .initialChoice = coordinator.state {
        } else {
            XCTFail("The new login must still require consent for its local library.")
        }
        XCTAssertFalse(coordinator.state.permitsUpload)
    }

    private func cloudEnvelope(store: RecipeStore) throws -> CloudSnapshotEnvelope {
        let payload = try store.exportCloudSnapshot()
        return CloudSnapshotEnvelope(
            schemaVersion: payload.version,
            payload: payload,
            clientUpdatedAt: Date(timeIntervalSince1970: 1_791_670_000),
            revision: 1,
            serverUpdatedAt: Date(timeIntervalSince1970: 1_791_670_001)
        )
    }

    private func makeCloudCoordinator(service: PausedCloudSyncService) throws -> CloudSyncCoordinator {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeCloudSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            await service.cancelPendingRequests()
            try? FileManager.default.removeItem(at: root)
        }
        let defaults = makeAuthDefaults()
        defaults.set(CloudSyncMode.manual.rawValue, forKey: "recipe.sync.mode")
        return CloudSyncCoordinator(
            service: service,
            defaults: defaults,
            monitorsNetworkChanges: false,
            supportDirectory: root
        )
    }

    func testGoogleOAuthCancellationIsNotAnAuthenticationError() {
        let cancellation = NSError(
            domain: ASWebAuthenticationSessionErrorDomain,
            code: ASWebAuthenticationSessionError.canceledLogin.rawValue
        )
        XCTAssertTrue(RecipeAuthService.isGoogleSignInCancellation(cancellation))

        let unrelated = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertFalse(RecipeAuthService.isGoogleSignInCancellation(unrelated))
    }

    func testEmailSignupWrongPasswordAndPasswordResetStates() async throws {
        let userID = UUID()
        let email = "recipe-auth@example.test"
        let defaults = makeAuthDefaults()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/signup":
                return .json(payload: userPayload(id: userID, email: email))
            case "/auth/v1/token":
                return .json(
                    statusCode: 400,
                    payload: [
                        "code": "invalid_credentials", "message": "Invalid login credentials",
                    ]
                )
            case "/auth/v1/recover":
                return .json(payload: [:])
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let service = makeService(defaults: defaults)
        await waitUntil { service.state == .signedOut }

        try await service.signUp(email: email, password: "correct-horse-battery")
        XCTAssertEqual(service.state, .needsEmailVerification(email))

        do {
            try await service.signIn(email: email, password: "wrong-password")
            XCTFail("A rejected password must not create an authenticated session.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid login credentials"))
        }
        if case .error = service.state {
        } else {
            XCTFail("A rejected password should leave a recoverable error state.")
        }

        try await service.sendPasswordReset(to: email)
        XCTAssertEqual(service.state, .passwordResetSent(email))
    }

    func testEmailSignInSignOutAndReloginUseTheMockSession() async throws {
        let userID = UUID()
        let email = "recipe-session@example.test"
        let defaults = makeAuthDefaults()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/token":
                return .json(payload: sessionPayload(id: userID, email: email))
            case "/auth/v1/logout":
                return AuthMockResponse(statusCode: 204, body: Data())
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let service = makeService(defaults: defaults)
        await waitUntil { service.state == .signedOut }

        try await service.signIn(email: email, password: "test-password")
        XCTAssertEqual(service.state, .signedIn(userID: userID, email: email))

        try await service.signOut()
        XCTAssertEqual(service.state, .signedOut)

        try await service.signIn(email: email, password: "test-password")
        XCTAssertEqual(service.state, .signedIn(userID: userID, email: email))
    }

    func testEmailConfirmationCallbackSignsInTheConfirmedAccount() async throws {
        let userID = UUID()
        let email = "recipe-confirmation@example.test"
        let defaults = makeAuthDefaults()
        let storage = MemoryAuthStorage()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/signup":
                return .json(payload: userPayload(id: userID, email: email))
            case "/auth/v1/token":
                return .json(payload: sessionPayload(id: userID, email: email))
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let service = makeService(defaults: defaults, storage: storage)
        await waitUntil { service.state == .signedOut }

        try await service.signUp(email: email, password: "test-password-strong")
        XCTAssertEqual(service.state, .needsEmailVerification(email))

        service.handleAuthCallback(
            URL(string: "cook://auth/callback?code=local-confirmation-code")!
        )
        await waitUntil {
            service.state == .signedIn(userID: userID, email: email)
                && service.authCallbackGeneration == 1
        }
        XCTAssertFalse(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))
    }

    func testStoredSessionIsRestoredWhenAuthServiceIsRecreated() async throws {
        let userID = UUID()
        let email = "recipe-restore@example.test"
        let defaults = makeAuthDefaults()
        let storage = MemoryAuthStorage()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/token":
                return .json(payload: sessionPayload(id: userID, email: email))
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let originalService = makeService(defaults: defaults, storage: storage)
        await waitUntil { originalService.state == .signedOut }
        try await originalService.signIn(email: email, password: "test-password")
        XCTAssertEqual(originalService.state, .signedIn(userID: userID, email: email))

        let restoredService = makeService(defaults: defaults, storage: storage)
        await waitUntil { restoredService.state == .signedIn(userID: userID, email: email) }
    }

    func testFailedAuthCallbackPublishesAnAccountRouteableError() async throws {
        let service = makeService(defaults: makeAuthDefaults())
        await waitUntil { service.state == .signedOut }

        service.handleAuthCallback(
            URL(string: "cook://auth/callback?code=missing-local-verifier")!
        )
        await waitUntil {
            if case .error = service.state {
                return service.authCallbackGeneration == 1
            }
            return false
        }
    }

    func testPasswordRecoveryCallbackKeepsRecoveryStateAfterUpdateFailureAndAllowsRetry()
        async throws
    {
        let userID = UUID()
        let email = "recipe-recovery@example.test"
        let defaults = makeAuthDefaults()
        let storage = MemoryAuthStorage()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/recover":
                guard let requestURL = request.url else {
                    return .json(statusCode: 400, payload: ["message": "Missing request URL"])
                }
                let redirectURL = URLComponents(
                    url: requestURL,
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first(where: { $0.name == "redirect_to" })?.value
                guard redirectURL == RecipeSupabase.redirectURL.absoluteString else {
                    return .json(
                        statusCode: 400,
                        payload: ["message": "Unexpected recovery redirect URL"]
                    )
                }
                return .json(payload: [:])
            case "/auth/v1/token":
                return .json(payload: sessionPayload(id: userID, email: email))
            case "/auth/v1/user":
                return .json(
                    statusCode: 400,
                    payload: ["code": "weak_password", "message": "Password is too weak"]
                )
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let service = makeService(defaults: defaults, storage: storage)
        await waitUntil { service.state == .signedOut }
        try await service.sendPasswordReset(to: email)
        XCTAssertTrue(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))

        let callbackService = makeService(defaults: defaults, storage: storage)
        await waitUntil { callbackService.state == .signedOut }
        callbackService.handleAuthCallback(URL(string: "cook://auth/callback?code=local-code")!)
        await waitUntil { callbackService.state == .passwordRecovery(userID: userID) }
        XCTAssertEqual(callbackService.authCallbackGeneration, 1)
        XCTAssertFalse(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))

        do {
            try await callbackService.setRecoveredPassword("short-password")
            XCTFail("The mocked Auth error should be surfaced to the caller.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Password is too weak"))
        }
        XCTAssertEqual(callbackService.state, .passwordRecovery(userID: userID))

        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/user":
                return .json(payload: userPayload(id: userID, email: email))
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        try await callbackService.setRecoveredPassword("longer-local-password")
        XCTAssertEqual(callbackService.state, .signedIn(userID: userID, email: email))
    }

    private func makeService(
        defaults: UserDefaults,
        storage: MemoryAuthStorage = MemoryAuthStorage()
    ) -> RecipeAuthService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://auth.mock.invalid")!,
            supabaseKey: "sb_publishable_local_test_key",
            options: .init(
                auth: .init(storage: storage, autoRefreshToken: false),
                global: .init(session: session)
            )
        )
        return RecipeAuthService(client: client, defaults: defaults)
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Auth state did not reach the expected value.", file: file, line: line)
    }

    private func makeAuthDefaults() -> UserDefaults {
        let suiteName = "RecipeAuthServiceTests-\(UUID().uuidString)"
        defaultsSuiteName = suiteName
        return UserDefaults(suiteName: suiteName)!
    }
}

/// Pauses real coordinator calls at its existing service boundary; never uses Auth or network.
private actor PausedCloudSyncService: RecipeCloudSyncing {
    private(set) var downloadCount = 0
    private(set) var uploadCount = 0
    private(set) var deletionCount = 0
    private var downloads: [Int: CheckedContinuation<CloudSnapshotEnvelope?, any Error>] = [:]
    private var pendingUpload: CheckedContinuation<CloudSnapshotEnvelope, any Error>?
    private var pendingDeletion: CheckedContinuation<Void, any Error>?
    private let maximumDownloads: Int?

    init(maximumDownloads: Int? = nil) {
        self.maximumDownloads = maximumDownloads
    }

    func download(for userID: UUID) async throws -> CloudSnapshotEnvelope? {
        downloadCount += 1
        if let maximumDownloads, downloadCount > maximumDownloads {
            throw URLError(.badServerResponse)
        }
        let requestID = downloadCount
        return try await withCheckedThrowingContinuation { continuation in
            downloads[requestID] = continuation
        }
    }

    func upload(
        _ snapshot: CloudSnapshotEnvelope,
        expectedRevision: Int64,
        for userID: UUID
    ) async throws -> CloudSnapshotEnvelope {
        uploadCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingUpload = continuation
        }
    }

    func deleteAccountAndCloudData() async throws {
        deletionCount += 1
        try await withCheckedThrowingContinuation { continuation in
            pendingDeletion = continuation
        }
    }

    func completeDownload(_ requestID: Int, with result: Result<CloudSnapshotEnvelope?, any Error>) {
        downloads.removeValue(forKey: requestID)?.resume(with: result)
    }

    func completeUpload(with result: Result<CloudSnapshotEnvelope, any Error>) {
        let continuation = pendingUpload
        pendingUpload = nil
        continuation?.resume(with: result)
    }

    func completeDeletion(with result: Result<Void, any Error>) {
        let continuation = pendingDeletion
        pendingDeletion = nil
        continuation?.resume(with: result)
    }

    func waitForRequests(downloads: Int = 0, uploads: Int = 0, deletions: Int = 0) async throws {
        for _ in 0..<100 {
            if downloadCount >= downloads, uploadCount >= uploads, deletionCount >= deletions {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw URLError(.timedOut)
    }

    func cancelPendingRequests() {
        let pending = Array(downloads.values)
        downloads.removeAll()
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
        completeUpload(with: .failure(CancellationError()))
        let continuation = pendingDeletion
        pendingDeletion = nil
        continuation?.resume(throwing: CancellationError())
    }
}

private struct AuthMockResponse: Sendable {
    let statusCode: Int
    let body: Data

    static func json(
        statusCode: Int = 200,
        payload: [String: Any]
    ) -> Self {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return Self(statusCode: statusCode, body: body)
    }
}

private final class AuthMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> AuthMockResponse

    private static let handlerStore = AuthMockHandlerStore()

    static func setHandler(_ handler: @escaping Handler) {
        handlerStore.set(handler)
    }

    static func clearHandler() {
        handlerStore.set(nil)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "auth.mock.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let mockResponse = Self.handlerStore.response(for: request)
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: mockResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !mockResponse.body.isEmpty {
            client?.urlProtocol(self, didLoad: mockResponse.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AuthMockHandlerStore: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: AuthMockURLProtocol.Handler?

    func set(_ handler: AuthMockURLProtocol.Handler?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    func response(for request: URLRequest) -> AuthMockResponse {
        lock.lock()
        let handler = handler
        lock.unlock()
        return handler?(request)
            ?? .json(
                statusCode: 500,
                payload: ["message": "No mock Auth response is configured"]
            )
    }
}

private final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private func userPayload(id: UUID, email: String) -> [String: Any] {
    [
        "id": id.uuidString,
        "aud": "authenticated",
        "role": "authenticated",
        "email": email,
        "app_metadata": ["provider": "email", "providers": ["email"]],
        "user_metadata": [:],
        "created_at": "2026-10-08T00:00:00Z",
        "updated_at": "2026-10-08T00:00:00Z",
    ]
}

private func sessionPayload(id: UUID, email: String) -> [String: Any] {
    [
        "access_token": "local-access-token",
        "token_type": "bearer",
        "expires_in": 3600,
        "expires_at": Date().addingTimeInterval(3600).timeIntervalSince1970,
        "refresh_token": "local-refresh-token",
        "user": userPayload(id: id, email: email),
    ]
}
