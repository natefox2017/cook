// Developer: gengyun
// Purpose: Verifies the unified access store and upgrade router against fake decoded access snapshots.

import Foundation
import RecipeCore
import XCTest

@testable import Recipe

@MainActor
final class RecipeUpgradeRouterTests: XCTestCase {

    private let ownerA = "00000000-0000-4000-8000-000000000001"
    private let ownerB = "00000000-0000-4000-8000-000000000002"

    func testSameOperationRecoversOnlyOnce() {
        let router = UpgradeRouter(access: RecipeAccessStore(stage: .commercial))

        XCTAssertTrue(router.recover(pendingID: "op-1"))
        XCTAssertFalse(router.recover(pendingID: "op-1"), "A repeated callback must never re-run.")
        XCTAssertTrue(router.recover(pendingID: "op-2"))
    }

    func testCancelKeepsOperationPendingAndNotRecovered() {
        let router = UpgradeRouter(access: RecipeAccessStore(stage: .commercial))

        router.cancel(pendingID: "op-1")

        XCTAssertTrue(router.isCanceled("op-1"))
        // Cancel keeps the operation pending; it does not count as recovered.
        XCTAssertTrue(router.recover(pendingID: "op-1"))
    }

    func testFreeTestStageNeverPresentsUpgrade() {
        let access = RecipeAccessStore(stage: .freeTest)
        let router = UpgradeRouter(access: access)

        XCTAssertFalse(access.isEnabled)
        router.showUpgrade(capability: .handsFreeCooking, pendingID: "op-1")
        XCTAssertNil(router.presented)
        XCTAssertFalse(router.requiresUpgrade(.handsFreeCooking))
    }

    func testOwnerMismatchRejectsResponse() throws {
        let access = RecipeAccessStore(stage: .commercial)
        access.bind(ownerID: ownerA)

        let response = try decode(premiumAccess(ownerID: ownerB))

        XCTAssertFalse(access.apply(response), "A response from another owner must be rejected.")
        XCTAssertNil(access.snapshot)
    }

    func testMatchingOwnerAppliesResponse() throws {
        let access = RecipeAccessStore(stage: .commercial)
        access.bind(ownerID: ownerA)

        let response = try decode(premiumAccess(ownerID: ownerA))

        XCTAssertTrue(access.apply(response))
        XCTAssertTrue(access.hasPremium)
        XCTAssertFalse(access.entitlementExpired)
    }

    func testExpiredEntitlementDoesNotGrantAccess() throws {
        let access = RecipeAccessStore(stage: .commercial)
        access.bind(ownerID: ownerA)

        let response = try decode(expiredAccess(ownerID: ownerA))

        XCTAssertTrue(access.apply(response))
        XCTAssertTrue(access.entitlementExpired)
        XCTAssertFalse(access.hasPremium)
        XCTAssertFalse(access.isEntitled(to: .handsFreeCooking))
        XCTAssertFalse(access.canUse(.handsFreeCooking))

        let router = UpgradeRouter(access: access)
        XCTAssertTrue(router.requiresUpgrade(.handsFreeCooking))
    }

    func testExhaustedQuotaIsNotUsableAndRequiresUpgrade() throws {
        let access = RecipeAccessStore(stage: .commercial)
        access.bind(ownerID: ownerA)

        let response = try decode(premiumAccess(ownerID: ownerA))
        XCTAssertTrue(access.apply(response))

        // smart_import carries 0 remaining in the fixture.
        XCTAssertEqual(access.remaining(for: .smartImport), Optional(0))
        XCTAssertFalse(access.canUse(.smartImport))

        let router = UpgradeRouter(access: access)
        XCTAssertTrue(router.requiresUpgrade(.smartImport))
    }

    func testOwnerSwitchClearsSnapshotAndRouterState() throws {
        let access = RecipeAccessStore(stage: .commercial)
        access.bind(ownerID: ownerA)
        XCTAssertTrue(access.apply(try decode(premiumAccess(ownerID: ownerA))))
        XCTAssertNotNil(access.snapshot)

        let router = UpgradeRouter(access: access)
        router.showUpgrade(capability: .handsFreeCooking, pendingID: "op-1")
        XCTAssertNotNil(router.presented)
        XCTAssertTrue(router.recover(pendingID: "op-1"))

        // Switching owner clears the previous account's snapshot and recovery state.
        access.bind(ownerID: ownerB)
        router.reset()

        XCTAssertNil(access.snapshot)
        XCTAssertNil(router.presented)
        XCTAssertTrue(router.recover(pendingID: "op-1"), "Recovery state must reset on owner switch.")
    }

    // MARK: Fixtures

    private func decode(_ json: String) throws -> RecipeAccessResponse {
        try JSONDecoder().decode(RecipeAccessResponse.self, from: Data(json.utf8))
    }

    private func premiumAccess(ownerID: String) -> String {
        """
        {
          "owner_id": "\(ownerID)",
          "server_time": "2026-10-15T12:00:00.000Z",
          "policy_version": 1,
          "stage": "commercial",
          "entitlement": {"status": "premium", "valid_until": "2026-11-15T00:00:00.000Z"},
          "capabilities": [
            {"id": "hands_free_cooking", "entitled": true, "quota": null},
            {"id": "smart_import", "entitled": true, "quota": {"units": "successful_imports", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 100, "used": 100, "reserved": 0, "remaining": 0}}
          ]
        }
        """
    }

    private func expiredAccess(ownerID: String) -> String {
        """
        {
          "owner_id": "\(ownerID)",
          "server_time": "2026-10-15T12:00:00.000Z",
          "policy_version": 1,
          "stage": "commercial",
          "entitlement": {"status": "expired", "valid_until": "2026-10-01T00:00:00.000Z"},
          "capabilities": [
            {"id": "hands_free_cooking", "entitled": false, "quota": null}
          ]
        }
        """
    }
}
