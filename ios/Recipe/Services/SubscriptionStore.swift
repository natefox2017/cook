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
                await transaction.finish()
                await self.refreshEntitlements()
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
            state = .unavailable(error.localizedDescription)
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
                await transaction.finish()
                await refreshEntitlements()

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
            if state != .active {
                message = "No active RecipePouch subscription was found for this App Store account."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        let configuredProductIDs = Set(Self.productIDs)
        guard !configuredProductIDs.isEmpty else {
            state = .unavailable("Subscription products have not been configured.")
            return
        }

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard configuredProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            state = .active
            return
        }

        state = .free
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
