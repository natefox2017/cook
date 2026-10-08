// Developer: gengyun
// Purpose: Owns StoreKit products, transactions, entitlement refresh, purchase, and restore state.

import Foundation
import Observation
import StoreKit

enum SubscriptionState: Equatable {
    case loading
    case free
    case active
    case unavailable(String)
}

@MainActor @Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
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

            let loadedProducts = try await Product.products(for: ids).sorted { $0.price < $1.price }
            guard !loadedProducts.isEmpty else {
                products = []
                await refreshEntitlements()
                if state != .active {
                    state = .unavailable("No App Store subscription products are available for this storefront right now.")
                }
                // Product availability can be transient; keep load retryable.
                return
            }

            products = loadedProducts
            await refreshEntitlements()
            hasLoaded = true
        } catch {
            // A storefront/network error must not erase a verified entitlement.
            if state != .active {
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
            if state == .active {
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
                message = "The App Store verified your purchase, but the entitlement is not yet available. Check your subscription status or try Restore Purchases."
            }
            return
        }

        await transaction.finish()
    }

    /// The App Store's active entitlement sequence includes subscriptions
    /// in billing grace periods. Never unlock from an unverified transaction.
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

        state = entitledProductIDs.isEmpty ? .free : .active
        return entitledProductIDs
    }

    static var productIDs: [String] {
        let keys = [
            "RecipeSubscriptionProductIDs",
            "LegacyCookSubscriptionProductIDs"
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
