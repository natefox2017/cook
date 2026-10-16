// Developer: gengyun
// Purpose: Composes the unified commercial services (access, upgrade, import usage) and binds them to the verified owner.

import Foundation
import Observation
import RecipeCore

/// Single composition point that instantiates the unified commercial services and keeps them bound
/// to the verified Supabase owner. Features consume capability gating through `RecipeAccessStore`
/// and upgrades through `UpgradeRouter`; import quota flows go through `RecipeImportUsageBridge`.
/// The draft review-to-save flow is owned by the self-contained `RecipeDraftService`, not here. In
/// the freeTest build everything stays dormant and no StoreKit/usage network call is made.
@MainActor
@Observable
final class RecipeCommerceComposition {
    let accessStore: RecipeAccessStore
    let upgradeRouter: UpgradeRouter

    /// Import quota reserve/settle/recover bridge. `nil` only when the per-owner usage store
    /// directory could not be created (disk failure); import quota then remains unavailable.
    let importUsage: RecipeImportUsageBridge?

    /// DEV-78 media-import save client (reserve/finalize/release the media_import unit). Stateless
    /// HTTP client that verifies the bound session owner per call; it is not exposed directly — the
    /// `mediaBundlePort` accessor is the only integration point.
    private let mediaSave: RecipeMediaSaveService

    /// The owner the composition is currently bound to. Mirrors the access store binding so the
    /// settle port can gate on a matched owner without reaching into `RecipeAccessStore` internals.
    @ObservationIgnored private var boundOwnerID: String?

    /// Monotonic generation bumped only when the bound owner changes (rebind/sign-out/sign-in), so a
    /// caller that captured an older snapshot can detect a mid-flight account switch.
    @ObservationIgnored private var ownerGeneration = 0

    /// An immutable snapshot of the bound owner plus its monotonic generation. Callers capture this
    /// before awaited bridge work and re-compare after the await: a changed generation means the
    /// owner/session was rebound, so the stale result must not be persisted or acknowledged.
    struct ImportUsageContext: Equatable, Sendable {
        let ownerID: UUID?
        let generation: Int
    }

    /// Live bound-owner + generation snapshot for the Detail owner's saveSelected fence.
    var importUsageContext: ImportUsageContext {
        ImportUsageContext(
            ownerID: boundOwnerID.flatMap(UUID.init(uuidString:)),
            generation: ownerGeneration
        )
    }

    init() {
        let access = RecipeAccessStore()
        self.accessStore = access
        self.upgradeRouter = UpgradeRouter(access: access)

        let mediaSave = RecipeMediaSaveService()
        self.mediaSave = mediaSave

        let usageClient = RecipeImportUsageService()
        if let store = try? RecipeImportUsageStore.default() {
            self.importUsage = RecipeImportUsageBridge(client: usageClient, store: store)
        } else {
            self.importUsage = nil
        }
    }

    /// Re-binds commercial services to the current verified owner across sign-in, sign-out, and
    /// account switch. A different owner clears the access snapshot and upgrade state so stale
    /// data from the previous account never surfaces in the new one.
    func ownerDidChange(to ownerID: UUID?) {
        let nextBound = ownerID?.uuidString.lowercased()
        if nextBound != boundOwnerID {
            boundOwnerID = nextBound
            ownerGeneration &+= 1
        }
        if let ownerID {
            accessStore.bind(ownerID: ownerID.uuidString.lowercased())
        } else {
            accessStore.unbind()
        }
        upgradeRouter.reset()
    }

    /// Resumes pending import reservations (`.reserving`/`.awaitingUpgrade`) for the owner after an
    /// upgrade or a relaunch. In freeTest it returns immediately without touching the network or the
    /// persisted pending records; only an enabled commercial stage reopens the recovery path.
    func recoverPendingImportUsage(ownerID: UUID) async {
        guard RecipeMonetization.isEnabled else {
            return
        }
        guard let importUsage else {
            return
        }
        _ = try? await importUsage.recover(ownerID: ownerID)
        // DEV-78 media bundles recover atomically (grouped by job, idempotent REPLAY + reserved media
        // finalize unknown-result replay). `mediaBundlePort` is nil in freeTest or without a bound
        // owner/store (fail-closed), so the freeTest save stays byte-equivalent and unmetered.
        if let mediaBundlePort {
            _ = try? await mediaBundlePort.recover(ownerID: ownerID)
        }
    }

    /// The commercial settle port for the normal single-recipe import save. Non-nil only when
    /// commercial is enabled and a verified owner is bound; `nil` keeps the freeTest save
    /// byte-equivalent and unmetered. The adapter's bridge re-verifies the session owner on every
    /// reserve/finalize/acknowledge, so a stale account callback never settles for a previous owner.
    var importSettlePort: (any RecipeImportUsageSettling)? {
        guard RecipeMonetization.isEnabled, let importUsage, boundOwnerID != nil else {
            return nil
        }
        return RecipeImportUsageSettleAdapter(bridge: importUsage)
    }

    /// The DEV-78 media bundle port for the Detail owner's saveSelected. `nil` in freeTest and when
    /// no verified owner is bound or the per-owner usage store is unavailable (fail-closed); only a
    /// commercial stage with a bound owner exposes the media reserve/finalize/release port. The port
    /// reuses the existing import usage store and re-verifies the bound owner/generation via the
    /// `importUsageContext` fence on every call.
    var mediaBundlePort: RecipeMediaBundlePort? {
        guard RecipeMonetization.isEnabled, boundOwnerID != nil, let importUsage else {
            return nil
        }
        return RecipeMediaBundlePort(client: mediaSave, store: importUsage.store)
    }

    /// Minimal PDF export capability entry for DEV-440's Profile. Returns `true` when the export
    /// may proceed; otherwise presents the upgrade paywall and returns `false`.
    func requestPDFExport() -> Bool {
        guard upgradeRouter.requiresUpgrade(.pdfExport) else {
            return true
        }
        upgradeRouter.showUpgrade(capability: .pdfExport, pendingID: "pdf-export")
        return false
    }
}
