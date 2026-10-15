// Developer: gengyun
// Purpose: Owns the unified commercial access snapshot: release stage, owner binding, entitlement and per-capability quota state.

import Foundation
import Observation
import RecipeCore

/// Single source of truth for a signed-in owner's commercial access. Every feature consumes
/// capability gating and upgrade recovery through this store and `UpgradeRouter`, so call sites
/// never scatter `if isPro` checks. The server response is authoritative; a response whose owner
/// differs from the bound session owner is always rejected.
@MainActor
@Observable
final class RecipeAccessStore {

    /// The active release stage resolves from the build configuration. `freeTest` is the safe
    /// default and keeps StoreKit networking and purchase entry points off.
    let stage: RecipeReleaseStage

    /// Whether commercial monetization is active for this build.
    var isEnabled: Bool { stage == .commercial }

    /// The most recently applied `/recipe-access` snapshot, or `nil` when unbound or unavailable.
    private(set) var snapshot: RecipeAccessResponse?

    /// The session owner this store is bound to. Responses from any other owner are rejected.
    @ObservationIgnored private var boundOwnerID: String?

    init(stage: RecipeReleaseStage = RecipeAccessStore.resolveStage()) {
        self.stage = stage
    }

    // MARK: Stage resolution

    /// Resolves the active stage from the process environment (deterministic UI-test override),
    /// then the main bundle's `RecipeReleaseStage` build configuration, defaulting to `freeTest`.
    static func resolveStage() -> RecipeReleaseStage {
        if let raw = ProcessInfo.processInfo.environment["RECIPE_RELEASE_STAGE"],
            let stage = RecipeReleaseStage(rawValue: raw)
        {
            return stage
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RecipeReleaseStage") as? String,
            let stage = RecipeReleaseStage(rawValue: raw)
        {
            return stage
        }
        return .freeTest
    }

    // MARK: Owner binding

    /// Binds the store to a signed-in owner. Binding a different owner clears the previous
    /// snapshot so stale data from the old account never surfaces in the new one.
    func bind(ownerID: String) {
        guard boundOwnerID != ownerID else {
            return
        }
        boundOwnerID = ownerID
        snapshot = nil
    }

    /// Clears the binding and snapshot (sign-out / session teardown).
    func unbind() {
        boundOwnerID = nil
        snapshot = nil
    }

    /// Applies a decoded `/recipe-access` response. Rejects (returns `false`) any response whose
    /// owner differs from the bound owner, or when no owner is bound, so a stale owner response
    /// never enters the current account's state.
    @discardableResult
    func apply(_ response: RecipeAccessResponse) -> Bool {
        guard let owner = boundOwnerID, response.ownerID == owner else {
            return false
        }
        snapshot = response
        return true
    }

    var hasSnapshot: Bool { snapshot != nil }

    // MARK: Entitlement

    var entitlementStatus: RecipeEntitlementStatus? {
        snapshot?.entitlement.status
    }

    var hasPremium: Bool {
        snapshot?.entitlement.status == .premium
    }

    var entitlementExpired: Bool {
        snapshot?.entitlement.status == .expired
    }

    // MARK: Capability access

    func access(for capability: RecipeCapability) -> RecipeCapabilityAccess? {
        snapshot?.capabilities.first { $0.id == capability }
    }

    func isEntitled(to capability: RecipeCapability) -> Bool {
        access(for: capability)?.entitled == true
    }

    func remaining(for capability: RecipeCapability) -> Int? {
        access(for: capability)?.quota?.remaining
    }

    func resetAt(for capability: RecipeCapability) -> Date? {
        guard let raw = access(for: capability)?.quota?.resetAt else {
            return nil
        }
        return Self.parseTimestamp(raw)
    }

    /// Whether a capability is currently usable. The server snapshot is authoritative: the
    /// capability must be entitled, and a metered capability additionally needs positive
    /// remaining quota. Unmetered premium capabilities (`quota == nil`) grant no numeric promise.
    func canUse(_ capability: RecipeCapability) -> Bool {
        guard let access = access(for: capability), access.entitled else {
            return false
        }
        guard let quota = access.quota else {
            return true
        }
        return quota.remaining > 0
    }

    // MARK: Timestamp parsing

    /// Parses a contract ISO 8601 UTC timestamp (optional 1–3 digit fraction) for display.
    static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: raw)
    }
}
