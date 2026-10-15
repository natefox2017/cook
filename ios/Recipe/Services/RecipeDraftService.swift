// Developer: gengyun
// Purpose: Orchestrates the owner draft review flow from session creation through approval and pending commit persistence.

import Foundation
import Observation
import RecipeCore
import Supabase

/// Errors surfaced to the draft review UI. Every case maps to an explicit
/// loading/review/retry/manual-exit path rather than a shared failure message.
enum RecipeDraftServiceError: LocalizedError, Equatable {
    case notSignedIn
    case invalidConfiguration
    case ownerChanged
    case staleRevision
    case noTurn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            RecipeLanguage.localized("Sign in to review this recipe draft.")
        case .invalidConfiguration:
            RecipeLanguage.localized("The draft review service is not configured.")
        case .ownerChanged:
            RecipeLanguage.localized("The signed-in account changed. The draft review was canceled.")
        case .staleRevision:
            RecipeLanguage.localized("This draft changed on the server. Reloading the differences.")
        case .noTurn:
            RecipeLanguage.localized("No draft turn is available to approve.")
        }
    }
}

/// Stable-per-auth-session generation identifier. Replacing the generation on
/// every login/logout lets the draft client reject credentials from a previous
/// account session even while the owner UUID alone would still match.
private enum RecipeDraftGeneration {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int: UUID] = [:]

    static func uuid(for generation: Int) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[generation] {
            return existing
        }
        let fresh = UUID()
        cache[generation] = fresh
        return fresh
    }
}

/// The deferred finalize → local write → ACK handoff. The DEV-428/DEV-434
/// composition contract owns the payload hash and the RecipeStore write; this
/// protocol is the seam that wiring fills without changing this service.
protocol RecipeDraftCommitHandoff: Sendable {
    func commit(
        session: RecipeDraftSession,
        receipt: RecipeDraftApprovalReceipt,
        ownerID: UUID
    ) async throws
}

@MainActor
@Observable
final class RecipeDraftService {
    enum Phase: Equatable {
        case idle
        case loading
        case reviewing(RecipeDraftReviewState)
        case ready
        case approving
        case committed(RecipeDraftApprovalReceipt)
        case failed(String, Bool)
    }

    struct RecipeDraftReviewState: Equatable {
        let session: RecipeDraftSession
        let questions: [RecipeDraftQuestion]
        let suggestions: [RecipeDraftSuggestion]
        let reviewFields: [String]

        static func make(
            session: RecipeDraftSession,
            turn: RecipeDraftTurn
        ) -> RecipeDraftReviewState? {
            guard case .proposal(let questions, let suggestions) = turn.result else {
                return nil
            }
            return RecipeDraftReviewState(
                session: session,
                questions: questions,
                suggestions: suggestions,
                reviewFields: session.context.reviewFields
            )
        }
    }

    private let client: RecipeDraftClient
    private let pendingStore: RecipeDraftPendingCommitStore
    private let commitHandoff: (any RecipeDraftCommitHandoff)?

    private(set) var phase: Phase = .idle
    private var currentSession: RecipeDraftSession?
    private var currentTurn: RecipeDraftTurn?
    private var inFlight: Task<Void, Never>?

    init(
        pendingStore: RecipeDraftPendingCommitStore = RecipeDraftPendingCommitStore(),
        commitHandoff: (any RecipeDraftCommitHandoff)? = nil,
        bundle: Bundle = .main
    ) throws {
        self.pendingStore = pendingStore
        self.commitHandoff = commitHandoff
        self.client = try RecipeDraftClient(
            functionBaseURL: Self.draftFunctionBaseURL(bundle: bundle),
            enabled: true,
            authenticate: Self.makeAuthenticate(),
            isOwnerCurrent: Self.makeIsOwnerCurrent()
        )
    }

    // MARK: - Session lifecycle

    func createOrResumeSession(jobID: UUID) async {
        guard let ownerID = Self.currentOwnerID() else {
            phase = .failed(RecipeDraftServiceError.notSignedIn.localizedDescription, false)
            return
        }
        await runExclusive { [self] in
            do {
                let session = try await self.client.createSession(
                    jobID: jobID,
                    clientRequestID: UUID(),
                    ownerID: ownerID
                )
                self.currentSession = session
                self.currentTurn = nil
                self.phase = .loading
            } catch {
                await self.fail(for: error)
            }
        }
    }

    func resume(sessionID: UUID) async {
        guard let ownerID = Self.currentOwnerID() else {
            phase = .failed(RecipeDraftServiceError.notSignedIn.localizedDescription, false)
            return
        }
        await runExclusive { [self] in
            do {
                let session = try await self.client.fetchSession(
                    sessionID: sessionID, ownerID: ownerID
                )
                self.currentSession = session
                self.currentTurn = nil
                self.phase = .loading
            } catch {
                await self.fail(for: error)
            }
        }
    }

    // MARK: - Turn lifecycle

    func submitMessage(_ message: String) async {
        guard let session = currentSession, let ownerID = Self.currentOwnerID() else {
            phase = .failed(RecipeDraftServiceError.notSignedIn.localizedDescription, false)
            return
        }
        await runExclusive { [self] in
            do {
                let turn = try await self.client.createTurn(
                    sessionID: Self.uuid(session.sessionID),
                    requestID: UUID(),
                    expectedRevision: session.revision,
                    message: message,
                    ownerID: ownerID
                )
                let settled = try await self.poll(turn: turn, ownerID: ownerID)
                self.apply(turn: settled)
            } catch {
                await self.fail(for: error)
            }
        }
    }

    private func poll(turn: RecipeDraftTurn, ownerID: UUID) async throws -> RecipeDraftTurn {
        var current = turn
        while current.state == "pending" {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(750))
            current = try await client.fetchTurn(
                sessionID: Self.uuid(current.sessionID),
                requestID: Self.uuid(current.requestID),
                ownerID: ownerID
            )
        }
        return current
    }

    private func apply(turn: RecipeDraftTurn) {
        currentTurn = turn
        guard let session = currentSession else {
            phase = .idle
            return
        }
        switch turn.result {
        case .proposal:
            if let state = RecipeDraftReviewState.make(session: session, turn: turn) {
                phase = .reviewing(state)
            } else {
                phase = .failed(
                    RecipeDraftServiceError.noTurn.localizedDescription, false
                )
            }
        case .noReviewNeeded:
            phase = .ready
        case .rejected, .unavailable, .none:
            phase = .failed(
                RecipeDraftServiceError.noTurn.localizedDescription, true
            )
        }
    }

    // MARK: - Approval

    func accept(selectedPaths: [String]) async {
        await approve(action: "accept", selectedPaths: selectedPaths)
    }

    func reject() async {
        await approve(action: "reject", selectedPaths: [])
    }

    private func approve(action: String, selectedPaths: [String]) async {
        guard let session = currentSession, let turn = currentTurn,
            let ownerID = Self.currentOwnerID()
        else {
            phase = .failed(RecipeDraftServiceError.noTurn.localizedDescription, false)
            return
        }
        phase = .approving
        await runExclusive { [self] in
            do {
                let receipt = try await self.client.approveTurn(
                    sessionID: Self.uuid(session.sessionID),
                    turnRequestID: Self.uuid(turn.requestID),
                    requestID: UUID(),
                    expectedRevision: session.revision,
                    action: action,
                    selectedPaths: selectedPaths,
                    ownerID: ownerID
                )
                if action == "accept" {
                    if let commitHandoff = self.commitHandoff {
                        try await commitHandoff.commit(
                            session: session, receipt: receipt, ownerID: ownerID
                        )
                    } else {
                        try self.persistPendingCommit(
                            session: session, receipt: receipt, ownerID: ownerID
                        )
                    }
                }
                self.phase = .committed(receipt)
            } catch {
                await self.fail(for: error)
            }
        }
    }

    // MARK: - Manual exit and cancellation

    func skipToManual() {
        reset()
    }

    func cancel() {
        reset()
    }

    private func reset() {
        inFlight?.cancel()
        inFlight = nil
        currentSession = nil
        currentTurn = nil
        phase = .idle
    }

    // MARK: - Private helpers

    private func persistPendingCommit(
        session: RecipeDraftSession,
        receipt: RecipeDraftApprovalReceipt,
        ownerID: UUID
    ) throws {
        let pending = try RecipeDraftPendingCommit(
            ownerID: ownerID.uuidString.lowercased(),
            sessionID: receipt.sessionID,
            turnRequestID: receipt.turnRequestID,
            requestID: receipt.requestID,
            operationID: UUID().uuidString.lowercased(),
            selectedPaths: receipt.selectedPaths
        )
        try pendingStore.save(pending)
    }

    private func runExclusive(_ body: @escaping () async -> Void) async {
        if inFlight != nil {
            return
        }
        let task = Task { [weak self] in
            await body()
            self?.inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func fail(for error: Error) async {
        switch error {
        case let draftError as RecipeDraftClientError:
            switch draftError {
            case .ownerChanged:
                phase = .failed(
                    RecipeDraftServiceError.ownerChanged.localizedDescription, false
                )
            case .disabled:
                phase = .failed(
                    RecipeDraftServiceError.invalidConfiguration.localizedDescription, false
                )
            case .invalidInput, .invalidResponse:
                phase = .failed(
                    RecipeDraftServiceError.noTurn.localizedDescription, false
                )
            }
        case let apiError as RecipeDraftAPIError where Self.isStaleRevision(apiError):
            phase = .failed(RecipeDraftServiceError.staleRevision.localizedDescription, true)
        case let apiError as RecipeDraftAPIError:
            phase = .failed(apiError.message, apiError.recoverable)
        case is CancellationError:
            phase = .idle
        default:
            phase = .failed(error.localizedDescription, true)
        }
    }

    private static func isStaleRevision(_ error: RecipeDraftAPIError) -> Bool {
        error.code == "STALE_REVISION" || error.code == "REVISION_EXHAUSTED"
    }

    private static func uuid(_ text: String) -> UUID {
        // The draft wire contract validates lowercase RFC UUIDs before a value
        // reaches the service, so a nil result here is a programming error.
        UUID(uuidString: text)!
    }

    private static func currentOwnerID() -> UUID? {
        if case .signedIn(let userID, _) = RecipeAuthService.shared.state {
            return userID
        }
        return nil
    }

    private static func draftFunctionBaseURL(bundle: Bundle) throws -> URL {
        guard
            let origin = bundle.object(forInfoDictionaryKey: "RecipeSupabaseURL") as? String,
            let url = URL(string: origin),
            url.scheme == "https",
            url.host?.hasSuffix(".supabase.co") == true
        else {
            throw RecipeDraftServiceError.invalidConfiguration
        }
        return url.appendingPathComponent("functions/v1")
    }

    private static func makeAuthenticate() -> @Sendable (UUID) async throws
        -> RecipeDraftCredential
    {
        { ownerID in
            let session = try await RecipeSupabase.client.auth.session
            guard session.user.id == ownerID else {
                throw RecipeDraftClientError.ownerChanged
            }
            let generation = await MainActor.run {
                RecipeDraftGeneration.uuid(
                    for: RecipeAuthService.shared.sharingSessionGeneration
                )
            }
            return RecipeDraftCredential(
                ownerID: ownerID,
                generation: generation,
                bearerToken: session.accessToken
            )
        }
    }

    private static func makeIsOwnerCurrent() -> @Sendable (RecipeDraftCredential) async -> Bool {
        { credential in
            await MainActor.run {
                guard case .signedIn(let userID, _) = RecipeAuthService.shared.state else {
                    return false
                }
                return userID == credential.ownerID
            }
        }
    }
}
