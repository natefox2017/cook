// Developer: gengyun
// Purpose: Owns StoreKit products, transactions, entitlement refresh, purchase, and restore state.

import Foundation
import Observation
import RecipeCore
import StoreKit

enum RecipeMonetization {
    // The first release is fully free. Retain paid UI and StoreKit code for a later approved release.
    static let isEnabled = false

    // Commercial build switch (DEV-432 owns future routes). freeTest keeps the RevenueCat SDK,
    // StoreKit networking, and every purchase entry point dormant.
    static var stage: RecipeReleaseStage { .freeTest }
}

enum SubscriptionState: Equatable {
    case loading
    case free
    case trial
    case active
    case gracePeriod
    case billingRetry
    case expired
    case revoked
    case unavailable(String)

    var hasEntitlement: Bool {
        switch self {
        case .trial, .active, .gracePeriod:
            true
        case .loading, .free, .billingRetry, .expired, .revoked, .unavailable:
            false
        }
    }
}

@MainActor @Observable
final class SubscriptionStore {
    private static let unconfiguredProductsMessage =
        RecipeLanguage.localized(
            "Subscription products have not been configured in App Store Connect.")

    private(set) var products: [Product] = []
    private(set) var trialEligibleProductIDs = Set<String>()
    private(set) var state: SubscriptionState = .loading
    private(set) var isWorking = false
    private(set) var hasLoaded = false
    var message: String?

    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    /// Identity bridge binding verified purchases to the Supabase owner (DEV-426).
    let purchaseAccountBridge: RecipePurchaseAccountBridge

    init(purchaseAccountBridge: RecipePurchaseAccountBridge? = nil) {
        self.purchaseAccountBridge =
            purchaseAccountBridge ?? RecipePurchaseAccountBridge.makeProduction()
        guard RecipeMonetization.isEnabled else {
            return
        }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else {
                    return
                }
                guard case .verified(let transaction) = update else {
                    continue
                }
                await self.finishAfterEntitlementDelivery(
                    transaction,
                    reportUnavailable: false
                )
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func load(force: Bool = false) async {
        guard !isWorking else {
            return
        }
        guard force || !hasLoaded else {
            return
        }

        isWorking = true
        defer {
            isWorking = false
        }

        do {
            let ids = Self.productIDs
            guard !ids.isEmpty else {
                products = []
                state = .unavailable(Self.unconfiguredProductsMessage)
                hasLoaded = true
                return
            }

            // Preserve any locally verifiable access if product metadata cannot load.
            await refreshEntitlements()
            let loadedProducts = try await Product.products(for: ids)
                .filter {
                    $0.type == .autoRenewable
                }
                .sorted {
                    $0.price < $1.price
                }
            guard !loadedProducts.isEmpty else {
                products = []
                await refreshEntitlements()
                if !state.hasEntitlement {
                    state = .unavailable(
                        RecipeLanguage.localized(
                            "No App Store subscription products are available for this storefront right now."
                        )
                    )
                }
                // Product availability can be transient; keep load retryable.
                return
            }

            products = loadedProducts
            trialEligibleProductIDs = await eligibleIntroductoryTrialProductIDs(in: loadedProducts)
            await refreshEntitlements()
            hasLoaded = true
        } catch {
            // A storefront/network error must not erase a verified entitlement.
            if !state.hasEntitlement {
                state = .unavailable(error.localizedDescription)
            }
            // Do not cache transient StoreKit failures.
        }
    }

    func purchase(_ product: Product) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        defer {
            isWorking = false
        }

        // Login-first: a commercial purchase must be bound to a verified owner. Without one,
        // preserve the intent and prompt login instead of buying anonymously.
        var options: Set<Product.PurchaseOption> = []
        if RecipeMonetization.stage == .commercial {
            guard let ownerID = purchaseAccountBridge.boundOwnerID else {
                purchaseAccountBridge.preservePendingPurchase(productID: product.id)
                message = RecipeLanguage.localized(
                    "Sign in to purchase a subscription.")
                return
            }
            options = [.appAccountToken(ownerID)]
        }

        // Capture the initiating owner and generation before the native sheet. A sign-out or
        // account switch while the App Store prompt is open must never bind the result to a
        // different owner after the await.
        let initiatingOwnerID = purchaseAccountBridge.boundOwnerID
        let initiatingGeneration = purchaseAccountBridge.ownerGeneration

        let purchaseResult: Product.PurchaseResult
        do {
            purchaseResult = try await product.purchase(options: options)
        } catch {
            message = error.localizedDescription
            return
        }

        switch purchaseResult {
        case .success(let result):
            guard case .verified(let transaction) = result else {
                message = RecipeLanguage.localized(
                    "The App Store transaction could not be verified.")
                return
            }
            // Associate the verified transaction with the initiating owner before finishing it;
            // a later sync backfills any transaction a failed record could not reach RevenueCat.
            if let initiatingOwnerID {
                await purchaseAccountBridge.recordVerifiedPurchase(
                    purchaseResult,
                    ownerID: initiatingOwnerID,
                    generation: initiatingGeneration
                )
            }
            await finishAfterEntitlementDelivery(
                transaction,
                reportUnavailable: true
            )

        case .pending:
            message = RecipeLanguage.localized("Your purchase is pending approval.")

        case .userCancelled:
            break

        @unknown default:
            message = RecipeLanguage.localized(
                "The App Store returned an unknown purchase result.")
        }
    }

    func restore() async {
        guard !isWorking else {
            return
        }
        guard !Self.productIDs.isEmpty else {
            state = .unavailable(Self.unconfiguredProductsMessage)
            message = Self.unconfiguredProductsMessage
            return
        }

        isWorking = true
        defer {
            isWorking = false
        }

        // Capture the bound owner and generation before the native sync so a sign-out/switch
        // during AppStore.sync never pushes the previous owner's receipt to a different owner.
        let ownerID = purchaseAccountBridge.boundOwnerID
        let generation = purchaseAccountBridge.ownerGeneration

        do {
            try await AppStore.sync()
            // Push historical/unfinished transactions to RevenueCat for the initiating owner; the
            // bridge no-ops in freeTest and surfaces owner conflicts without silent transfer.
            if let ownerID {
                await purchaseAccountBridge.restore(
                    ownerID: ownerID,
                    generation: generation
                )
            }
            await refreshEntitlements()
            if state.hasEntitlement {
                message = RecipeLanguage.localized(
                    "Your active Recipe Pals subscription has been restored.")
            } else if case .unavailable(let reason) = state {
                message = reason
            } else {
                message = RecipeLanguage.localized(
                    "No active Recipe Pals subscription was found for this App Store account.")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Deliver the verified entitlement before acknowledging a StoreKit
    /// transaction. A purchase may be verified but not yet reflected in the
    /// active subscription sequence; never finish it before granting access.
    private func finishAfterEntitlementDelivery(
        _ transaction: Transaction,
        reportUnavailable: Bool
    ) async {
        let configuredIDs = Self.entitlementProductIDs
        guard configuredIDs.contains(transaction.productID),
            transaction.revocationDate == nil
        else {
            await refreshEntitlements()
            return
        }

        let entitledIDs = await refreshEntitlements()
        guard entitledIDs.contains(transaction.productID) else {
            if reportUnavailable {
                message =
                    RecipeLanguage.localized(
                        "The App Store verified your purchase, but the entitlement is not yet available. Check your subscription status or try Restore Purchases."
                    )
            }
            return
        }

        await transaction.finish()
    }

    /// Only verified current entitlements grant access; status data refines the
    /// displayed lifecycle state without granting access on its own.
    @discardableResult
    func refreshEntitlements() async -> Set<String> {
        guard !Self.productIDs.isEmpty else {
            state = .unavailable(Self.unconfiguredProductsMessage)
            return []
        }

        var entitledProductIDs = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else {
                continue
            }
            guard Self.entitlementProductIDs.contains(transaction.productID) else {
                continue
            }
            guard transaction.revocationDate == nil else {
                continue
            }
            entitledProductIDs.insert(transaction.productID)
        }

        var renewalStates: [Product.SubscriptionInfo.RenewalState] = []
        let groupIDs = Set(
            products.compactMap {
                $0.subscription?.subscriptionGroupID
            }
        )
        var statusLookupFailed = false
        for groupID in groupIDs {
            guard let statuses = try? await Product.SubscriptionInfo.status(for: groupID) else {
                statusLookupFailed = true
                continue
            }
            for status in statuses {
                guard case .verified(let transaction) = status.transaction,
                    case .verified = status.renewalInfo,
                    Self.entitlementProductIDs.contains(transaction.productID)
                else {
                    continue
                }
                renewalStates.append(status.state)
            }
        }

        if !entitledProductIDs.isEmpty {
            if renewalStates.contains(.inGracePeriod) {
                state = .gracePeriod
            } else if renewalStates.contains(.subscribed),
                await hasCurrentFreeTrial(in: entitledProductIDs)
            {
                state = .trial
            } else {
                state = .active
            }
        } else if statusLookupFailed || groupIDs.isEmpty {
            state = .unavailable(
                RecipeLanguage.localized(
                    "The App Store subscription status could not be checked. Try again when you are online."
                )
            )
        } else if renewalStates.contains(.revoked) {
            state = .revoked
        } else if renewalStates.contains(.expired) {
            state = .expired
        } else if renewalStates.contains(.inBillingRetryPeriod) {
            state = .billingRetry
        } else {
            state = .free
        }
        reconcileAccountLinkState(entitledProductIDs: entitledProductIDs)
        return entitledProductIDs
    }

    /// A local-only legacy entitlement never self-grants server quota. List it for account
    /// linking only when the server explicitly reports no premium (not when it is simply
    /// unreachable), so a pending webhook sync is not mislabeled.
    private func reconcileAccountLinkState(entitledProductIDs: Set<String>) {
        guard !entitledProductIDs.isEmpty,
            entitledProductIDs.isSubset(of: Self.legacyProductIDs)
        else {
            return
        }
        guard let serverEntitlement = purchaseAccountBridge.serverEntitlement else {
            return
        }
        if serverEntitlement.status != .premium {
            purchaseAccountBridge.markNeedsAccountLink()
        }
    }

    func isTrialEligible(for product: Product) -> Bool {
        trialEligibleProductIDs.contains(product.id)
    }

    private func eligibleIntroductoryTrialProductIDs(in products: [Product]) async -> Set<String> {
        var eligibleIDs = Set<String>()
        for product in products {
            guard let subscription = product.subscription,
                let offer = subscription.introductoryOffer,
                offer.paymentMode == .freeTrial,
                await subscription.isEligibleForIntroOffer
            else {
                continue
            }
            eligibleIDs.insert(product.id)
        }
        return eligibleIDs
    }

    private func hasCurrentFreeTrial(in productIDs: Set<String>) async -> Bool {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                productIDs.contains(transaction.productID),
                transaction.offer?.type == .introductory,
                transaction.offer?.paymentMode == .freeTrial
            else {
                continue
            }
            return true
        }
        return false
    }

    static var productIDs: [String] {
        #if DEBUG
            let processInfo = ProcessInfo.processInfo
            if processInfo.arguments.contains("--uitesting"),
                let testProductIDs = processInfo.environment["RECIPE_STOREKIT_TEST_PRODUCT_IDS"]
            {
                return parseProductIDs(testProductIDs)
            }
        #endif

        let keys = [
            "RecipeSubscriptionProductIDs",
            "LegacyCookSubscriptionProductIDs",
        ]

        for key in keys {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
                continue
            }

            let ids = parseProductIDs(raw)

            if !ids.isEmpty {
                return ids
            }
        }

        return []
    }

    /// Legacy purchase identifiers recognized for existing customers but never offered to new ones.
    static var legacyProductIDs: Set<String> {
        let legacyIDs = [
            "com.natefox.cookapp.pro.monthly",
            "com.natefox.cookapp.pro.yearly",
            "com.natefox.cookapp.lifetime",
        ]
        let configuredLegacyIDs =
            (Bundle.main.object(forInfoDictionaryKey: "LegacyCookSubscriptionProductIDs") as? String)
            .map(parseProductIDs) ?? []
        return Set(legacyIDs + configuredLegacyIDs)
    }

    /// Recognize verified legacy purchases without offering their products to new customers.
    static var entitlementProductIDs: Set<String> {
        Set(productIDs).union(legacyProductIDs)
    }

    private static func parseProductIDs(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter {
                !$0.isEmpty && !$0.hasPrefix("$(")
            }
    }
}
