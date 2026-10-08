// Developer: gengyun
// Purpose: Defines RecipePouch cloud synchronization boundaries and explicit unconfigured behavior.

import Foundation

struct CloudSnapshotEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let payload: Data
    let clientUpdatedAt: Date
}

enum CloudSyncState: Equatable, Sendable {
    case localOnly
    case syncing
    case synced(Date)
    case conflict
    case error(String)
}

/// Protocol boundary used by the UI/store. The production implementation is
/// backed by Supabase Auth + an owner-scoped user_snapshots row.
protocol RecipeCloudSyncing: Sendable {
    func upload(_ snapshot: CloudSnapshotEnvelope) async throws
    func download() async throws -> CloudSnapshotEnvelope?
    func deleteAccountAndCloudData() async throws
}

/// Used until the Supabase project is active/configured. It never pretends a
/// cloud write succeeded.
struct UnconfiguredCloudSync: RecipeCloudSyncing {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "RecipePouch cloud sync is not configured in this build." }
    }
    func upload(_ snapshot: CloudSnapshotEnvelope) async throws { throw NotConfigured() }
    func download() async throws -> CloudSnapshotEnvelope? { throw NotConfigured() }
    func deleteAccountAndCloudData() async throws { throw NotConfigured() }
}
