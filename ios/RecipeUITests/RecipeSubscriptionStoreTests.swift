// Developer: gengyun
// Purpose: Verifies formal offers and legacy entitlements in hosted local StoreKit tests.

import Foundation
import StoreKit
import StoreKitTest
import XCTest

@testable import Recipe

@MainActor
final class RecipeSubscriptionStoreTests: XCTestCase {
    func testFormalMonthlyAndAnnualPlansHaveNoTrialWithDefaultBuildConfiguration() async throws {
        let session = try makeSession()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        let expectedIDs: Set<String> = [
            "com.shopkivoo.recipe.pro.monthly",
            "com.shopkivoo.recipe.pro.yearly",
        ]
        XCTAssertEqual(Set(SubscriptionStore.productIDs), expectedIDs)

        // Fixture transactions exercise the real service, not ASC Sandbox or UI rendering.
        for productID in expectedIDs.sorted() {
            session.clearTransactions()
            let store = SubscriptionStore()
            await store.load()
            XCTAssertEqual(Set(store.products.map(\.id)), expectedIDs)
            XCTAssertTrue(store.trialEligibleProductIDs.isEmpty)
            XCTAssertFalse(store.state.hasEntitlement)

            let product = try XCTUnwrap(
                store.products.first { product in
                    product.id == productID
                })
            let subscription = try XCTUnwrap(product.subscription)
            XCTAssertEqual(subscription.subscriptionPeriod.value, 1)
            XCTAssertEqual(
                subscription.subscriptionPeriod.unit,
                productID.hasSuffix("monthly") ? .month : .year
            )
            XCTAssertNil(subscription.introductoryOffer)
            XCTAssertFalse(store.isTrialEligible(for: product))
            XCTAssertEqual(
                product.price,
                try XCTUnwrap(Decimal(string: productID.hasSuffix("monthly") ? "4.99" : "39.99"))
            )

            await store.purchase(product)
            await assertLocallyVerifiedEntitlement(for: productID)
            XCTAssertNil(store.message)
            XCTAssertEqual(store.state, .active)
            let entitledIDs = await store.refreshEntitlements()
            XCTAssertTrue(entitledIDs.contains(productID))
            XCTAssertEqual(session.allTransactions().count, 1)
        }
    }

    func testFormalDefaultBuildPreservesLegacySubscriptionAndLifetimeEntitlements() async throws {
        let session = try makeSession()
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        for productID in [
            "com.natefox.cookapp.pro.monthly",
            "com.natefox.cookapp.lifetime",
        ] {
            session.clearTransactions()
            _ = try await session.buyProduct(identifier: productID)
            await assertLocallyVerifiedEntitlement(for: productID)
            let store = SubscriptionStore()
            await store.load()
            let entitledIDs = await store.refreshEntitlements()
            XCTAssertTrue(entitledIDs.contains(productID))
            XCTAssertEqual(store.state, .active)
            XCTAssertFalse(
                store.products.contains { product in
                    product.id == productID
                })
        }
    }

    private func assertLocallyVerifiedEntitlement(for productID: String) async {
        var foundEntitlement = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == productID else {
                    continue
                }
                foundEntitlement = true
                XCTAssertEqual(transaction.environment, .xcode)
            case .unverified(let transaction, let error):
                guard transaction.productID == productID else {
                    continue
                }
                XCTFail("Local fixture transaction was not verified: \(error)")
            }
        }
        XCTAssertTrue(foundEntitlement, "No verified Xcode entitlement for \(productID)")
    }

    private func makeSession() throws -> SKTestSession {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "RecipeSubscriptionTests",
                withExtension: "storekit"
            )
        )
        let session = try SKTestSession(contentsOf: fixtureURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.locale = Locale(identifier: "en_US")
        session.storefront = "USA"
        session.clearTransactions()
        return session
    }
}
