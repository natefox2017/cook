// Developer: gengyun
// Purpose: Composes the unified commercial services (access, upgrade, usage, draft commit) and binds them to the verified owner.

import Foundation
import Observation
import RecipeCore

/// Single composition point that instantiates the unified commercial services and keeps them bound
/// to the verified Supabase owner. Features consume capability gating through `RecipeAccessStore`
/// and upgrades through `UpgradeRouter`; import quota flows go through `RecipeImportUsageBridge`;
/// the draft save/recovery goes through `RecipeDraftCommitCoordinator`. In the freeTest build
/// everything stays dormant and no StoreKit/usage network call is made.
@MainActor
@Observable
final class RecipeCommerceComposition {
    let accessStore: RecipeAccessStore
    let upgradeRouter: UpgradeRouter

    /// Import quota reserve/settle/recover bridge. `nil` only when the per-owner usage store
    /// directory could not be created (disk failure); import quota then remains unavailable.
    let importUsage: RecipeImportUsageBridge?

    /// Draft commit handoff. `nil` only when the store writer is not yet bound; the draft service
    /// then falls back to persisting a pending commit instead of settling inline.
    let draftCommitCoordinator: RecipeDraftCommitCoordinator?

    /// The app-level composer adapter (DEV-428): composes the accepted terminal `.proposal`
    /// suggestions onto the immutable session context and fails closed on unresolved fields.
    static let draftComposer: RecipeDraftRecipeComposer = { session, suggestions, receipt, ownerID in
        try RecipeDraftRecipeComposerAdapter.compose(
            session: session,
            suggestions: suggestions,
            receipt: receipt,
            ownerID: ownerID
        )
    }

    init(
        writer: RecipeFinalizedRecipeWriter? = nil,
        sessionLoader: RecipeDraftSessionLoader? = nil
    ) {
        let access = RecipeAccessStore()
        self.accessStore = access
        self.upgradeRouter = UpgradeRouter(access: access)

        let usageClient = RecipeUsageService()
        if let store = try? RecipeImportUsageStore.default() {
            self.importUsage = RecipeImportUsageBridge(client: usageClient, store: store)
        } else {
            self.importUsage = nil
        }

        if let writer {
            self.draftCommitCoordinator = RecipeDraftCommitCoordinator(
                usage: usageClient,
                composer: Self.draftComposer,
                writer: writer,
                sessionLoader: sessionLoader
            )
        } else {
            self.draftCommitCoordinator = nil
        }
    }

    /// Re-binds commercial services to the current verified owner across sign-in, sign-out, and
    /// account switch. A different owner clears the access snapshot and upgrade state so stale
    /// data from the previous account never surfaces in the new one.
    func ownerDidChange(to ownerID: UUID?) {
        if let ownerID {
            accessStore.bind(ownerID: ownerID.uuidString.lowercased())
        } else {
            accessStore.unbind()
        }
        upgradeRouter.reset()
    }

    /// Resumes pending import reservations (`.reserving`/`.awaitingUpgrade`) for the owner after an
    /// upgrade or a relaunch. Returns immediately when the usage store is unavailable.
    func recoverPendingImportUsage(ownerID: UUID) async {
        guard let importUsage else {
            return
        }
        _ = try? await importUsage.recover(ownerID: ownerID)
    }

    /// Re-runs the still-owed part of a pending draft commit (finalize/write/ack) for the owner.
    /// No-op until the draft commit coordinator and its session loader are wired.
    func recoverPendingDraftSettlements(ownerID: UUID) async {
        await draftCommitCoordinator?.recoverPendingSettlements(ownerID: ownerID)
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
