// Developer: gengyun
// Purpose: Owns StoreKit products, transactions, entitlement refresh, purchase, and restore state.

import Foundation
import Observation
import StoreKit

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
    private(set) var products: [Product] = []
    private(set) var trialEligibleProductIDs = Set<String>()
    private(set) var state: SubscriptionState = .loading
    private(set) var isWorking = false
    private(set) var hasLoaded = false
    var message: String?

    @ObservationIgnored nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = update else { continue }
                await self.finishAfterEntitlementDelivery(
                    transaction,
                    reportUnavailable: false
                )
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load(force: Bool = false) async {
        guard !isWorking else { return }
        guard force || !hasLoaded else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let ids = Self.productIDs
            guard !ids.isEmpty else {
                products = []
                state = .unavailable("Subscription products have not been configured in App Store Connect.")
                hasLoaded = true
                return
            }

            // Preserve any locally verifiable access if product metadata cannot load.
            await refreshEntitlements()
            let loadedProducts = try await Product.products(for: ids)
                .filter { $0.type == .autoRenewable }
                .sorted { $0.price < $1.price }
            guard !loadedProducts.isEmpty else {
                products = []
                await refreshEntitlements()
                if !state.hasEntitlement {
                    state = .unavailable(
                        "No App Store subscription products are available for this storefront right now."
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
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "The App Store transaction could not be verified."
                    return
                }
                await finishAfterEntitlementDelivery(
                    transaction,
                    reportUnavailable: true
                )

            case .pending:
                message = "Your purchase is pending approval."

            case .userCancelled:
                break

            @unknown default:
                message = "The App Store returned an unknown purchase result."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if state.hasEntitlement {
                message = "Your active RecipePouch subscription has been restored."
            } else {
                message = "No active RecipePouch subscription was found for this App Store account."
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
        let configuredIDs = Set(Self.productIDs)
        guard configuredIDs.contains(transaction.productID),
              transaction.revocationDate == nil else {
            await refreshEntitlements()
            return
        }

        let entitledIDs = await refreshEntitlements()
        guard entitledIDs.contains(transaction.productID) else {
            if reportUnavailable {
                message = "The App Store verified your purchase, but the entitlement is not yet available. "
                    + "Check your subscription status or try Restore Purchases."
            }
            return
        }

        await transaction.finish()
    }

    /// Only verified current entitlements grant access; status data refines the
    /// displayed lifecycle state without granting access on its own.
    @discardableResult
    func refreshEntitlements() async -> Set<String> {
        let configuredProductIDs = Set(Self.productIDs)
        guard !configuredProductIDs.isEmpty else {
            state = .unavailable("Subscription products have not been configured.")
            return []
        }

        var entitledProductIDs = Set<String>()
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard configuredProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            entitledProductIDs.insert(transaction.productID)
        }

        var renewalStates: [Product.SubscriptionInfo.RenewalState] = []
        let groupIDs = Set(products.compactMap { $0.subscription?.subscriptionGroupID })
        var statusLookupFailed = false
        for groupID in groupIDs {
            guard let statuses = try? await Product.SubscriptionInfo.status(for: groupID) else {
                statusLookupFailed = true
                continue
            }
            for status in statuses {
                guard case .verified(let transaction) = status.transaction,
                      case .verified = status.renewalInfo,
                      Self.productIDs.contains(transaction.productID) else {
                    continue
                }
                renewalStates.append(status.state)
            }
        }

        if !entitledProductIDs.isEmpty {
            if renewalStates.contains(.inGracePeriod) {
                state = .gracePeriod
            } else if renewalStates.contains(.subscribed),
                      await hasCurrentFreeTrial(in: entitledProductIDs) {
                state = .trial
            } else {
                state = .active
            }
        } else if statusLookupFailed || groupIDs.isEmpty {
            state = .unavailable(
                "The App Store subscription status could not be checked. Try again when you are online."
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
        return entitledProductIDs
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
                  await subscription.isEligibleForIntroOffer else {
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
                  transaction.offer?.paymentMode == .freeTrial else {
                continue
            }
            return true
        }
        return false
    }

    static var productIDs: [String] {
        let keys = [
            "RecipeSubscriptionProductIDs",
            "LegacyCookSubscriptionProductIDs",
        ]

        for key in keys {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
                continue
            }

            let ids = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("$(") }

            if !ids.isEmpty {
                return ids
            }
        }

        return []
    }
}
