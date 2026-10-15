// Developer: gengyun
// Purpose: Routes capability-triggered upgrade requests and enforces once-only operation recovery after a successful upgrade.

import Foundation
import Observation
import RecipeCore

/// Unified upgrade entry point. Every feature presents an upgrade through this router and
/// consumes capability access through `RecipeAccessStore`, instead of scattering payment checks.
@MainActor
@Observable
final class UpgradeRouter {

    /// A presented upgrade request. The stable pending id resumes the original action after a
    /// successful upgrade.
    struct Request: Identifiable, Equatable {
        let id: UUID
        let capability: RecipeCapability
        let pendingID: String
    }

    private(set) var presented: Request?

    @ObservationIgnored private let access: RecipeAccessStore

    /// Operations already recovered after a successful upgrade. A repeated callback never re-runs.
    @ObservationIgnored private var recoveredOperationIDs: Set<String> = []

    /// Operations canceled by the user. They stay pending and are never unlocked by cancellation.
    @ObservationIgnored private var canceledOperationIDs: Set<String> = []

    init(access: RecipeAccessStore) {
        self.access = access
    }

    /// Whether the capability currently needs an upgrade: a commercial build with a known access
    /// snapshot that reports the capability as not usable.
    func requiresUpgrade(_ capability: RecipeCapability) -> Bool {
        guard access.isEnabled, access.hasSnapshot else {
            return false
        }
        return !access.canUse(capability)
    }

    /// Unified upgrade entry point. In a `freeTest` build nothing is presented.
    func showUpgrade(capability: RecipeCapability, pendingID: String) {
        guard access.isEnabled else {
            return
        }
        presented = Request(id: UUID(), capability: capability, pendingID: pendingID)
    }

    func dismiss() {
        presented = nil
    }

    /// Recovers a pending operation exactly once after the server confirms an active entitlement.
    /// Returns `true` only the first time a given operation is recovered; repeated callbacks are
    /// ignored so the original receipt/proposal never executes twice.
    @discardableResult
    func recover(pendingID: String) -> Bool {
        guard !recoveredOperationIDs.contains(pendingID) else {
            return false
        }
        recoveredOperationIDs.insert(pendingID)
        return true
    }

    /// Cancels a pending operation. It stays pending (never unlocked); only a later successful
    /// upgrade and `recover` resumes it.
    func cancel(pendingID: String) {
        canceledOperationIDs.insert(pendingID)
    }

    /// Whether the operation was canceled and remains pending.
    func isCanceled(_ pendingID: String) -> Bool {
        canceledOperationIDs.contains(pendingID)
    }

    /// Clears presentation and recovery state on owner switch / sign-out.
    func reset() {
        presented = nil
        recoveredOperationIDs.removeAll()
        canceledOperationIDs.removeAll()
    }
}
