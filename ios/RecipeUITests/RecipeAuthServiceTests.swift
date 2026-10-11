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
        try oldCloud.upsert(
            Recipe(title: "Old session soup", steps: [.init(instruction: "Simmer.")]))
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
        let defaults = makeAuthDefaults()
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
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
                _ = try await coordinator.deleteAccountAndCloudData()
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
            await service.completeDeletion(
                with: .success(CloudAccountDeletionResult(sessionChanged: false)))
        }
        let wasCancelled = try await deletion.value
        XCTAssertTrue(
            wasCancelled, "An obsolete deletion must not report success to a new session.")
        XCTAssertNil(defaults.string(forKey: "recipe.sync.deletedAccountPendingSignOut"))
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
            await coordinator.bind(
                store: oldStore, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        let newBinding = Task {
            await coordinator.bind(
                store: newStore, authState: .signedIn(userID: userID, email: nil))
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

    func testEditsDuringInitialDownloadRemainPendingAtSameRevision() async throws {
        try await verifyEditsDuringInitialDownload(remoteRevision: 1)
    }

    func testEditsDuringInitialDownloadRemainPendingAtNewRevision() async throws {
        try await verifyEditsDuringInitialDownload(remoteRevision: 2)
    }

    private func verifyEditsDuringInitialDownload(remoteRevision: Int64) async throws {
        let service = PausedCloudSyncService()
        let defaults = makeAuthDefaults()
        defaults.set(CloudSyncMode.automatic.rawValue, forKey: "recipe.sync.mode")
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
        let store = RecipeStore()
        let cloud = RecipeStore()
        let originalRecipe = Recipe(
            title: "Previously synced soup",
            steps: [.init(instruction: "Simmer.")]
        )
        try cloud.upsert(originalRecipe)
        let userID = UUID()
        let firstLogin = Task {
            await coordinator.bind(
                store: store,
                authState: .signedIn(userID: userID, email: nil)
            )
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(try cloudEnvelope(store: cloud)))
        await firstLogin.value
        await coordinator.authenticationChanged(.signedOut)

        let secondLogin = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)
        let pendingRecipe = Recipe(
            title: "Added while cloud download was waiting",
            steps: [.init(instruction: "Stir.")]
        )
        try store.upsert(pendingRecipe)
        if remoteRevision > 1 {
            try cloud.upsert(
                Recipe(title: "Independent remote soup", steps: [.init(instruction: "Boil.")])
            )
        }
        let remote = try cloudEnvelope(store: cloud, revision: remoteRevision)
        await service.completeDownload(2, with: .success(remote))
        // Login must schedule the edit itself; a forced manual upload would
        // hide an incorrectly advanced lastExportedToken.
        try await service.waitForRequests(uploads: 1)
        let uploadedRecipeIDs = await service.uploadedRecipeIDs
        XCTAssertTrue(uploadedRecipeIDs.first?.contains(pendingRecipe.id) == true)
        await service.completeUpload(
            with: .success(try cloudEnvelope(store: store, revision: remoteRevision + 1))
        )
        await secondLogin.value
        XCTAssertTrue(store.recipes.contains { $0.id == pendingRecipe.id })
    }

    private func cloudEnvelope(
        store: RecipeStore,
        revision: Int64 = 1
    ) throws -> CloudSnapshotEnvelope {
        let payload = try store.exportCloudSnapshot()
        return CloudSnapshotEnvelope(
            schemaVersion: payload.version,
            payload: payload,
            clientUpdatedAt: Date(timeIntervalSince1970: 1_791_670_000),
            revision: revision,
            serverUpdatedAt: Date(timeIntervalSince1970: 1_791_670_001)
        )
    }

    func testConfirmedDeletionBlocksSyncAfterRestartUntilExplicitSignOut() async throws {
        let service = PausedCloudSyncService()
        let defaults = makeAuthDefaults()
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
        let store = RecipeStore()
        let userID = UUID()
        let login = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await login.value
        let deletion = Task {
            try await coordinator.deleteAccountAndCloudData()
        }
        try await service.waitForRequests(deletions: 1)
        // A repeated continuous-session notification must not discard a valid receipt.
        await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))
        await service.completeDeletion(
            with: .success(CloudAccountDeletionResult(sessionChanged: false)))
        let result = try await deletion.value
        XCTAssertFalse(result.sessionChanged)
        XCTAssertEqual(coordinator.state, .localOnly)
        await coordinator.appBecameActive()
        await coordinator.syncNow()
        await coordinator.authenticationChanged(.signedIn(userID: userID, email: nil))

        let restarted = try makeCloudCoordinator(service: service, defaults: defaults)
        await restarted.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        await restarted.appBecameActive()
        await restarted.syncNow()
        let downloadsBeforeSignOut = await service.downloadCount
        let uploadsBeforeSignOut = await service.uploadCount
        XCTAssertEqual(downloadsBeforeSignOut, 1)
        XCTAssertEqual(uploadsBeforeSignOut, 0)

        await restarted.authenticationChanged(.signedOut)
        let newLogin = Task {
            await restarted.authenticationChanged(.signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 2)
        await service.completeDownload(2, with: .success(nil))
        await newLogin.value
        XCTAssertEqual(restarted.state, .localOnly)
    }

    func testOldUploadSlotReleaseResumesOnlyEligibleNewSessionChanges() async throws {
        let service = PausedCloudSyncService()
        let defaults = makeAuthDefaults()
        defaults.set(CloudSyncMode.automatic.rawValue, forKey: "recipe.sync.mode")
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
        let oldStore = RecipeStore()
        let oldRecipe = Recipe(title: "Account A soup", steps: [.init(instruction: "Simmer.")])
        try oldStore.upsert(oldRecipe)
        let userA = UUID()
        let userB = UUID()
        let loginA = Task {
            await coordinator.bind(store: oldStore, authState: .signedIn(userID: userA, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await loginA.value
        let uploadA = Task {
            await coordinator.chooseInitialSync(.mergeLibraries)
        }
        try await service.waitForRequests(uploads: 1)
        let currentStore = RecipeStore()
        let loginB = Task {
            await coordinator.bind(
                store: currentStore, authState: .signedIn(userID: userB, email: nil))
        }
        try await service.waitForRequests(downloads: 2)
        await service.completeDownload(2, with: .success(nil))
        await loginB.value
        let currentRecipe = Recipe(title: "Account B soup", steps: [.init(instruction: "Stir.")])
        try currentStore.upsert(currentRecipe)
        await coordinator.localStoreChanged(token: currentStore.changeToken)
        let uploadsWhileOldSlotHeld = await service.uploadCount
        XCTAssertEqual(uploadsWhileOldSlotHeld, 1)

        await service.completeUpload(with: .success(try cloudEnvelope(store: oldStore)))
        await uploadA.value
        try await service.waitForRequests(uploads: 2)
        let owners = await service.uploadedUserIDs
        let recipes = await service.uploadedRecipeIDs
        XCTAssertEqual(owners, [userA, userB])
        XCTAssertEqual(recipes, [[oldRecipe.id], [currentRecipe.id]])
        let currentEnvelope = try cloudEnvelope(store: currentStore)
        await service.completeUpload(with: .success(currentEnvelope))
        await waitUntil {
            coordinator.lastSyncedAt == currentEnvelope.serverUpdatedAt
        }
        XCTAssertEqual(currentStore.recipes.map(\.id), [currentRecipe.id])
    }

    func testDeletionTransportCancellationKeepsDurableSyncBarrier() async throws {
        try await verifyDeletionCancellationBarrier(beforeRequest: false)
    }

    func testOldDeletionReceiptCannotOverwriteAnotherUsersPendingBarrier() async throws {
        let service = PausedCloudSyncService()
        let defaults = makeAuthDefaults()
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
        let userA = UUID()
        let userB = UUID()
        let loginA = Task {
            await coordinator.bind(
                store: RecipeStore(), authState: .signedIn(userID: userA, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await loginA.value
        let deleteA = Task {
            do {
                _ = try await coordinator.deleteAccountAndCloudData()
                return false
            } catch is CancellationError {
                return true
            }
        }
        try await service.waitForRequests(deletions: 1)
        await coordinator.authenticationChanged(.signedOut)
        let loginB = Task {
            await coordinator.authenticationChanged(.signedIn(userID: userB, email: nil))
        }
        try await service.waitForRequests(downloads: 2)
        await service.completeDownload(2, with: .success(nil))
        await loginB.value
        let deleteB = Task {
            try await coordinator.deleteAccountAndCloudData()
        }
        try await service.waitForRequests(deletions: 2)
        await service.completeDeletion(
            1, with: .success(CloudAccountDeletionResult(sessionChanged: true)))
        let cancelledA = try await deleteA.value
        XCTAssertTrue(cancelledA)
        XCTAssertEqual(
            defaults.string(forKey: "recipe.sync.deletedAccountPendingSignOut"), userB.uuidString)
        XCTAssertEqual(coordinator.state, .syncing)
        await service.completeDeletion(
            2, with: .success(CloudAccountDeletionResult(sessionChanged: false)))
        let resultB = try await deleteB.value
        XCTAssertFalse(resultB.sessionChanged)
        XCTAssertEqual(
            defaults.string(forKey: "recipe.sync.deletedAccountPendingSignOut"), userB.uuidString)
        let deletedUsers = await service.deletionUserIDs
        XCTAssertEqual(deletedUsers, [userA, userB])
    }

    func testDeletionIdentityMismatchRemovesOnlyItsOwnPreRequestBarrier() async throws {
        try await verifyDeletionCancellationBarrier(beforeRequest: true)
    }

    private func verifyDeletionCancellationBarrier(beforeRequest: Bool) async throws {
        let service = PausedCloudSyncService()
        let defaults = makeAuthDefaults()
        let coordinator = try makeCloudCoordinator(service: service, defaults: defaults)
        let store = RecipeStore()
        if beforeRequest {
            try store.upsert(
                Recipe(title: "Unapproved local soup", steps: [.init(instruction: "Simmer.")]))
        }
        let userID = UUID()
        let login = Task {
            await coordinator.bind(store: store, authState: .signedIn(userID: userID, email: nil))
        }
        try await service.waitForRequests(downloads: 1)
        await service.completeDownload(1, with: .success(nil))
        await login.value
        let previousState = coordinator.state
        let deletion = Task {
            do {
                _ = try await coordinator.deleteAccountAndCloudData()
                return false
            } catch is CancellationError {
                return true
            }
        }
        try await service.waitForRequests(deletions: 1)
        if beforeRequest {
            await service.completeDeletion(
                with: .failure(CloudAccountDeletionRequestError.identityChangedBeforeRequest))
        } else {
            await service.completeDeletion(with: .failure(CancellationError()))
        }
        let cancelled = try await deletion.value
        XCTAssertTrue(cancelled)
        let marker = defaults.string(forKey: "recipe.sync.deletedAccountPendingSignOut")
        XCTAssertEqual(marker, beforeRequest ? nil : userID.uuidString)
        if beforeRequest {
            XCTAssertEqual(coordinator.state, previousState)
            XCTAssertFalse(coordinator.state.permitsUpload)
        } else {
            await coordinator.syncNow()
            await coordinator.appBecameActive()
            let downloads = await service.downloadCount
            XCTAssertEqual(downloads, 1)
        }
    }

    private func makeCloudCoordinator(
        service: PausedCloudSyncService,
        defaults suppliedDefaults: UserDefaults? = nil,
        supportDirectory suppliedRoot: URL? = nil
    ) throws -> CloudSyncCoordinator {
        let root =
            suppliedRoot
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RecipeCloudSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            await service.cancelPendingRequests()
            try? FileManager.default.removeItem(at: root)
        }
        let defaults = suppliedDefaults ?? makeAuthDefaults()
        if defaults.string(forKey: "recipe.sync.mode") == nil {
            defaults.set(CloudSyncMode.manual.rawValue, forKey: "recipe.sync.mode")
        }
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
        XCTAssertNil(defaults.string(forKey: "recipe.auth.pending_password_recovery_email_hash"))

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

    func testAnotherAccountCallbackPreservesPendingPasswordRecovery() async throws {
        let recoveryEmail = "recipe-recovery-a@example.test"
        let otherEmail = "recipe-callback-b@example.test"
        let otherUserID = UUID()
        let defaults = makeAuthDefaults()
        let storage = MemoryAuthStorage()
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/recover":
                return .json(payload: [:])
            case "/auth/v1/token":
                return .json(payload: sessionPayload(id: otherUserID, email: otherEmail))
            default:
                return .json(statusCode: 404, payload: ["message": "Unexpected Auth request"])
            }
        }

        let originalService = makeService(defaults: defaults, storage: storage)
        await waitUntil { originalService.state == .signedOut }
        try await originalService.sendPasswordReset(to: recoveryEmail)
        let pendingHash = defaults.string(
            forKey: "recipe.auth.pending_password_recovery_email_hash"
        )
        XCTAssertNotNil(pendingHash)

        // Recreate the service to exercise the persisted cold-launch intent.
        let callbackService = makeService(defaults: defaults, storage: storage)
        await waitUntil { callbackService.state == .signedOut }
        callbackService.handleAuthCallback(
            URL(string: "cook://auth/callback?code=other-account-code")!
        )
        await waitUntil {
            callbackService.state == .signedIn(userID: otherUserID, email: otherEmail)
                && callbackService.authCallbackGeneration == 1
        }
        XCTAssertTrue(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))
        XCTAssertEqual(
            defaults.string(forKey: "recipe.auth.pending_password_recovery_email_hash"),
            pendingHash
        )

        // Start a new reset to install a fresh SDK PKCE verifier for this second callback.
        try await originalService.sendPasswordReset(to: recoveryEmail)
        // An explicit recovery for B must likewise not erase A's reset intent.
        callbackService.handleAuthCallback(
            URL(string: "cook://auth/callback?code=other-recovery-code&type=recovery")!
        )
        await waitUntil {
            callbackService.state == .passwordRecovery(userID: otherUserID)
                && callbackService.authCallbackGeneration == 2
        }
        XCTAssertTrue(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))
        XCTAssertEqual(
            defaults.string(forKey: "recipe.auth.pending_password_recovery_email_hash"),
            pendingHash
        )
    }

    func testFailedCallbackPreservesPendingPasswordRecovery() async throws {
        let defaults = makeAuthDefaults()
        AuthMockURLProtocol.setHandler { request in
            if request.url?.path == "/auth/v1/recover" {
                return .json(payload: [:])
            }
            return .json(
                statusCode: 400,
                payload: ["code": "bad_code_verifier", "message": "Rejected callback"]
            )
        }
        let service = makeService(defaults: defaults)
        await waitUntil { service.state == .signedOut }
        try await service.sendPasswordReset(to: "recipe-recovery@example.test")
        let pendingHash = defaults.string(
            forKey: "recipe.auth.pending_password_recovery_email_hash"
        )
        XCTAssertNotNil(pendingHash)
        service.handleAuthCallback(URL(string: "cook://auth/callback?code=rejected-code")!)
        await waitUntil {
            if case .error = service.state {
                return service.authCallbackGeneration == 1
            }
            return false
        }
        XCTAssertTrue(defaults.bool(forKey: "recipe.auth.pending_password_recovery"))
        XCTAssertEqual(
            defaults.string(forKey: "recipe.auth.pending_password_recovery_email_hash"),
            pendingHash
        )
    }

    func testAccountDeletionPinsJWTAndRequiresExplicitSignOut() async throws {
        let fixture = makeDeletionHTTPFixture()
        let userID = UUID()
        fixture.control.setLogin(userID: userID, token: "deletion-session-A")
        _ = try await fixture.client.auth.signIn(
            email: "owner@example.test", password: "test-password")
        let deletion = Task {
            try await fixture.service.deleteAccountAndCloudData(for: userID)
        }
        try await fixture.control.waitForDeletionRequest()
        XCTAssertEqual(fixture.control.authorization, "Bearer deletion-session-A")
        fixture.control.releaseDeletionResponse()
        let result = try await deletion.value
        XCTAssertFalse(result.sessionChanged)
        XCTAssertEqual(fixture.client.auth.currentSession?.accessToken, "deletion-session-A")
        XCTAssertEqual(fixture.control.logoutCount, 0)

        // The normal explicit Auth sign-out removes saved credentials even
        // when the deleted account's logout endpoint answers 401.
        try await fixture.client.auth.signOut()
        XCTAssertNil(fixture.client.auth.currentSession)
        XCTAssertEqual(fixture.control.logoutCount, 1)
    }

    func testAccountDeletionDoesNotSignOutAnotherUser() async throws {
        try await verifyDeletionKeepsChangedSession(reloggedAsSameUser: false)
    }

    func testAccountDeletionDoesNotSignOutNewTokenForSameUser() async throws {
        try await verifyDeletionKeepsChangedSession(reloggedAsSameUser: true)
    }

    func testAccountDeletionRejectsWrongExpectedUserBeforeSending() async throws {
        let fixture = makeDeletionHTTPFixture()
        let currentUserID = UUID()
        fixture.control.setLogin(userID: currentUserID, token: "deletion-session-B")
        _ = try await fixture.client.auth.signIn(
            email: "owner@example.test", password: "test-password")
        do {
            _ = try await fixture.service.deleteAccountAndCloudData(for: UUID())
            XCTFail("A different intended owner must never reach the deletion endpoint.")
        } catch CloudAccountDeletionRequestError.identityChangedBeforeRequest {
        }
        XCTAssertEqual(fixture.control.deletionCount, 0)
        XCTAssertEqual(fixture.control.logoutCount, 0)
        XCTAssertEqual(fixture.client.auth.currentSession?.user.id, currentUserID)
    }

    private func verifyDeletionKeepsChangedSession(reloggedAsSameUser: Bool) async throws {
        let fixture = makeDeletionHTTPFixture()
        let originalUserID = UUID()
        fixture.control.setLogin(userID: originalUserID, token: "deletion-session-A1")
        _ = try await fixture.client.auth.signIn(
            email: "owner@example.test", password: "test-password")
        let deletion = Task {
            try await fixture.service.deleteAccountAndCloudData(for: originalUserID)
        }
        try await fixture.control.waitForDeletionRequest()
        let currentUserID = reloggedAsSameUser ? originalUserID : UUID()
        fixture.control.setLogin(userID: currentUserID, token: "deletion-session-new")
        _ = try await fixture.client.auth.signIn(
            email: "owner@example.test", password: "test-password")
        fixture.control.releaseDeletionResponse()
        let result = try await deletion.value
        XCTAssertTrue(result.sessionChanged)
        XCTAssertEqual(fixture.control.authorization, "Bearer deletion-session-A1")
        XCTAssertEqual(fixture.client.auth.currentSession?.user.id, currentUserID)
        XCTAssertEqual(fixture.client.auth.currentSession?.accessToken, "deletion-session-new")
        XCTAssertEqual(fixture.control.logoutCount, 0)
    }

    private func makeDeletionHTTPFixture() -> (
        client: SupabaseClient,
        service: SupabaseCloudSync,
        control: PausedDeletionHTTPController
    ) {
        let control = PausedDeletionHTTPController()
        addTeardownBlock {
            control.releaseDeletionResponse()
        }
        AuthMockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/v1/token":
                return .json(payload: control.loginPayload())
            case "/functions/v1/delete-account":
                control.recordDeletion(request)
                return .json(
                    payload: ["ok": true],
                    beforeResponse: {
                        control.waitUntilResponseReleased()
                    })
            case "/auth/v1/logout":
                control.recordLogout()
                return .json(statusCode: 401, payload: ["message": "The account was deleted"])
            default:
                return .json(
                    statusCode: 404, payload: ["message": "Unexpected deletion test request"])
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://auth.mock.invalid")!,
            supabaseKey: "sb_publishable_local_test_key",
            options: .init(
                auth: .init(storage: MemoryAuthStorage(), autoRefreshToken: false),
                global: .init(session: session)
            )
        )
        let functions = FunctionsClient(
            url: URL(string: "https://auth.mock.invalid/functions/v1")!,
            headers: ["apikey": "sb_publishable_local_test_key"],
            fetch: { request in
                try await session.data(for: request)
            }
        )
        return (
            client,
            SupabaseCloudSync(client: client, accountDeletionFunctions: functions),
            control
        )
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
    private(set) var uploadedUserIDs: [UUID] = []
    private(set) var uploadedRecipeIDs: [[UUID]] = []
    private(set) var deletionCount = 0
    private var downloads: [Int: CheckedContinuation<CloudSnapshotEnvelope?, any Error>] = [:]
    private var pendingUpload: CheckedContinuation<CloudSnapshotEnvelope, any Error>?
    private var pendingDeletions:
        [Int: CheckedContinuation<CloudAccountDeletionResult, any Error>] = [:]
    private(set) var deletionUserIDs: [UUID] = []
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
        uploadedUserIDs.append(userID)
        uploadedRecipeIDs.append(snapshot.payload.recipes.map(\.id))
        return try await withCheckedThrowingContinuation { continuation in
            pendingUpload = continuation
        }
    }

    func deleteAccountAndCloudData(for userID: UUID) async throws -> CloudAccountDeletionResult {
        deletionCount += 1
        deletionUserIDs.append(userID)
        let requestID = deletionCount
        return try await withCheckedThrowingContinuation { continuation in
            pendingDeletions[requestID] = continuation
        }
    }

    func completeDownload(_ requestID: Int, with result: Result<CloudSnapshotEnvelope?, any Error>)
    {
        downloads.removeValue(forKey: requestID)?.resume(with: result)
    }

    func completeUpload(with result: Result<CloudSnapshotEnvelope, any Error>) {
        let continuation = pendingUpload
        pendingUpload = nil
        continuation?.resume(with: result)
    }

    func completeDeletion(
        _ requestID: Int? = nil, with result: Result<CloudAccountDeletionResult, any Error>
    ) {
        pendingDeletions.removeValue(forKey: requestID ?? deletionCount)?.resume(with: result)
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
        let pendingDeletionRequests = Array(pendingDeletions.values)
        pendingDeletions.removeAll()
        for continuation in pendingDeletionRequests {
            continuation.resume(throwing: CancellationError())
        }
    }
}

/// Keeps delayed URLProtocol responses off the loading thread, so another
/// synthetic sign-in can finish while the deletion response is pending.
private final class PausedDeletionHTTPController: @unchecked Sendable {
    private let lock = NSLock()
    private let responseGate = DispatchSemaphore(value: 0)
    private var userID = UUID()
    private var token = "unset-test-token"
    private var recordedAuthorization: String?
    private var recordedDeletions = 0
    private var recordedLogouts = 0

    var authorization: String? {
        lock.lock()
        defer { lock.unlock() }
        return recordedAuthorization
    }

    var deletionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedDeletions
    }

    var logoutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedLogouts
    }

    func setLogin(userID: UUID, token: String) {
        lock.lock()
        defer { lock.unlock() }
        self.userID = userID
        self.token = token
    }

    func loginPayload() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var payload = sessionPayload(id: userID, email: "owner@example.test")
        payload["access_token"] = token
        return payload
    }

    func recordDeletion(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        recordedAuthorization = request.value(forHTTPHeaderField: "Authorization")
        recordedDeletions += 1
    }

    func recordLogout() {
        lock.lock()
        defer { lock.unlock() }
        recordedLogouts += 1
    }

    func waitForDeletionRequest() async throws {
        for _ in 0..<100 {
            if deletionCount > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw URLError(.timedOut)
    }

    func waitUntilResponseReleased() {
        responseGate.wait()
    }

    func releaseDeletionResponse() {
        responseGate.signal()
    }
}

private struct AuthMockResponse: Sendable {
    let statusCode: Int
    let body: Data
    let beforeResponse: (@Sendable () -> Void)?

    init(statusCode: Int, body: Data, beforeResponse: (@Sendable () -> Void)? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.beforeResponse = beforeResponse
    }

    static func json(
        statusCode: Int = 200,
        payload: [String: Any],
        beforeResponse: (@Sendable () -> Void)? = nil
    ) -> Self {
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return Self(statusCode: statusCode, body: body, beforeResponse: beforeResponse)
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
        if let beforeResponse = mockResponse.beforeResponse {
            DispatchQueue.global().async {
                beforeResponse()
                self.deliver(mockResponse)
            }
        } else {
            deliver(mockResponse)
        }
    }

    private func deliver(_ mockResponse: AuthMockResponse) {
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
