// Developer: gengyun
// Purpose: Synchronizes validated RecipePouch snapshots through Supabase with revision checks.

import Foundation
import Network
import Observation
import RecipeCore
import Supabase

struct CloudSnapshotEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let payload: RecipeLibrarySnapshot
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

    init(_ snapshot: RecipeLibrarySnapshot) {
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

enum CloudSyncMode: String, CaseIterable, Sendable, Hashable {
    case automatic = "Automatic"
    case wifiOnly = "Wi-Fi Only"
    case manual = "Manually"
}

/// Protocol boundary used by the UI/store. The production implementation is
/// backed by Supabase Auth + an owner-scoped user_snapshots row.
protocol RecipeCloudSyncing: Sendable {
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
struct UnconfiguredCloudSync: RecipeCloudSyncing {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? {
            String(localized: "RecipePouch cloud sync is not configured in this build.")
        }
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

enum RecipeCloudSyncError: LocalizedError {
    case unsupportedPayload
    case revisionConflict
    case missingSaveResult

    var errorDescription: String? {
        switch self {
        case .unsupportedPayload:
            String(localized: "This library snapshot cannot be sent to cloud sync.")
        case .revisionConflict:
            String(localized: "This library changed on another device. Download the latest version before retrying.")
        case .missingSaveResult:
            String(localized: "Cloud sync did not confirm that the snapshot was saved.")
        }
    }
}

/// Supabase implementation uses the signed-in user's JWT and the database's RLS.
struct SupabaseCloudSync: RecipeCloudSyncing {
    private let client: SupabaseClient

    init(client: SupabaseClient = RecipeSupabase.client) {
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

        guard let record = records.first else { throw RecipeCloudSyncError.revisionConflict }
        guard let serverUpdatedAt = Self.parseDate(record.updatedAt) else {
            throw RecipeCloudSyncError.unsupportedPayload
        }
        guard let clientUpdatedAt = Self.parseDate(record.clientUpdatedAt) else {
            throw RecipeCloudSyncError.unsupportedPayload
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
            throw RecipeCloudSyncError.unsupportedPayload
        }
        guard let serverUpdatedAt = Self.parseDate(row.updatedAt) else {
            throw RecipeCloudSyncError.unsupportedPayload
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

enum RecipeLocalResetError: LocalizedError {
    case requiresSignOut
    case syncInProgress
    case markerPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .requiresSignOut:
            String(localized: "Sign out of your RecipePouch account before deleting only this iPhone's data. Your cloud library will stay intact.")
        case .syncInProgress:
            String(localized: "A cloud sync operation is still finishing. Try deleting local data again after it stops.")
        case .markerPersistenceFailed:
            String(localized: "Could not securely persist the local erase barrier. Your library was not deleted. Check device storage and try again.")
        }
    }
}

/// Coordinates account changes, user-approved first sync, and revision-checked updates.
@Observable @MainActor
final class CloudSyncCoordinator {
    private(set) var state: CloudSyncCoordinatorState = .localOnly
    private(set) var lastSyncedAt: Date?
    private(set) var mode: CloudSyncMode

    @ObservationIgnored private let service: any RecipeCloudSyncing
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathQueue = DispatchQueue(label: "com.modelhub.recipe.cloud-sync-path")
    @ObservationIgnored private var store: RecipeStore?
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var remoteSnapshot: CloudSnapshotEnvelope?
    @ObservationIgnored private var mergeBaseSnapshot: RecipeLibrarySnapshot?
    @ObservationIgnored private var expectedRevision: Int64 = 0
    @ObservationIgnored private var lastExportedToken: UInt64 = 0
    @ObservationIgnored private var automaticSyncPaused = false
    @ObservationIgnored private var deferredInitialChoice:
        (local: CloudLibraryCounts, cloud: CloudLibraryCounts?)?
    @ObservationIgnored private var isOnWiFi = false
    @ObservationIgnored private var isSyncing = false

    init(service: any RecipeCloudSyncing = SupabaseCloudSync()) {
        self.service = service
        let defaults = UserDefaults.standard
        let storedMode = defaults.string(forKey: "recipe.sync.mode")
            ?? defaults.string(forKey: "cook.sync.mode")
            ?? CloudSyncMode.automatic.rawValue
        mode = CloudSyncMode(rawValue: storedMode) ?? .automatic
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

    /// Local-only erasure is allowed only after sign-out and after all
    /// pending network operations have completed.
    func verifyLocalOnlyResetAllowed() throws {
        guard accountID == nil else {
            throw RecipeLocalResetError.requiresSignOut
        }
        guard !isSyncing else {
            throw RecipeLocalResetError.syncInProgress
        }
    }

    /// Invalidate local sync identity BEFORE clearing the on-device library.
    /// The durable marker also prevents an old sync file that cannot be removed
    /// from being used as an upload base after relaunch.
    func prepareForLocalOnlyReset() throws {
        try verifyLocalOnlyResetAllowed()

        // This marker is an independently atomic file outside the Sync cache.
        // If persisting it fails, never touch the library contents.
        try RecipeLocalEraseMarker.persist(at: localEraseMarkerURL)

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "recipe.sync.localErasePending")
        for key in [
            "recipe.sync.localAccountID",
            "cook.sync.localAccountID",
            "recipe.sync.mode",
            "cook.sync.mode"
        ] {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("recipe.sync.lastAt.")
            || key.hasPrefix("cook.sync.lastAt.") {
            defaults.removeObject(forKey: key)
        }

        // Persist the invalidation before committing an empty library. If the
        // process stops after the following write, the next launch must not
        // reinterpret the empty snapshot as an offline cloud deletion.
        guard defaults.synchronize() else {
            throw RecipeLocalResetError.markerPersistenceFailed
        }

        mode = .automatic
        remoteSnapshot = nil
        mergeBaseSnapshot = nil
        expectedRevision = 0
        lastExportedToken = store?.changeToken ?? 0
        lastSyncedAt = nil
        automaticSyncPaused = false
        deferredInitialChoice = nil
        state = .localOnly
    }

    /// Best-effort filesystem cleanup performed AFTER sync lineage invalidation.
    /// An I/O error must be surfaced, but cannot restore the old sync identity.
    func removeLocalSyncCacheFilesAfterReset() throws {
        try verifyLocalOnlyResetAllowed()

        for directoryName in ["Recipe", "Cook"] {
            let syncDirectory = URL.applicationSupportDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
                .appendingPathComponent("Sync", isDirectory: true)
            if FileManager.default.fileExists(atPath: syncDirectory.path) {
                try FileManager.default.removeItem(at: syncDirectory)
            }
        }
    }

    func bind(store: RecipeStore, authState: RecipeAuthState) async {
        self.store = store
        await authenticationChanged(authState)
    }

    func authenticationChanged(_ authState: RecipeAuthState) async {
        switch authState {
        case .signedIn(let userID, _):
            if accountID == userID {
                await refreshFromCloudIfAllowed()
                await syncLocalChangesIfAllowed()
                return
            }
            accountID = userID
            remoteSnapshot = loadPersistedBase(for: userID)
            mergeBaseSnapshot = nil
            expectedRevision = remoteSnapshot?.revision ?? 0
            automaticSyncPaused = false
            deferredInitialChoice = nil
            lastSyncedAt = UserDefaults.standard.object(
                forKey: lastSyncedKey(for: userID)
            ) as? Date
            await loadAccountSnapshot(userID: userID)
            await syncLocalChangesIfAllowed()
        case .signedOut:
            accountID = nil
            remoteSnapshot = nil
            mergeBaseSnapshot = nil
            expectedRevision = 0
            automaticSyncPaused = false
            deferredInitialChoice = nil
            lastSyncedAt = nil
            state = .localOnly
        case .loading,
             .authenticating,
             .emailCodeSent,
             .needsEmailVerification,
             .passwordResetSent,
             .passwordRecovery:
            break
        case .error(let message):
            state = .error(message)
        }
    }

    func setMode(_ mode: CloudSyncMode) {
        self.mode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "recipe.sync.mode")
        if mode != .manual {
            Task {
                await refreshFromCloudIfAllowed()
                await syncLocalChangesIfAllowed()
            }
        }
    }

    func localStoreChanged(token: UInt64) async {
        guard token != lastExportedToken else { return }
        await syncLocalChangesIfAllowed()
    }

    func chooseInitialSync(_ choice: InitialCloudSyncChoice) async {
        guard case .initialChoice(let local, let cloud) = state,
              let store else {
            return
        }

        switch choice {
        case .keepLocalUntilLater:
            automaticSyncPaused = true
            deferredInitialChoice = (local, cloud)
            state = .localOnly

        case .mergeLibraries:
            automaticSyncPaused = false
            deferredInitialChoice = nil
            do {
                if let remoteSnapshot {
                    mergeBaseSnapshot = nil
                    let conflicts = try store.mergeCloudLibrary(
                        with: remoteSnapshot.payload
                    )
                    guard conflicts.isEmpty else {
                        state = .conflicts(conflicts)
                        return
                    }
                }
                await uploadLocalSnapshot(forceFollowUp: true)
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func resolveConflicts(with choices: [LibraryMergeChoice]) async {
        guard let store, let remoteSnapshot else { return }
        do {
            let conflicts = try store.mergeCloudLibrary(
                with: remoteSnapshot.payload,
                base: mergeBaseSnapshot,
                choices: choices
            )
            guard conflicts.isEmpty else {
                state = .conflicts(conflicts)
                return
            }
            mergeBaseSnapshot = nil
            await uploadLocalSnapshot(forceFollowUp: true)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard let requestedAccountID = accountID else {
            state = .localOnly
            return
        }

        if let deferredInitialChoice {
            state = .initialChoice(
                local: deferredInitialChoice.local,
                cloud: deferredInitialChoice.cloud
            )
            return
        }

        automaticSyncPaused = false
        if case .initialChoice = state { return }
        if case .conflicts = state { return }

        await refreshFromCloudIfAllowed(force: true)
        guard accountID == requestedAccountID else { return }
        if case .conflicts = state { return }
        await uploadLocalSnapshot(forceFollowUp: true)
    }

    func appBecameActive() async {
        await refreshFromCloudIfAllowed()
        await syncLocalChangesIfAllowed()
    }

    func deleteAccountAndCloudData() async throws {
        guard let deletingAccountID = accountID else {
            state = .localOnly
            return
        }

        try await service.deleteAccountAndCloudData()

        try? removePersistedBase(for: deletingAccountID)
        if localLibraryAccountID == deletingAccountID {
            try linkLocalLibrary(to: nil)
        }

        guard accountID == deletingAccountID else { return }

        accountID = nil
        remoteSnapshot = nil
        mergeBaseSnapshot = nil
        expectedRevision = 0
        automaticSyncPaused = false
        deferredInitialChoice = nil
        lastSyncedAt = nil
        state = .localOnly
    }

    private func loadAccountSnapshot(userID: UUID) async {
        guard let store else { return }
        state = .syncing

        do {
            let persistedBase = remoteSnapshot
            let local = try store.exportCloudSnapshot()
            let linkedAccountID = localLibraryAccountID
            let remote = try await service.download(for: userID)
            guard accountID == userID else { return }

            // A local library associated with another account must never be
            // silently uploaded into the newly signed-in account.
            if store.hasUserData,
               let linkedAccountID,
               linkedAccountID != userID {
                remoteSnapshot = remote
                expectedRevision = remote?.revision ?? 0
                state = .initialChoice(
                    local: CloudLibraryCounts(local),
                    cloud: remote.map { CloudLibraryCounts($0.payload) }
                )
                return
            }

            if store.hasUserData,
               linkedAccountID == nil,
               persistedBase == nil {
                remoteSnapshot = remote
                expectedRevision = remote?.revision ?? 0
                state = .initialChoice(
                    local: CloudLibraryCounts(local),
                    cloud: remote.map { CloudLibraryCounts($0.payload) }
                )
                return
            }

            if let persistedBase {
                guard let remote else {
                    state = .error(
                        "The previously synced cloud library is no longer available."
                    )
                    return
                }

                expectedRevision = remote.revision

                if remote.revision == persistedBase.revision {
                    remoteSnapshot = remote
                    if local == persistedBase.payload {
                        try persistBase(remote, for: userID)
                        try linkLocalLibrary(to: userID)
                        lastExportedToken = store.changeToken
                        markSynced(remote.serverUpdatedAt)
                    } else {
                        // Local offline edits exist. Keep the persisted server
                        // base and let the normal upload path compare-and-swap.
                        state = .localOnly
                    }
                    return
                }

                let localWasDirty = local != persistedBase.payload
                let conflicts = try store.mergeCloudLibrary(
                    with: remote.payload,
                    base: persistedBase.payload
                )
                guard accountID == userID else { return }

                mergeBaseSnapshot = persistedBase.payload
                remoteSnapshot = remote
                expectedRevision = remote.revision

                if conflicts.isEmpty {
                    mergeBaseSnapshot = nil
                    if localWasDirty {
                        state = .localOnly
                    } else {
                        try persistBase(remote, for: userID)
                        try linkLocalLibrary(to: userID)
                        lastExportedToken = store.changeToken
                        markSynced(remote.serverUpdatedAt)
                    }
                } else {
                    state = .conflicts(conflicts)
                }
                return
            }

            remoteSnapshot = remote
            expectedRevision = remote?.revision ?? 0

            if let remote {
                if store.hasUserData {
                    state = .initialChoice(
                        local: CloudLibraryCounts(local),
                        cloud: CloudLibraryCounts(remote.payload)
                    )
                } else {
                    try store.replaceLibrary(with: remote.payload)
                    try persistBase(remote, for: userID)
                    try linkLocalLibrary(to: userID)
                    lastExportedToken = store.changeToken
                    markSynced(remote.serverUpdatedAt)
                }
            } else if store.hasUserData
                        || !(local.deletedEntities ?? []).isEmpty {
                state = .initialChoice(
                    local: CloudLibraryCounts(local),
                    cloud: nil
                )
            } else {
                lastExportedToken = store.changeToken
                state = .localOnly
            }
        } catch {
            guard accountID == userID else { return }
            state = .error(error.localizedDescription)
        }
    }

    private func refreshFromCloudIfAllowed(force: Bool = false) async {
        guard let store, let accountID else { return }
        guard !isSyncing else { return }
        guard force || (!automaticSyncPaused && canSyncAutomatically) else {
            return
        }
        if case .initialChoice = state { return }
        if case .conflicts = state { return }

        isSyncing = true
        state = .syncing
        defer { isSyncing = false }

        do {
            let latest = try await service.download(for: accountID)
            guard self.accountID == accountID else { return }

            guard let latest else {
                if expectedRevision > 0 {
                    state = .error(
                        "The cloud library is no longer available. Sync again before uploading."
                    )
                } else {
                    state = .localOnly
                }
                return
            }

            guard latest.revision != expectedRevision else {
                remoteSnapshot = latest
                if store.changeToken == lastExportedToken {
                    try persistBase(latest, for: accountID)
                    try linkLocalLibrary(to: accountID)
                    markSynced(latest.serverUpdatedAt)
                } else {
                    state = .localOnly
                }
                return
            }

            let base = remoteSnapshot?.payload
            let localWasDirty = store.changeToken != lastExportedToken
            let conflicts = try store.mergeCloudLibrary(
                with: latest.payload,
                base: base
            )
            guard self.accountID == accountID else { return }

            mergeBaseSnapshot = base
            remoteSnapshot = latest
            expectedRevision = latest.revision

            if conflicts.isEmpty {
                mergeBaseSnapshot = nil
                if localWasDirty {
                    state = .localOnly
                } else {
                    try persistBase(latest, for: accountID)
                    try linkLocalLibrary(to: accountID)
                    lastExportedToken = store.changeToken
                    markSynced(latest.serverUpdatedAt)
                }
            } else {
                state = .conflicts(conflicts)
            }
        } catch {
            guard self.accountID == accountID else { return }
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

    private func uploadLocalSnapshot(forceFollowUp: Bool = false) async {
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
                    Task { @MainActor in
                        if forceFollowUp {
                            await self.uploadLocalSnapshot(forceFollowUp: true)
                        } else {
                            await self.syncLocalChangesIfAllowed()
                        }
                    }
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
                mergeBaseSnapshot = nil
                expectedRevision = saved.revision
                try persistBase(saved, for: accountID)
                try linkLocalLibrary(to: accountID)
                lastExportedToken = submittedToken
                markSynced(saved.serverUpdatedAt)
                followUpSyncNeeded = store.changeToken != submittedToken
            } catch RecipeCloudSyncError.revisionConflict {
                guard self.accountID == accountID else { return }
                let base = remoteSnapshot?.payload
                let latest = try await service.download(for: accountID)
                guard self.accountID == accountID else { return }

                guard let latest else {
                    state = .error(
                        "Cloud sync changed while this device was saving. Try again."
                    )
                    return
                }

                let conflicts = try store.mergeCloudLibrary(
                    with: latest.payload,
                    base: base
                )
                guard self.accountID == accountID else { return }

                mergeBaseSnapshot = base
                remoteSnapshot = latest
                expectedRevision = latest.revision

                if conflicts.isEmpty {
                    mergeBaseSnapshot = nil
                    state = .localOnly
                    followUpSyncNeeded = true
                } else {
                    state = .conflicts(conflicts)
                }
            }
        } catch {
            guard self.accountID == accountID else { return }
            state = .error(error.localizedDescription)
        }
    }

    private var localLibraryAccountID: UUID? {
        guard let raw = UserDefaults.standard.string(
            forKey: "recipe.sync.localAccountID"
        ) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private var localEraseMarkerURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
            .appendingPathComponent(".localErasePending")
    }

    private func linkLocalLibrary(to userID: UUID?) throws {
        let defaults = UserDefaults.standard
        if let userID {
            // Persist the newly linked account first; clear the durable erase
            // barrier only AFTER a confirmed cloud read/save and local base.
            defaults.set(
                userID.uuidString,
                forKey: "recipe.sync.localAccountID"
            )
            guard defaults.synchronize() else {
                throw RecipeLocalResetError.markerPersistenceFailed
            }
            try RecipeLocalEraseMarker.clear(at: localEraseMarkerURL)
            defaults.removeObject(forKey: "recipe.sync.localErasePending")
        } else {
            defaults.removeObject(
                forKey: "recipe.sync.localAccountID"
            )
        }
    }

    private func lastSyncedKey(for userID: UUID) -> String {
        "recipe.sync.lastAt.\(userID.uuidString)"
    }

    private func syncBaseURL(for userID: UUID) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent(
                "\(userID.uuidString).json"
            )
    }

    private func loadPersistedBase(
        for userID: UUID
    ) -> CloudSnapshotEnvelope? {
        // A previous local-only erase invalidates ALL cached server baselines,
        // including files left behind by an interrupted cleanup.
        guard !RecipeLocalEraseMarker.isPresent(at: localEraseMarkerURL),
              !UserDefaults.standard.bool(
                forKey: "recipe.sync.localErasePending"
              ) else {
            return nil
        }

        let url = syncBaseURL(for: userID)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CloudSnapshotEnvelope.self,
            from: data
        )
    }

    private func persistBase(
        _ snapshot: CloudSnapshotEnvelope,
        for userID: UUID
    ) throws {
        let url = syncBaseURL(for: userID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private func removePersistedBase(
        for userID: UUID
    ) throws {
        let url = syncBaseURL(for: userID)
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func markSynced(_ date: Date?) {
        let timestamp = date ?? .now
        lastSyncedAt = timestamp
        if let accountID {
            UserDefaults.standard.set(
                timestamp,
                forKey: lastSyncedKey(for: accountID)
            )
        }
        state = .synced(timestamp)
    }
}

private struct SaveSnapshotParameters: Encodable {
    let targetUserID: UUID
    let expectedRevision: Int64
    let schemaVersion: Int
    let payload: RecipeLibrarySnapshot
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
    let payload: RecipeLibrarySnapshot
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
