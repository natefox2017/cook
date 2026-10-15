// Developer: gengyun
// Purpose: Binds RevenueCat purchases to the verified Supabase owner and guards owner changes without duplicating account identity.

import Foundation
import Observation
import RecipeCore
import StoreKit
import RevenueCat
import Supabase

// MARK: - RevenueCat client port

/// Reduced RevenueCat customer state the bridge actually consumes. Kept as a value type so the
/// bridge and its tests never construct SDK `CustomerInfo` objects.
struct RecipeCustomerSnapshot: Equatable, Sendable {
    /// Whether RevenueCat reports any active subscription for the identified owner.
    let hasActiveEntitlement: Bool
}

/// Typed failures the bridge surfaces from the SDK layer; tests inject these directly.
enum RecipeRevenueCatClientError: Error, Equatable, Sendable {
    /// The receipt or transaction belongs to a different App User ID (restore behavior
    /// "Keep with original App User ID", or a purchase bound to another owner).
    case belongsToOtherOwner
    /// Transient network/SDK failure; retryable.
    case unavailable
}

/// Async surface of the pinned RevenueCat SDK (purchases-ios 5.95.0). The app never calls this
/// protocol directly; `RecipePurchaseAccountBridge` drives it and tests inject fakes.
protocol RecipeRevenueCatClient: Sendable {
    func logIn(appUserID: String) async throws -> RecipeCustomerSnapshot
    func syncPurchases() async throws -> RecipeCustomerSnapshot
    func restorePurchases() async throws -> RecipeCustomerSnapshot
    /// Records a StoreKit 2 purchase the app completed. The SDK deduplicates by transaction, so
    /// replays are idempotent; returns true when a transaction was recorded.
    func recordPurchase(_ result: Product.PurchaseResult) async throws -> Bool
}

// MARK: - Server access port

/// Reads the server-authoritative entitlement snapshot (DEV-427 owns `GET /recipe-access`).
/// The bridge consumes this frozen DTO through injection and never authors server entitlement.
protocol RecipeAccessReading: Sendable {
    func accessSnapshot() async throws -> RecipeAccessResponse
}

/// Real authenticated owner-scoped read of the server snapshot. It consumes the frozen DEV-425
/// `RecipeAccessResponse` DTO over the existing Supabase transport and never authors entitlement;
/// the backend route itself is owned by DEV-427. Any failure maps to a retryable unavailability
/// so the bridge keeps its last snapshot without faking a server entitlement locally.
struct RecipeAccessReaderClient: RecipeAccessReading {
    private let client: SupabaseClient

    init(client: SupabaseClient = RecipeSupabase.client) {
        self.client = client
    }

    func accessSnapshot() async throws -> RecipeAccessResponse {
        do {
            return try await client.functions.invoke(
                "recipe-access",
                options: FunctionInvokeOptions(method: .get)
            )
        } catch {
            // 404 (route not shipped), 503 (unavailable), and decode/auth failures are all
            // retryable; the bridge keeps its last snapshot rather than treating them as free.
            throw RecipeAccessReaderError.unavailable
        }
    }
}

enum RecipeAccessReaderError: Error, Sendable {
    case unavailable
}

// MARK: - Login-first pending purchase

/// A purchase intent preserved across a forced login. The app never buys anonymously; the intent
/// is replayed only after a verified owner is bound.
struct RecipePurchasePendingContext: Equatable, Sendable {
    let productID: String
    let requestedAt: Date
}

// MARK: - Bounded sync lifecycle

enum RecipePurchaseSyncState: Equatable {
    /// freeTest or missing public SDK key: the SDK and network are never touched.
    case dormant
    /// Commercial stage enabled but no verified owner is bound yet.
    case unbound
    /// RevenueCat `logIn` is in flight for a verified owner.
    case binding
    /// Bound to a verified owner; entitlement is known.
    case bound
    /// Post-purchase/restore sync is in flight (webhook-to-ledger delay); retryable.
    case syncing
    /// A local legacy entitlement exists with no trusted server owner; needs account link.
    case needsAccountLink
    /// The receipt/transaction belongs to another owner and is never silently transferred.
    case conflict
    /// Transient failure; retryable without re-prompting a purchase.
    case failed
}

// MARK: - Bridge

@MainActor @Observable
final class RecipePurchaseAccountBridge {

    /// Verified Supabase owner (from the auth session) the bridge is currently serving.
    /// Set immediately on an owner transition; RevenueCat binding proceeds asynchronously.
    private(set) var verifiedOwnerID: UUID?

    /// The owner the RevenueCat SDK is actually identified as. Set only after a successful
    /// `logIn`; nil while binding or after a sign-out/switch. SDK side effects (record/restore/
    /// sync) are gated on this so a stale owner never receives the previous owner's transactions.
    private(set) var boundOwnerID: UUID?

    /// Monotonic generation bumped on every owner change and sign-out so stale async results
    /// captured on an older generation are discarded.
    private(set) var ownerGeneration = 0

    /// RevenueCat-entitlement result for the current binding (active or not).
    private(set) var hasRevenueCatEntitlement = false

    /// Server entitlement snapshot consumed from the injected access port; accepted only when its
    /// `owner_id` matches `verifiedOwnerID`.
    private(set) var serverEntitlement: RecipeEntitlement?

    /// Login-first purchase intent preserved across a forced login; never an anonymous purchase.
    private(set) var pendingContext: RecipePurchasePendingContext?

    /// True only in commercial stage with a resolved public SDK key; freeTest stays dormant.
    var isConfigured: Bool { isCommerciallyEnabled }

    /// Bounded sync lifecycle for surfacing webhook-delay messaging.
    private(set) var syncState: RecipePurchaseSyncState

    @ObservationIgnored private let client: RecipeRevenueCatClient?
    @ObservationIgnored private let accessReader: RecipeAccessReading
    @ObservationIgnored private let stage: RecipeReleaseStage
    @ObservationIgnored private let apiKey: String?
    @ObservationIgnored private let isCommerciallyEnabled: Bool
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(
        client: RecipeRevenueCatClient?,
        accessReader: RecipeAccessReading,
        stage: RecipeReleaseStage,
        apiKey: String?
    ) {
        self.client = client
        self.accessReader = accessReader
        self.stage = stage
        self.apiKey = apiKey
        let hasUsableKey = apiKey.map { !$0.isEmpty && !$0.hasPrefix("$(") } ?? false
        self.isCommerciallyEnabled = stage == .commercial && client != nil && hasUsableKey
        self.syncState = isCommerciallyEnabled ? .unbound : .dormant
    }

    /// Drives the bridge on every auth owner transition (sign-in, sign-out, account switch).
    /// Idempotent for an unchanged owner; fully dormant in freeTest or without a usable key.
    func ownerDidChange(to ownerID: UUID?) {
        guard isCommerciallyEnabled else {
            if verifiedOwnerID != nil {
                verifiedOwnerID = nil
            }
            syncState = .dormant
            return
        }

        guard ownerID != verifiedOwnerID else {
            return
        }

        let previousOwner = verifiedOwnerID

        // Invalidate all in-flight work from the previous owner before binding the next.
        ownerGeneration += 1
        syncTask?.cancel()
        syncTask = nil
        verifiedOwnerID = ownerID
        boundOwnerID = nil
        serverEntitlement = nil
        hasRevenueCatEntitlement = false

        // Preserve a login-first purchase intent only across nil -> verified; a real owner
        // switch or sign-out must never carry the previous owner's intent forward.
        if previousOwner != nil {
            pendingContext = nil
        }

        guard let ownerID else {
            // Sign-out gates the old owner and clears caches without calling anonymous logOut.
            syncState = .unbound
            return
        }
        bind(ownerID)
    }

    /// Records a StoreKit 2 purchase the app verified, then syncs RevenueCat so the transaction
    /// is associated with the owner that initiated it. The owner and generation are captured
    /// before the native purchase; a stale result after an owner switch is discarded, never bound
    /// to a different owner. Idempotent; a network failure leaves the transaction in
    /// `Transaction.currentEntitlements` for the next sync backfill.
    func recordVerifiedPurchase(
        _ result: Product.PurchaseResult,
        ownerID: UUID,
        generation: Int
    ) async {
        guard isCommerciallyEnabled, let client else {
            return
        }
        // The SDK must still be bound to the initiating owner; otherwise the result is stale.
        guard boundOwnerID == ownerID, ownerGeneration == generation else {
            return
        }
        syncState = .syncing
        do {
            _ = try await client.recordPurchase(result)
            guard self.ownerGeneration == generation, self.boundOwnerID == ownerID else {
                return
            }
            let snapshot = try await client.syncPurchases()
            guard self.ownerGeneration == generation, self.boundOwnerID == ownerID else {
                return
            }
            hasRevenueCatEntitlement = snapshot.hasActiveEntitlement
            syncState = .bound
            await refreshServerEntitlement(for: ownerID, generation: generation)
        } catch RecipeRevenueCatClientError.belongsToOtherOwner {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .conflict
        } catch {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .failed
        }
    }

    /// Explicit user restore. Idempotent for the same owner; a receipt bound to another owner
    /// surfaces `.conflict` and is never silently transferred.
    func restore(ownerID: UUID, generation: Int) async {
        guard isCommerciallyEnabled, let client else {
            return
        }
        guard boundOwnerID == ownerID, ownerGeneration == generation else {
            return
        }
        syncState = .syncing
        do {
            let snapshot = try await client.restorePurchases()
            guard self.ownerGeneration == generation, self.boundOwnerID == ownerID else {
                return
            }
            hasRevenueCatEntitlement = snapshot.hasActiveEntitlement
            syncState = .bound
            await refreshServerEntitlement(for: ownerID, generation: generation)
        } catch RecipeRevenueCatClientError.belongsToOtherOwner {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .conflict
        } catch {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .failed
        }
    }

    /// Bounded refresh: re-reads RevenueCat and the server snapshot for the bound owner. Callable
    /// after a webhook delay to retry without re-prompting a purchase.
    func sync(ownerID: UUID) async {
        guard isCommerciallyEnabled, let client, boundOwnerID == ownerID else {
            return
        }
        let generation = ownerGeneration
        syncState = .syncing
        do {
            let snapshot = try await client.syncPurchases()
            guard self.ownerGeneration == generation, self.boundOwnerID == ownerID else {
                return
            }
            hasRevenueCatEntitlement = snapshot.hasActiveEntitlement
            syncState = .bound
            await refreshServerEntitlement(for: ownerID, generation: generation)
        } catch RecipeRevenueCatClientError.belongsToOtherOwner {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .conflict
        } catch {
            guard self.ownerGeneration == generation else {
                return
            }
            syncState = .failed
        }
    }

    /// Preserves a purchase intent when a commercial purchase is attempted before a verified
    /// owner is bound, so login can replay it instead of buying anonymously.
    func preservePendingPurchase(productID: String) {
        guard isCommerciallyEnabled else {
            return
        }
        pendingContext = RecipePurchasePendingContext(productID: productID, requestedAt: Date())
    }

    func clearPendingPurchase() {
        pendingContext = nil
    }

    /// Marks the current binding as carrying only a local legacy entitlement with no trusted
    /// server owner, so the account UI can list it for linking instead of self-granting quota.
    func markNeedsAccountLink() {
        guard isCommerciallyEnabled, boundOwnerID != nil else {
            return
        }
        syncState = .needsAccountLink
    }

    /// The canonical lowercase App User ID the webhook and server DTO both use for an owner.
    func appUserID(for ownerID: UUID) -> String {
        ownerID.uuidString.lowercased()
    }

    // MARK: - Private

    private func bind(_ ownerID: UUID) {
        let generation = ownerGeneration
        syncState = .binding
        syncTask = Task { [weak self] in
            guard let self, let client = self.client else {
                return
            }
            do {
                let snapshot = try await client.logIn(appUserID: self.appUserID(for: ownerID))
                guard self.ownerGeneration == generation else {
                    return
                }
                self.boundOwnerID = ownerID
                self.hasRevenueCatEntitlement = snapshot.hasActiveEntitlement
                self.syncState = .bound
                await self.refreshServerEntitlement(for: ownerID, generation: generation)
            } catch {
                guard self.ownerGeneration == generation else {
                    return
                }
                self.syncState = .failed
            }
        }
    }

    /// Reads the server snapshot through the injected port and keeps only a matching-owner result.
    /// A failed read never corrupts the local binding (the route is unavailable until DEV-427).
    private func refreshServerEntitlement(for ownerID: UUID, generation: Int) async {
        do {
            let response = try await accessReader.accessSnapshot()
            guard self.ownerGeneration == generation else {
                return
            }
            guard response.ownerID == appUserID(for: ownerID) else {
                serverEntitlement = nil
                return
            }
            serverEntitlement = response.entitlement
        } catch {
            // Keep the last known snapshot; an unavailable server read must not fail the binding.
        }
    }
}

// MARK: - Real RevenueCat adapter

/// Real RevenueCat adapter pinned to purchases-ios 5.95.0 in observer mode (`myApp` completes
/// purchases) with StoreKit 2. Configured only with a verified Supabase UUID; never anonymous.
actor RecipeRevenueCatAdapter: RecipeRevenueCatClient {
    private let apiKey: String
    private var configured = false

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func logIn(appUserID: String) async throws -> RecipeCustomerSnapshot {
        configureIfNeeded(appUserID: appUserID)
        do {
            let (info, _) = try await Purchases.shared.logIn(appUserID)
            return snapshot(from: info)
        } catch {
            throw mapped(error)
        }
    }

    func syncPurchases() async throws -> RecipeCustomerSnapshot {
        do {
            return snapshot(from: try await Purchases.shared.syncPurchases())
        } catch {
            throw mapped(error)
        }
    }

    func restorePurchases() async throws -> RecipeCustomerSnapshot {
        do {
            return snapshot(from: try await Purchases.shared.restorePurchases())
        } catch {
            throw mapped(error)
        }
    }

    func recordPurchase(_ result: Product.PurchaseResult) async throws -> Bool {
        do {
            return try await Purchases.shared.recordPurchase(result) != nil
        } catch {
            throw mapped(error)
        }
    }

    /// Configures the SDK exactly once, always with a verified App User ID so there is never an
    /// anonymous identity. `logIn` re-identifies on later owner changes.
    private func configureIfNeeded(appUserID: String) {
        guard !configured else {
            return
        }
        let configuration = Configuration.builder(withAPIKey: apiKey)
            .with(appUserID: appUserID)
            .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
            .build()
        Purchases.configure(with: configuration)
        configured = true
    }

    private func snapshot(from info: CustomerInfo) -> RecipeCustomerSnapshot {
        RecipeCustomerSnapshot(hasActiveEntitlement: !info.activeSubscriptions.isEmpty)
    }

    private func mapped(_ error: Error) -> RecipeRevenueCatClientError {
        let conflicts: Set<Int> = [
            RevenueCat.ErrorCode.receiptAlreadyInUseError.rawValue,
            RevenueCat.ErrorCode.receiptInUseByOtherSubscriberError.rawValue,
            RevenueCat.ErrorCode.purchaseBelongsToOtherUser.rawValue,
        ]
        // The async SDK methods throw ErrorCode directly.
        if let code = error as? RevenueCat.ErrorCode {
            return conflicts.contains(code.rawValue) ? .belongsToOtherOwner : .unavailable
        }
        // Wrapped SDK errors bridge to NSError; match the RevenueCat domain and code together.
        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
            conflicts.contains(nsError.code)
        {
            return .belongsToOtherOwner
        }
        return .unavailable
    }
}

// MARK: - Production wiring

extension RecipePurchaseAccountBridge {
    /// Production bridge. The SDK adapter exists only when the commercial stage and a public SDK
    /// key are both present; otherwise the bridge stays fully dormant (freeTest default). The
    /// access reader is injectable so DEV-427 can supply the real `/recipe-access` HTTP client.
    static func makeProduction(
        accessReader: RecipeAccessReading = RecipeAccessReaderClient()
    ) -> RecipePurchaseAccountBridge {
        let stage = RecipeMonetization.stage
        let apiKey = Self.configuredAPIKey
        let client: RecipeRevenueCatClient? = {
            guard stage == .commercial, let apiKey, !apiKey.isEmpty, !apiKey.hasPrefix("$(")
            else {
                return nil
            }
            return RecipeRevenueCatAdapter(apiKey: apiKey)
        }()
        return RecipePurchaseAccountBridge(
            client: client,
            accessReader: accessReader,
            stage: stage,
            apiKey: apiKey
        )
    }

    /// Public RevenueCat SDK key from the app bundle. Absent/placeholder keys keep the bridge
    /// dormant; the value is never logged.
    static var configuredAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
