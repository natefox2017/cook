// Developer: gengyun
// Purpose: Synchronize validated Cook snapshots through Supabase with revision checks.

import Foundation
import Network
import Observation
import CookCore
import Supabase

struct CloudSnapshotEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let payload: CookLibrarySnapshot
    let clientUpdatedAt: Date
    let revision: Int64
    let serverUpdatedAt: Date?
}

enum CloudSyncState: Equatable, Sendable {
    case localOnly
    case syncing
    case synced(Date)
    case conflict
    case error(String)
}

struct CloudLibraryCounts: Equatable, Sendable {
    let recipes: Int
    let groceries: Int
    let plannedMeals: Int

    var hasContent: Bool { recipes > 0 || groceries > 0 || plannedMeals > 0 }

    init(_ snapshot: CookLibrarySnapshot) {
        recipes = snapshot.recipes.count
        groceries = snapshot.groceries.count
        plannedMeals = snapshot.mealPlan.count
    }
}

enum CloudSyncCoordinatorState: Equatable, Sendable {
    case localOnly
    case syncing
    case synced(Date)
    case initialChoice(local: CloudLibraryCounts, cloud: CloudLibraryCounts?)
    case conflicts([LibraryMergeConflict])
    case error(String)
}

enum InitialCloudSyncChoice: Sendable {
    case mergeLibraries
    case keepLocalUntilLater
}

enum CloudSyncMode: String, CaseIterable, Sendable {
    case automatic = "Automatic"
    case wifiOnly = "Wi-Fi Only"
    case manual = "Manually"
}

/// Protocol boundary used by the UI/store. The production implementation is
/// backed by Supabase Auth + an owner-scoped user_snapshots row.
protocol CookCloudSyncing: Sendable {
    func upload(
        _ snapshot: CloudSnapshotEnvelope,
        expectedRevision: Int64,
        for userID: UUID
    ) async throws -> CloudSnapshotEnvelope
    func download(for userID: UUID) async throws -> CloudSnapshotEnvelope?
    func deleteAccountAndCloudData() async throws
}

/// Used until the Supabase project is active/configured. It never pretends a
/// cloud write succeeded.
struct UnconfiguredCloudSync: CookCloudSyncing {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "Cook cloud sync is not configured in this build." }
    }
    func upload(
        _ snapshot: CloudSnapshotEnvelope,
        expectedRevision: Int64,
        for userID: UUID
    ) async throws -> CloudSnapshotEnvelope {
        throw NotConfigured()
    }
    func download(for userID: UUID) async throws -> CloudSnapshotEnvelope? {
        _ = userID
        throw NotConfigured()
    }
    func deleteAccountAndCloudData() async throws { throw NotConfigured() }
}

enum CookCloudSyncError: LocalizedError {
    case unsupportedPayload
    case revisionConflict
    case missingSaveResult

    var errorDescription: String? {
        switch self {
        case .unsupportedPayload:
            "This library snapshot cannot be sent to cloud sync."
        case .revisionConflict:
            "This library changed on another device. Download the latest version before retrying."
        case .missingSaveResult:
            "Cloud sync did not confirm that the snapshot was saved."
        }
    }
}

/// Supabase implementation uses the signed-in user's JWT and the database's RLS.
struct SupabaseCloudSync: CookCloudSyncing {
    private let client: SupabaseClient

    init(client: SupabaseClient = CookSupabase.client) {
        self.client = client
    }

    func upload(
        _ snapshot: CloudSnapshotEnvelope,
        expectedRevision: Int64,
        for userID: UUID
    ) async throws -> CloudSnapshotEnvelope {
        let params = SaveSnapshotParameters(
            targetUserID: userID,
            expectedRevision: expectedRevision,
            schemaVersion: snapshot.schemaVersion,
            payload: snapshot.payload,
            clientUpdatedAt: ISO8601DateFormatter().string(from: snapshot.clientUpdatedAt)
        )
        let records: [RemoteSnapshot] = try await client
            .rpc("save_own_user_snapshot", params: params)
            .execute()
            .value

        guard let record = records.first else { throw CookCloudSyncError.revisionConflict }
        guard let serverUpdatedAt = Self.parseDate(record.updatedAt) else {
            throw CookCloudSyncError.unsupportedPayload
        }
        guard let clientUpdatedAt = Self.parseDate(record.clientUpdatedAt) else {
            throw CookCloudSyncError.unsupportedPayload
        }
        return CloudSnapshotEnvelope(
            schemaVersion: record.schemaVersion,
            payload: record.payload,
            clientUpdatedAt: clientUpdatedAt,
            revision: record.revision,
            serverUpdatedAt: serverUpdatedAt
        )
    }

    func download(for userID: UUID) async throws -> CloudSnapshotEnvelope? {
        let row: RemoteSnapshot? = try await client
            .from("user_snapshots")
            .select()
            .eq("user_id", value: userID.uuidString)
            .maybeSingle()
            .execute()
            .value
        guard let row else { return nil }

        guard let updatedAt = Self.parseDate(row.clientUpdatedAt) else {
            throw CookCloudSyncError.unsupportedPayload
        }
        guard let serverUpdatedAt = Self.parseDate(row.updatedAt) else {
            throw CookCloudSyncError.unsupportedPayload
        }
        return CloudSnapshotEnvelope(
            schemaVersion: row.schemaVersion,
            payload: row.payload,
            clientUpdatedAt: updatedAt,
            revision: row.revision,
            serverUpdatedAt: serverUpdatedAt
        )
    }

    func deleteAccountAndCloudData() async throws {
        try await client.functions.invoke("delete-account")
        // The edge function has already deleted the server identity. A local-only
        // sign-out clears its Keychain session without relying on that deleted user.
        try await client.auth.signOut(scope: .local)
    }

    private static func parseDate(_ value: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

}

/// Coordinates account changes, user-approved first sync, and revision-checked updates.
@Observable @MainActor
final class CloudSyncCoordinator {
    private(set) var state: CloudSyncCoordinatorState = .localOnly
    private(set) var lastSyncedAt: Date?
    private(set) var mode: CloudSyncMode

    @ObservationIgnored private let service: any CookCloudSyncing
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathQueue = DispatchQueue(label: "com.modelhub.cook.cloud-sync-path")
    @ObservationIgnored private var store: CookStore?
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var remoteSnapshot: CloudSnapshotEnvelope?
    @ObservationIgnored private var expectedRevision: Int64 = 0
    @ObservationIgnored private var lastExportedToken: UInt64 = 0
    @ObservationIgnored private var automaticSyncPaused = false
    @ObservationIgnored private var isOnWiFi = false
    @ObservationIgnored private var isSyncing = false

    init(service: any CookCloudSyncing = SupabaseCloudSync()) {
        self.service = service
        mode = CloudSyncMode(rawValue: UserDefaults.standard.string(forKey: "cook.sync.mode") ?? "Automatic") ?? .automatic
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnWiFi = path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnWiFi = isOnWiFi
                if isOnWiFi, self.mode == .wifiOnly { await self.syncLocalChangesIfAllowed() }
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func bind(store: CookStore, authState: CookAuthState) async {
        self.store = store
        await authenticationChanged(authState)
    }

    func authenticationChanged(_ authState: CookAuthState) async {
        switch authState {
        case .signedIn(let userID, _):
            guard accountID != userID else { return }
            accountID = userID
            remoteSnapshot = nil
            expectedRevision = 0
            automaticSyncPaused = false
            await loadAccountSnapshot(userID: userID)
        case .signedOut:
            accountID = nil
            remoteSnapshot = nil
            expectedRevision = 0
            automaticSyncPaused = false
            state = .localOnly
        case .loading, .authenticating, .needsEmailVerification, .passwordResetSent, .passwordRecovery:
            break
        case .error(let message):
            state = .error(message)
        }
    }

    func setMode(_ mode: CloudSyncMode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "cook.sync.mode")
        if mode != .manual { Task { await syncLocalChangesIfAllowed() } }
    }

    func localStoreChanged(token: UInt64) async {
        guard token != lastExportedToken else { return }
        await syncLocalChangesIfAllowed()
    }

    func chooseInitialSync(_ choice: InitialCloudSyncChoice) async {
        guard case .initialChoice = state, let store else { return }
        switch choice {
        case .keepLocalUntilLater:
            automaticSyncPaused = true
            state = .localOnly
        case .mergeLibraries:
            automaticSyncPaused = false
            do {
                if let remoteSnapshot {
                    let conflicts = try store.mergeCloudLibrary(with: remoteSnapshot.payload)
                    lastExportedToken = store.changeToken
                    guard conflicts.isEmpty else {
                        state = .conflicts(conflicts)
                        return
                    }
                }
                await uploadLocalSnapshot()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func resolveConflicts(with choices: [LibraryMergeChoice]) async {
        guard let store, let remoteSnapshot else { return }
        do {
            let conflicts = try store.mergeCloudLibrary(with: remoteSnapshot.payload, choices: choices)
            lastExportedToken = store.changeToken
            guard conflicts.isEmpty else {
                state = .conflicts(conflicts)
                return
            }
            await uploadLocalSnapshot()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard accountID != nil else { state = .localOnly; return }
        automaticSyncPaused = false
        if case .initialChoice = state { return }
        if case .conflicts = state { return }
        await uploadLocalSnapshot()
    }

    func deleteAccountAndCloudData() async throws {
        try await service.deleteAccountAndCloudData()
        accountID = nil
        remoteSnapshot = nil
        expectedRevision = 0
        automaticSyncPaused = false
        state = .localOnly
    }

    private func loadAccountSnapshot(userID: UUID) async {
        guard let store else { return }
        state = .syncing
        do {
            let remote = try await service.download(for: userID)
            guard accountID == userID else { return }
            remoteSnapshot = remote
            expectedRevision = remote?.revision ?? 0
            let local = try store.exportCloudSnapshot()
            if let remote {
                if store.hasUserData {
                    state = .initialChoice(local: CloudLibraryCounts(local), cloud: CloudLibraryCounts(remote.payload))
                } else {
                    try store.replaceLibrary(with: remote.payload)
                    lastExportedToken = store.changeToken
                    markSynced(remote.serverUpdatedAt)
                }
            } else if store.hasUserData || !(local.deletedEntities ?? []).isEmpty {
                state = .initialChoice(local: CloudLibraryCounts(local), cloud: nil)
            } else {
                lastExportedToken = store.changeToken
                state = .localOnly
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func syncLocalChangesIfAllowed() async {
        guard accountID != nil, let store, store.changeToken != lastExportedToken,
              !automaticSyncPaused,
              !isSyncing, canSyncAutomatically else { return }
        if case .initialChoice = state { return }
        if case .conflicts = state { return }
        await uploadLocalSnapshot()
    }

    private var canSyncAutomatically: Bool {
        switch mode {
        case .automatic: true
        case .wifiOnly: isOnWiFi
        case .manual: false
        }
    }

    private func uploadLocalSnapshot() async {
        guard let store, let accountID else { return }
        guard !isSyncing else { return }
        do {
            let payload = try store.exportCloudSnapshot()
            if !store.hasUserData && (payload.deletedEntities ?? []).isEmpty && expectedRevision == 0 {
                state = .localOnly
                return
            }
            isSyncing = true
            state = .syncing
            let submittedToken = store.changeToken
            var followUpSyncNeeded = false
            defer {
                isSyncing = false
                if followUpSyncNeeded {
                    Task { @MainActor in await self.syncLocalChangesIfAllowed() }
                }
            }
            let pending = CloudSnapshotEnvelope(
                schemaVersion: payload.version,
                payload: payload,
                clientUpdatedAt: .now,
                revision: expectedRevision,
                serverUpdatedAt: nil
            )
            do {
                let saved = try await service.upload(pending, expectedRevision: expectedRevision, for: accountID)
                guard self.accountID == accountID else { return }
                remoteSnapshot = saved
                expectedRevision = saved.revision
                lastExportedToken = submittedToken
                markSynced(saved.serverUpdatedAt)
                followUpSyncNeeded = store.changeToken != submittedToken
            } catch CookCloudSyncError.revisionConflict {
                guard self.accountID == accountID else { return }
                let latest = try await service.download(for: accountID)
                guard self.accountID == accountID else { return }
                remoteSnapshot = latest
                expectedRevision = latest?.revision ?? 0
                if let latest {
                    let conflicts = try store.mergeCloudLibrary(with: latest.payload)
                    lastExportedToken = submittedToken
                    if conflicts.isEmpty {
                        state = .localOnly
                        followUpSyncNeeded = true
                    } else {
                        state = .conflicts(conflicts)
                    }
                } else {
                    state = .error("Cloud sync changed while this device was saving. Try again.")
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func markSynced(_ date: Date?) {
        let timestamp = date ?? .now
        lastSyncedAt = timestamp
        if let accountID {
            UserDefaults.standard.set(timestamp, forKey: "cook.sync.lastAt.\(accountID.uuidString)")
        }
        state = .synced(timestamp)
    }
}

private struct SaveSnapshotParameters: Encodable {
    let targetUserID: UUID
    let expectedRevision: Int64
    let schemaVersion: Int
    let payload: CookLibrarySnapshot
    let clientUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case targetUserID = "target_user_id"
        case expectedRevision = "expected_revision"
        case schemaVersion = "snapshot_schema_version"
        case payload = "snapshot_payload"
        case clientUpdatedAt = "snapshot_client_updated_at"
    }
}

private struct RemoteSnapshot: Decodable {
    let schemaVersion: Int
    let payload: CookLibrarySnapshot
    let clientUpdatedAt: String
    let revision: Int64
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case payload
        case clientUpdatedAt = "client_updated_at"
        case revision
        case updatedAt = "updated_at"
    }
}
