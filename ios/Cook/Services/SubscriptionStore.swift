import Foundation
import Observation
import StoreKit

enum SubscriptionState: Equatable {
    case loading, free, active, unavailable(String)
}

@MainActor @Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var state: SubscriptionState = .loading
    private(set) var isWorking = false
    var message: String?
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let ids = Self.productIDs
            guard !ids.isEmpty else {
                products = []
                state = .unavailable("Subscription products have not been configured in App Store Connect.")
                return
            }
            products = try await Product.products(for: ids).sorted { $0.price < $1.price }
            await refreshEntitlements()
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func purchase(_ product: Product) async {
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
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if state != .active { message = "No active Cook subscription was found for this App Store account." }
        } catch { message = error.localizedDescription }
    }

    func refreshEntitlements() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        state = active ? .active : (Self.productIDs.isEmpty ? .unavailable("Subscription products have not been configured.") : .free)
    }

    static var productIDs: [String] {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CookSubscriptionProductIDs") as? String else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
