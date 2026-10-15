// Developer: gengyun
// Purpose: Verifies the purchase identity bridge state machine with injected SDK and server fakes.

import Foundation
import RecipeCore
import StoreKit
import XCTest

@testable import Recipe

@MainActor
final class RecipePurchaseAccountBridgeTests: XCTestCase {

    private let ownerA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let ownerB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func testFreeTestBridgeNeverTouchesClient() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .freeTest, apiKey: "sk_test")
        XCTAssertFalse(bridge.isConfigured)

        bridge.ownerDidChange(to: ownerA)

        XCTAssertNil(bridge.verifiedOwnerID)
        XCTAssertNil(bridge.boundOwnerID)
        XCTAssertEqual(bridge.syncState, .dormant)
        XCTAssertEqual(await client.loggedInAppUserIDs, [])
    }

    func testMissingAPIKeyStaysDormant() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: nil)
        XCTAssertFalse(bridge.isConfigured)

        bridge.ownerDidChange(to: ownerA)

        XCTAssertNil(bridge.verifiedOwnerID)
        XCTAssertEqual(bridge.syncState, .dormant)
        XCTAssertEqual(await client.loggedInAppUserIDs, [])
    }

    func testLoginBindsVerifiedOwnerWithLowercaseAppUserID() async {
        let client = FakeRevenueCatClient()
        await client.setLogInResult(
            .success(RecipeCustomerSnapshot(hasActiveEntitlement: true))
        )
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")
        XCTAssertTrue(bridge.isConfigured)

        bridge.ownerDidChange(to: ownerA)

        await waitForSyncState(bridge, .bound)
        XCTAssertEqual(bridge.verifiedOwnerID, ownerA)
        XCTAssertEqual(bridge.boundOwnerID, ownerA)
        XCTAssertTrue(bridge.hasRevenueCatEntitlement)
        XCTAssertEqual(await client.loggedInAppUserIDs, [ownerA.uuidString.lowercased()])
    }

    func testOwnerChangeDiscardsStaleLogInResult() async {
        let client = FakeRevenueCatClient()
        await client.setLogInResult(
            .success(RecipeCustomerSnapshot(hasActiveEntitlement: false))
        )
        await client.setSuspendNextLogIn()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForLoggedIn(client, 1)

        // Switch owners while owner A's logIn is still suspended.
        bridge.ownerDidChange(to: ownerB)
        await waitForSyncState(bridge, .bound)

        // Resolve owner A's stale logIn with an entitlement; it must be discarded.
        await client.completePendingLogIn(
            with: .success(RecipeCustomerSnapshot(hasActiveEntitlement: true))
        )
        await Task.yield()

        XCTAssertEqual(bridge.verifiedOwnerID, ownerB)
        XCTAssertEqual(bridge.boundOwnerID, ownerB)
        XCTAssertFalse(bridge.hasRevenueCatEntitlement)
        XCTAssertEqual(
            await client.loggedInAppUserIDs,
            [ownerA.uuidString.lowercased(), ownerB.uuidString.lowercased()]
        )
    }

    func testSignOutGatesOwnerWithoutCallingLogOut() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        let generationBeforeSignOut = bridge.ownerGeneration

        bridge.ownerDidChange(to: nil)

        XCTAssertEqual(bridge.syncState, .unbound)
        XCTAssertNil(bridge.verifiedOwnerID)
        XCTAssertNil(bridge.boundOwnerID)
        XCTAssertFalse(bridge.hasRevenueCatEntitlement)
        XCTAssertGreaterThan(bridge.ownerGeneration, generationBeforeSignOut)
        // The SDK is never force-logged-out to an anonymous identity.
        XCTAssertEqual(await client.logOutCount, 0)
    }

    func testRecordPurchaseForwardsAndSyncsOnce() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        let generation = bridge.ownerGeneration

        await bridge.recordVerifiedPurchase(.userCancelled, ownerID: ownerA, generation: generation)

        XCTAssertEqual(bridge.syncState, .bound)
        XCTAssertEqual(await client.recordPurchaseCount, 1)
        XCTAssertEqual(await client.syncPurchaseCount, 1)
    }

    func testRecordPurchaseFailureIsRetryable() async {
        let client = FakeRevenueCatClient()
        await client.setRecordPurchaseResult(.failure(.unavailable))
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        let generation = bridge.ownerGeneration

        await bridge.recordVerifiedPurchase(.userCancelled, ownerID: ownerA, generation: generation)

        XCTAssertEqual(bridge.syncState, .failed)
    }

    func testRecordPurchaseRefusedWhileBinding() async {
        let client = FakeRevenueCatClient()
        await client.setSuspendNextLogIn()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForLoggedIn(client, 1)
        XCTAssertEqual(bridge.syncState, .binding)

        // Still binding (boundOwnerID nil): the SDK side effect must be refused.
        await bridge.recordVerifiedPurchase(
            .userCancelled,
            ownerID: ownerA,
            generation: bridge.ownerGeneration
        )

        XCTAssertEqual(await client.recordPurchaseCount, 0)
        XCTAssertEqual(bridge.syncState, .binding)

        await client.completePendingLogIn(
            with: .success(RecipeCustomerSnapshot(hasActiveEntitlement: false))
        )
        await waitForSyncState(bridge, .bound)
    }

    func testStaleOwnerResultNeverBoundToNewOwner() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        let staleGeneration = bridge.ownerGeneration

        bridge.ownerDidChange(to: ownerB)
        await waitForSyncState(bridge, .bound)

        // Owner A's purchase completes after the switch; stale owner + generation are discarded.
        await bridge.recordVerifiedPurchase(
            .userCancelled,
            ownerID: ownerA,
            generation: staleGeneration
        )

        XCTAssertEqual(await client.recordPurchaseCount, 0)
    }

    func testRestoreConflictSurfacesConflictState() async {
        let client = FakeRevenueCatClient()
        await client.setRestoreResult(.failure(.belongsToOtherOwner))
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        let generation = bridge.ownerGeneration

        await bridge.restore(ownerID: ownerA, generation: generation)

        XCTAssertEqual(bridge.syncState, .conflict)
    }

    func testServerSnapshotOwnerMismatchRejected() async {
        let client = FakeRevenueCatClient()
        let reader = FakeAccessReader(
            result: .success(makeAccessResponse(ownerID: ownerB, premium: true))
        )
        let bridge = makeBridge(client: client, reader: reader, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)

        await bridge.sync(ownerID: ownerA)

        XCTAssertNil(bridge.serverEntitlement)
    }

    func testServerSnapshotPremiumConsumed() async {
        let client = FakeRevenueCatClient()
        let reader = FakeAccessReader(
            result: .success(makeAccessResponse(ownerID: ownerA, premium: true))
        )
        let bridge = makeBridge(client: client, reader: reader, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)

        await bridge.sync(ownerID: ownerA)

        XCTAssertEqual(bridge.serverEntitlement?.status, .premium)
    }

    func testPendingPurchasePreservedAndCleared() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.preservePendingPurchase(productID: "com.shopkivoo.recipe.pro.monthly")
        XCTAssertEqual(
            bridge.pendingContext?.productID,
            "com.shopkivoo.recipe.pro.monthly"
        )

        bridge.clearPendingPurchase()
        XCTAssertNil(bridge.pendingContext)
    }

    func testLoginPreservesPendingPurchaseIntent() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.preservePendingPurchase(productID: "com.shopkivoo.recipe.pro.monthly")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)

        XCTAssertEqual(
            bridge.pendingContext?.productID,
            "com.shopkivoo.recipe.pro.monthly"
        )
    }

    func testOwnerSwitchClearsPendingPurchaseIntent() async {
        let client = FakeRevenueCatClient()
        let bridge = makeBridge(client: client, stage: .commercial, apiKey: "sk_test")

        bridge.preservePendingPurchase(productID: "com.shopkivoo.recipe.pro.monthly")
        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        XCTAssertNotNil(bridge.pendingContext)

        bridge.ownerDidChange(to: ownerB)
        await waitForSyncState(bridge, .bound)

        XCTAssertNil(bridge.pendingContext)
    }

    func testLegacyOnlyEntitlementMarkedNeedsAccountLinkWhenServerNotPremium() async {
        let client = FakeRevenueCatClient()
        let reader = FakeAccessReader(
            result: .success(makeAccessResponse(ownerID: ownerA, premium: false))
        )
        let bridge = makeBridge(client: client, reader: reader, stage: .commercial, apiKey: "sk_test")

        bridge.ownerDidChange(to: ownerA)
        await waitForSyncState(bridge, .bound)
        await bridge.sync(ownerID: ownerA)

        bridge.markNeedsAccountLink()
        XCTAssertEqual(bridge.syncState, .needsAccountLink)
    }

    // MARK: - Helpers

    private func makeBridge(
        client: FakeRevenueCatClient,
        reader: RecipeAccessReading = FakeAccessReader(result: .failure(RecipeAccessReaderError.unavailable)),
        stage: RecipeReleaseStage,
        apiKey: String?
    ) -> RecipePurchaseAccountBridge {
        RecipePurchaseAccountBridge(
            client: client,
            accessReader: reader,
            stage: stage,
            apiKey: apiKey
        )
    }

    private func waitForSyncState(
        _ bridge: RecipePurchaseAccountBridge,
        _ expected: RecipePurchaseSyncState,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while bridge.syncState != expected, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(bridge.syncState, expected)
    }

    private func waitForLoggedIn(
        _ client: FakeRevenueCatClient,
        _ count: Int,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await client.loggedInAppUserIDs.count < count, Date() < deadline {
            await Task.yield()
        }
        let actual = await client.loggedInAppUserIDs.count
        XCTAssertGreaterThanOrEqual(actual, count)
    }

    private func makeAccessResponse(ownerID: UUID, premium: Bool) -> RecipeAccessResponse {
        let json = """
        {
          "owner_id": "\(ownerID.uuidString.lowercased())",
          "server_time": "2026-10-15T00:00:00Z",
          "policy_version": 1,
          "stage": "commercial",
          "entitlement": {
            "status": "\(premium ? "premium" : "free")",
            "valid_until": \(premium ? "\"2026-11-15T00:00:00Z\"" : "null")
          },
          "capabilities": [
            {
              "id": "smart_import",
              "entitled": true,
              "quota": {
                "units": "successful_imports",
                "period_type": "iso_week",
                "period_start": "2026-10-12T00:00:00Z",
                "reset_at": "2026-10-19T00:00:00Z",
                "limit": 5,
                "used": 0,
                "reserved": 0,
                "remaining": 5
              }
            }
          ]
        }
        """
        return try! JSONDecoder().decode(
            RecipeAccessResponse.self,
            from: Data(json.utf8)
        )
    }
}

// MARK: - Fakes

/// Controllable RevenueCat client; suspendable logIn supports deterministic owner-change races.
private actor FakeRevenueCatClient: RecipeRevenueCatClient {
    private(set) var loggedInAppUserIDs: [String] = []
    private(set) var recordPurchaseCount = 0
    private(set) var syncPurchaseCount = 0
    private(set) var restoreCount = 0
    private(set) var logOutCount = 0

    private var logInResult: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError> =
        .success(RecipeCustomerSnapshot(hasActiveEntitlement: false))
    private var syncResult: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError> =
        .success(RecipeCustomerSnapshot(hasActiveEntitlement: false))
    private var restoreResult: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError> =
        .success(RecipeCustomerSnapshot(hasActiveEntitlement: false))
    private var recordPurchaseResult: Result<Bool, RecipeRevenueCatClientError> = .success(true)
    private var suspendNextLogIn = false
    private var pendingLogIns:
        [CheckedContinuation<RecipeCustomerSnapshot, RecipeRevenueCatClientError>] = []

    func setLogInResult(_ result: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError>) {
        logInResult = result
    }

    func setSyncResult(_ result: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError>) {
        syncResult = result
    }

    func setRestoreResult(_ result: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError>) {
        restoreResult = result
    }

    func setRecordPurchaseResult(_ result: Result<Bool, RecipeRevenueCatClientError>) {
        recordPurchaseResult = result
    }

    func setSuspendNextLogIn() {
        suspendNextLogIn = true
    }

    func completePendingLogIn(
        with result: Result<RecipeCustomerSnapshot, RecipeRevenueCatClientError>
    ) {
        guard !pendingLogIns.isEmpty else {
            return
        }
        pendingLogIns.removeFirst().resume(with: result)
    }

    func logIn(appUserID: String) async throws -> RecipeCustomerSnapshot {
        loggedInAppUserIDs.append(appUserID)
        if suspendNextLogIn {
            suspendNextLogIn = false
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<
                    RecipeCustomerSnapshot, RecipeRevenueCatClientError
                >) in
                pendingLogIns.append(continuation)
            }
        }
        return try logInResult.get()
    }

    func syncPurchases() async throws -> RecipeCustomerSnapshot {
        syncPurchaseCount += 1
        return try syncResult.get()
    }

    func restorePurchases() async throws -> RecipeCustomerSnapshot {
        restoreCount += 1
        return try restoreResult.get()
    }

    func recordPurchase(_ result: Product.PurchaseResult) async throws -> Bool {
        recordPurchaseCount += 1
        return try recordPurchaseResult.get()
    }
}

/// Configurable server access reader; returns a decoded frozen DTO snapshot.
private struct FakeAccessReader: RecipeAccessReading {
    let result: Result<RecipeAccessResponse, RecipeAccessReaderError>

    func accessSnapshot() async throws -> RecipeAccessResponse {
        try result.get()
    }
}
