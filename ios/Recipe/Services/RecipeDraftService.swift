// Developer: gengyun
// Purpose: Bridges the authenticated owner draft flow (session -> turn -> review -> approve) to durable settlement and private save.

import Foundation
import Observation
import RecipeCore

/// Owner-scoped draft orchestration error surfaced to the review view.
enum RecipeDraftServiceError: Error, Equatable {
    case notSignedIn
    case ownerChanged
}

/// DEV-428 publishes this composition contract: an approved draft turn plus its
/// authoritative session become the canonical saveable recipe and the 64-hex
/// input hash that the settlement routes verify. This lane injects the contract
/// so it can be filled by DEV-428 without blocking the independent draft flow.
struct RecipeDraftComposition: Hashable, Sendable {
    let inputHash: String
    let recipe: Recipe

    init(inputHash: String, recipe: Recipe) {
        self.inputHash = inputHash
        self.recipe = recipe
    }
}

/// Classified failure so the review view can distinguish reload-diff from retry from manual fallback.
enum RecipeDraftFailureKind: Equatable, Sendable {
    case authRequired
    case notFound
    case staleRevision
    case alreadyDecided
    case idempotencyConflict
    case quotaExceeded
    case serviceUnavailable
    case invalidInput
    case unknown
}

struct RecipeDraftFailure: Equatable, Sendable {
    let kind: RecipeDraftFailureKind
    let code: String?
    let message: String
    let recoverable: Bool

    init(
        kind: RecipeDraftFailureKind,
        code: String? = nil,
        message: String,
        recoverable: Bool = true
    ) {
        self.kind = kind
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
}

/// The review screen's input: server-issued questions and AI suggestions plus the
/// paths the user has accepted so far. Selection is immutable; toggle returns a copy.
struct RecipeDraftReview: Equatable, Sendable {
    let sessionID: String
    let turnRequestID: String
    let questions: [RecipeDraftQuestion]
    let suggestions: [RecipeDraftSuggestion]
    let reviewFields: [String]
    let selectedPaths: Set<String>

    init(
        sessionID: String,
        turnRequestID: String,
        questions: [RecipeDraftQuestion],
        suggestions: [RecipeDraftSuggestion],
        reviewFields: [String],
        selectedPaths: Set<String> = []
    ) {
        self.sessionID = sessionID
        self.turnRequestID = turnRequestID
        self.questions = questions
        self.suggestions = suggestions
        self.reviewFields = reviewFields
        self.selectedPaths = selectedPaths
    }

    func selecting(_ path: String) -> RecipeDraftReview {
        var next = selectedPaths
        next.insert(path)
        return RecipeDraftReview(
            sessionID: sessionID,
            turnRequestID: turnRequestID,
            questions: questions,
            suggestions: suggestions,
            reviewFields: reviewFields,
            selectedPaths: next
        )
    }

    func deselecting(_ path: String) -> RecipeDraftReview {
        var next = selectedPaths
        next.remove(path)
        return RecipeDraftReview(
            sessionID: sessionID,
            turnRequestID: turnRequestID,
            questions: questions,
            suggestions: suggestions,
            reviewFields: reviewFields,
            selectedPaths: next
        )
    }
}

enum RecipeDraftPhase: Equatable, Sendable {
    case idle
    case loading
    case reviewing(RecipeDraftReview)
    case approving
    case saved(UUID)
    case noChangesNeeded
    case manualFallback
    case failed(RecipeDraftFailure)
    case unavailable(String)
}

/// Durable session identity so a restart resumes the same owner session for a job.
struct RecipeDraftSessionRecord: Codable, Hashable, Sendable {
    let ownerID: UUID
    let jobID: UUID
    let sessionID: String
    let clientRequestID: UUID

    init(ownerID: UUID, jobID: UUID, sessionID: String, clientRequestID: UUID) {
        self.ownerID = ownerID
        self.jobID = jobID
        self.sessionID = sessionID
        self.clientRequestID = clientRequestID
    }
}

/// The server finalize receipt persisted so a crash after finalize never re-settles.
struct RecipeDraftFinalizedReceipt: Codable, Hashable, Sendable {
    let recipeID: UUID
    let payloadHash: String

    init(recipeID: UUID, payloadHash: String) {
        self.recipeID = recipeID
        self.payloadHash = payloadHash
    }
}

/// Durable local intent persisted atomically before finalize. It carries the composed
/// recipe so recovery can finish local write + ACK without recomposition or double settle.
struct RecipeDraftSettlementIntent: Codable, Hashable, Sendable {
    let ownerID: UUID
    let operationID: UUID
    let sessionID: String
    let turnRequestID: String
    let inputHash: String
    var recipe: Recipe
    var finalized: RecipeDraftFinalizedReceipt?

    init(
        ownerID: UUID,
        operationID: UUID,
        sessionID: String,
        turnRequestID: String,
        inputHash: String,
        recipe: Recipe,
        finalized: RecipeDraftFinalizedReceipt? = nil
    ) {
        self.ownerID = ownerID
        self.operationID = operationID
        self.sessionID = sessionID
        self.turnRequestID = turnRequestID
        self.inputHash = inputHash
        self.recipe = recipe
        self.finalized = finalized
    }
}

/// File-backed, owner-scoped persistence for session resume and settlement recovery.
/// A missing or corrupt file is an empty store, never a crash; recovery re-runs idempotently.
final class RecipeDraftDurableStore: @unchecked Sendable {
    private struct Envelope: Codable {
        var sessions: [RecipeDraftSessionRecord]
        var intents: [RecipeDraftSettlementIntent]
    }

    private let lock = NSLock()
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func applicationSupport() -> RecipeDraftDurableStore {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
        return RecipeDraftDurableStore(
            fileURL: directory.appendingPathComponent("draft-settlement.json")
        )
    }

    func sessionRecord(ownerID: UUID, jobID: UUID) -> RecipeDraftSessionRecord? {
        withLock {
            load().sessions.first { $0.ownerID == ownerID && $0.jobID == jobID }
        }
    }

    func upsertSessionRecord(_ record: RecipeDraftSessionRecord) throws {
        try withLock {
            var envelope = load()
            envelope.sessions.removeAll {
                $0.ownerID == record.ownerID && $0.jobID == record.jobID
            }
            envelope.sessions.append(record)
            try save(envelope)
        }
    }

    func removeSessionRecord(ownerID: UUID, jobID: UUID) throws {
        try withLock {
            var envelope = load()
            envelope.sessions.removeAll { $0.ownerID == ownerID && $0.jobID == jobID }
            try save(envelope)
        }
    }

    func intents(ownerID: UUID) -> [RecipeDraftSettlementIntent] {
        withLock {
            load().intents.filter { $0.ownerID == ownerID }
        }
    }

    func upsertIntent(_ intent: RecipeDraftSettlementIntent) throws {
        try withLock {
            var envelope = load()
            envelope.intents.removeAll {
                $0.ownerID == intent.ownerID && $0.operationID == intent.operationID
            }
            envelope.intents.append(intent)
            try save(envelope)
        }
    }

    func removeIntent(ownerID: UUID, operationID: UUID) throws {
        try withLock {
            var envelope = load()
            envelope.intents.removeAll {
                $0.ownerID == ownerID && $0.operationID == operationID
            }
            try save(envelope)
        }
    }

    private func load() -> Envelope {
        guard let data = try? Data(contentsOf: fileURL),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else {
            return Envelope(sessions: [], intents: [])
        }
        return envelope
    }

    private func save(_ envelope: Envelope) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

/// Coordinates the authenticated owner draft flow without touching private Recipe models,
/// provider dispatch, or RecipeStore internals. Constructed with committed RecipeDraftClient
/// closures so networking and the auth bridge stay outside this lane.
@MainActor @Observable
final class RecipeDraftService {
    typealias Compose = @Sendable (
        _ session: RecipeDraftSession,
        _ approval: RecipeDraftApprovalReceipt
    ) throws -> RecipeDraftComposition

    typealias RecipeWrite = @Sendable (Recipe) throws -> Void

    private let client: RecipeDraftClient
    private let compose: Compose
    private let writeRecipe: RecipeWrite
    private let currentOwnerID: @Sendable () async -> UUID?
    private let authenticate: RecipeDraftClient.Authenticate
    private let isOwnerCurrent: RecipeDraftClient.IsOwnerCurrent
    private let send: RecipeDraftClient.Send
    private let functionBaseURL: URL
    private let durableStore: RecipeDraftDurableStore

    private var ownerID: UUID?
    private var session: RecipeDraftSession?
    private var turn: RecipeDraftTurn?
    private var lastJobID: UUID?
    private var lastClientRequestID: UUID?
    private var inFlight = false

    private(set) var phase: RecipeDraftPhase = .idle
    let isEnabled: Bool

    init(
        functionBaseURL: URL,
        enabled: Bool = false,
        authenticate: @escaping RecipeDraftClient.Authenticate,
        isOwnerCurrent: @escaping RecipeDraftClient.IsOwnerCurrent,
        currentOwnerID: @escaping @Sendable () async -> UUID?,
        send: @escaping RecipeDraftClient.Send = {
            try await RecipeShareHTTPTransport.send($0)
        },
        compose: @escaping Compose,
        writeRecipe: @escaping RecipeWrite,
        durableStore: RecipeDraftDurableStore = .applicationSupport()
    ) throws {
        self.functionBaseURL = functionBaseURL
        self.isEnabled = enabled
        self.authenticate = authenticate
        self.isOwnerCurrent = isOwnerCurrent
        self.currentOwnerID = currentOwnerID
        self.send = send
        self.compose = compose
        self.writeRecipe = writeRecipe
        self.durableStore = durableStore
        self.client = try RecipeDraftClient(
            functionBaseURL: functionBaseURL,
            enabled: enabled,
            authenticate: authenticate,
            isOwnerCurrent: isOwnerCurrent,
            send: send
        )
    }

    // MARK: - Public flow

    /// Creates or resumes the owner's session for a job, runs one no-chat turn, and polls to terminal.
    func start(jobID: UUID, clientRequestID: UUID) async {
        guard !inFlight else { return }
        guard isEnabled else {
            phase = .unavailable(Message.unavailable)
            return
        }
        inFlight = true
        defer { inFlight = false }
        lastJobID = jobID
        lastClientRequestID = clientRequestID
        do {
            let owner = try await refreshedOwner()
            phase = .loading
            let session = try await createOrResumeSession(
                jobID: jobID, clientRequestID: clientRequestID, ownerID: owner
            )
            self.session = session
            let turn = try await runTurn(session: session, ownerID: owner)
            self.turn = turn
            phase = terminalPhase(turn, session: session)
        } catch {
            phase = .failed(failure(for: error))
        }
    }

    func select(_ path: String) {
        guard case .reviewing(let review) = phase else { return }
        phase = .reviewing(review.selecting(path))
    }

    func deselect(_ path: String) {
        guard case .reviewing(let review) = phase else { return }
        phase = .reviewing(review.deselecting(path))
    }

    /// Accepts the selected AI suggestions, then durably settles: compose -> finalize -> local write -> ACK.
    func approve() async {
        guard case .reviewing(let review) = phase else { return }
        guard !review.selectedPaths.isEmpty else { return }
        guard !inFlight else { return }
        guard isEnabled else {
            phase = .unavailable(Message.unavailable)
            return
        }
        inFlight = true
        defer { inFlight = false }
        do {
            let owner = try await refreshedOwner()
            guard let session, let turn else { throw RecipeDraftClientError.invalidResponse }
            let sessionID = try uuid(session.sessionID)
            let turnRequestID = try uuid(turn.requestID)
            phase = .approving
            let receipt = try await client.approveTurn(
                sessionID: sessionID,
                turnRequestID: turnRequestID,
                requestID: UUID(),
                expectedRevision: session.revision,
                action: "accept",
                selectedPaths: Array(review.selectedPaths).sorted(),
                ownerID: owner
            )
            let updatedSession = try await client.fetchSession(
                sessionID: sessionID, ownerID: owner
            )
            let recipeID = try await settle(
                receipt: receipt, session: updatedSession, ownerID: owner
            )
            phase = .saved(recipeID)
        } catch {
            phase = .failed(failure(for: error))
        }
    }

    /// Rejects all AI suggestions and returns control to the existing manual save flow.
    func rejectAI() async {
        guard case .reviewing = phase else { return }
        guard !inFlight else { return }
        guard isEnabled else {
            phase = .unavailable(Message.unavailable)
            return
        }
        inFlight = true
        defer { inFlight = false }
        do {
            let owner = try await refreshedOwner()
            guard let session, let turn else { throw RecipeDraftClientError.invalidResponse }
            phase = .approving
            _ = try await client.approveTurn(
                sessionID: try uuid(session.sessionID),
                turnRequestID: try uuid(turn.requestID),
                requestID: UUID(),
                expectedRevision: session.revision,
                action: "reject",
                selectedPaths: [],
                ownerID: owner
            )
            phase = .manualFallback
        } catch {
            phase = .failed(failure(for: error))
        }
    }

    /// Leaves the draft flow untouched and defers to the existing manual editor.
    func skipToManual() {
        guard !inFlight else { return }
        clearDraftState()
        phase = .manualFallback
    }

    /// Re-runs the last start; settlement failures recover through `recoverPendingSettlement`.
    func retry() async {
        guard !inFlight else { return }
        if let jobID = lastJobID, let clientRequestID = lastClientRequestID {
            await start(jobID: jobID, clientRequestID: clientRequestID)
        } else {
            phase = .idle
        }
    }

    /// Account switch or logout: drop the current flow and any in-flight presentation.
    func reset() {
        clearDraftState()
        phase = .idle
    }

    /// Replays the current owner's durable settlement intents. A finalized intent only
    /// re-runs local write + ACK; a pre-finalize intent re-runs finalize (idempotent by operationID).
    func recoverPendingSettlement() async {
        guard let owner = await currentOwnerID() else { return }
        self.ownerID = owner
        let intents = durableStore.intents(ownerID: owner)
        for intent in intents {
            if Task.isCancelled {
                return
            }
            do {
                if let finalized = intent.finalized {
                    var recipe = intent.recipe
                    recipe.id = finalized.recipeID
                    try writeRecipe(recipe)
                    _ = try await ack(operationID: intent.operationID, ownerID: owner)
                } else {
                    try await finishUnfinalized(intent, ownerID: owner)
                }
                try durableStore.removeIntent(ownerID: owner, operationID: intent.operationID)
            } catch {
                // Leave the intent in place; the next launch retries. Never surface as saved.
                continue
            }
        }
    }

    // MARK: - Draft flow

    private func createOrResumeSession(
        jobID: UUID, clientRequestID: UUID, ownerID: UUID
    ) async throws -> RecipeDraftSession {
        if let record = durableStore.sessionRecord(ownerID: ownerID, jobID: jobID),
            let sessionID = UUID(uuidString: record.sessionID)
        {
            do {
                return try await client.fetchSession(sessionID: sessionID, ownerID: ownerID)
            } catch let error as RecipeDraftAPIError where error.code == "NOT_FOUND" {
                try durableStore.removeSessionRecord(ownerID: ownerID, jobID: jobID)
            }
        }
        let session = try await client.createSession(
            jobID: jobID, clientRequestID: clientRequestID, ownerID: ownerID
        )
        try durableStore.upsertSessionRecord(
            RecipeDraftSessionRecord(
                ownerID: ownerID,
                jobID: jobID,
                sessionID: session.sessionID,
                clientRequestID: clientRequestID
            )
        )
        return session
    }

    private func runTurn(session: RecipeDraftSession, ownerID: UUID) async throws
        -> RecipeDraftTurn
    {
        let requestID = UUID()
        var turn = try await client.createTurn(
            sessionID: try uuid(session.sessionID),
            requestID: requestID,
            expectedRevision: session.revision,
            message: "",
            ownerID: ownerID
        )
        var attempts = 0
        while turn.state == "pending" && attempts < 60 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1000))
            turn = try await client.fetchTurn(
                sessionID: try uuid(session.sessionID),
                requestID: requestID,
                ownerID: ownerID
            )
            attempts += 1
        }
        return turn
    }

    private func terminalPhase(
        _ turn: RecipeDraftTurn, session: RecipeDraftSession
    ) -> RecipeDraftPhase {
        guard turn.state == "terminal", let result = turn.result else {
            return .failed(
                RecipeDraftFailure(
                    kind: .unknown, code: nil, message: Message.unexpected, recoverable: false
                )
            )
        }
        switch result {
        case .noReviewNeeded:
            return .noChangesNeeded
        case .proposal(let questions, let suggestions):
            return .reviewing(
                RecipeDraftReview(
                    sessionID: turn.sessionID,
                    turnRequestID: turn.requestID,
                    questions: questions,
                    suggestions: suggestions,
                    reviewFields: session.context.reviewFields
                )
            )
        case .rejected(let code):
            return .failed(generationFailure(code))
        case .unavailable(let code):
            return .unavailable(generationMessage(code))
        }
    }

    // MARK: - Settlement

    private func settle(
        receipt: RecipeDraftApprovalReceipt, session: RecipeDraftSession, ownerID: UUID
    ) async throws -> UUID {
        let composition = try compose(session, receipt)
        let operationID = UUID()
        let intent = RecipeDraftSettlementIntent(
            ownerID: ownerID,
            operationID: operationID,
            sessionID: receipt.sessionID,
            turnRequestID: receipt.turnRequestID,
            inputHash: composition.inputHash,
            recipe: composition.recipe
        )
        try durableStore.upsertIntent(intent)

        let response = try await finalize(
            operationID: operationID,
            inputHash: composition.inputHash,
            sessionID: receipt.sessionID,
            turnRequestID: receipt.turnRequestID,
            ownerID: ownerID
        )
        guard let recipeID = UUID(uuidString: response.recipeID) else {
            throw RecipeDraftClientError.invalidResponse
        }
        var finalizedIntent = intent
        finalizedIntent.finalized = RecipeDraftFinalizedReceipt(
            recipeID: recipeID, payloadHash: response.payloadHash
        )
        try durableStore.upsertIntent(finalizedIntent)

        var recipe = composition.recipe
        recipe.id = recipeID
        try writeRecipe(recipe)

        _ = try await ack(operationID: operationID, ownerID: ownerID)
        try durableStore.removeIntent(ownerID: ownerID, operationID: operationID)
        return recipeID
    }

    private func finishUnfinalized(
        _ intent: RecipeDraftSettlementIntent, ownerID: UUID
    ) async throws {
        let response = try await finalize(
            operationID: intent.operationID,
            inputHash: intent.inputHash,
            sessionID: intent.sessionID,
            turnRequestID: intent.turnRequestID,
            ownerID: ownerID
        )
        guard let recipeID = UUID(uuidString: response.recipeID) else {
            throw RecipeDraftClientError.invalidResponse
        }
        var finalizedIntent = intent
        finalizedIntent.finalized = RecipeDraftFinalizedReceipt(
            recipeID: recipeID, payloadHash: response.payloadHash
        )
        try durableStore.upsertIntent(finalizedIntent)

        var recipe = intent.recipe
        recipe.id = recipeID
        try writeRecipe(recipe)
        _ = try await ack(operationID: intent.operationID, ownerID: ownerID)
    }

    private func finalize(
        operationID: UUID, inputHash: String, sessionID: String, turnRequestID: String,
        ownerID: UUID
    ) async throws -> RecipeUsageFinalizeResponse {
        let source = try RecipeUsageSource(sessionID: sessionID, turnRequestID: turnRequestID)
        let body = try RecipeUsageFinalizeRequest(
            capability: .aiEdit, inputHash: inputHash, source: source
        )
        return try await performSettlement(
            path: [operationID.uuidString.lowercased(), "finalize"],
            ownerID: ownerID,
            body: body
        )
    }

    private func ack(operationID: UUID, ownerID: UUID) async throws
        -> RecipeUsageAckResponse
    {
        try await performSettlement(
            path: [operationID.uuidString.lowercased(), "ack"],
            ownerID: ownerID,
            body: Optional<EmptyBody>.none
        )
    }

    private struct EmptyBody: Encodable {}

    private func performSettlement<T: Decodable>(
        path: [String], ownerID: UUID, body: (any Encodable)?
    ) async throws -> T {
        let credential = try await authenticate(ownerID)
        try Task.checkCancellation()
        guard credential.ownerID == ownerID, !credential.bearerToken.isEmpty else {
            throw RecipeDraftServiceError.ownerChanged
        }
        guard await isOwnerCurrent(credential) else {
            throw RecipeDraftServiceError.ownerChanged
        }
        var url = functionBaseURL.appendingPathComponent("recipe-usage")
        for part in path {
            url.appendPathComponent(part)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(
            "Bearer " + credential.bearerToken, forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        try Task.checkCancellation()
        guard await isOwnerCurrent(credential) else {
            throw RecipeDraftServiceError.ownerChanged
        }
        guard data.count <= RecipeShareHTTPTransport.maximumBodyBytes else {
            throw RecipeDraftClientError.invalidResponse
        }
        guard response.statusCode == 200 else {
            if let error = try? JSONDecoder().decode(RecipeUsageAPIError.self, from: data) {
                throw error
            }
            throw RecipeDraftClientError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Owner isolation

    private func refreshedOwner() async throws -> UUID {
        guard let owner = await currentOwnerID() else {
            throw RecipeDraftServiceError.notSignedIn
        }
        if owner != ownerID {
            ownerID = owner
            clearDraftState()
        }
        return owner
    }

    private func clearDraftState() {
        session = nil
        turn = nil
        lastJobID = nil
        lastClientRequestID = nil
    }

    private func uuid(_ text: String) throws -> UUID {
        guard let value = UUID(uuidString: text) else {
            throw RecipeDraftClientError.invalidResponse
        }
        return value
    }

    // MARK: - Error mapping

    private func failure(for error: Error) -> RecipeDraftFailure {
        if let api = error as? RecipeDraftAPIError {
            return RecipeDraftFailure(
                kind: draftKind(api.code),
                code: api.code,
                message: api.message,
                recoverable: api.recoverable
            )
        }
        if let api = error as? RecipeUsageAPIError {
            return RecipeDraftFailure(
                kind: usageKind(api.code),
                code: api.code,
                message: api.message,
                recoverable: api.recoverable
            )
        }
        if let serviceError = error as? RecipeDraftServiceError {
            switch serviceError {
            case .notSignedIn:
                return RecipeDraftFailure(
                    kind: .authRequired, code: nil, message: Message.signedOut
                )
            case .ownerChanged:
                return RecipeDraftFailure(
                    kind: .authRequired, code: nil, message: Message.ownerChanged
                )
            }
        }
        if let clientError = error as? RecipeDraftClientError {
            switch clientError {
            case .disabled:
                return RecipeDraftFailure(
                    kind: .serviceUnavailable, code: nil, message: Message.unavailable,
                    recoverable: false
                )
            case .ownerChanged:
                return RecipeDraftFailure(
                    kind: .authRequired, code: nil, message: Message.ownerChanged
                )
            case .invalidInput, .invalidResponse:
                return RecipeDraftFailure(
                    kind: .unknown, code: nil, message: Message.unexpected, recoverable: false
                )
            }
        }
        if error is CancellationError {
            return RecipeDraftFailure(
                kind: .unknown, code: nil, message: Message.cancelled
            )
        }
        return RecipeDraftFailure(
            kind: .unknown, code: nil, message: error.localizedDescription
        )
    }

    private func generationFailure(_ code: String) -> RecipeDraftFailure {
        let kind: RecipeDraftFailureKind
        let recoverable: Bool
        switch code {
        case "STALE_REVISION":
            kind = .staleRevision
            recoverable = true
        case "INPUT_BUDGET", "OUTPUT_BUDGET":
            kind = .quotaExceeded
            recoverable = false
        case "INVALID_INPUT", "INVALID_EVIDENCE", "INVALID_REVIEW_PATH",
            "INVALID_PROVIDER_OUTPUT":
            kind = .invalidInput
            recoverable = false
        default:
            kind = .unknown
            recoverable = true
        }
        return RecipeDraftFailure(
            kind: kind, code: code, message: generationMessage(code), recoverable: recoverable
        )
    }

    private func generationMessage(_ code: String) -> String {
        switch code {
        case "STALE_REVISION":
            return Message.staleRevision
        case "INPUT_BUDGET", "OUTPUT_BUDGET":
            return Message.budgetExhausted
        case "INVALID_INPUT", "INVALID_EVIDENCE", "INVALID_REVIEW_PATH",
            "INVALID_PROVIDER_OUTPUT":
            return Message.invalidInput
        default:
            return Message.unavailable
        }
    }

    private func draftKind(_ code: String) -> RecipeDraftFailureKind {
        switch code {
        case "AUTH_REQUIRED": return .authRequired
        case "NOT_FOUND": return .notFound
        case "STALE_REVISION", "REVISION_EXHAUSTED": return .staleRevision
        case "TURN_ALREADY_DECIDED": return .alreadyDecided
        case "IDEMPOTENCY_CONFLICT": return .idempotencyConflict
        case "BUDGET_EXHAUSTED": return .quotaExceeded
        case "DRAFT_DISABLED", "PROVIDER_UNAVAILABLE": return .serviceUnavailable
        case "INVALID_INPUT", "INVALID_EVIDENCE", "INVALID_REVIEW_PATH", "INPUT_TOO_LARGE":
            return .invalidInput
        default: return .unknown
        }
    }

    private func usageKind(_ code: String) -> RecipeDraftFailureKind {
        switch code {
        case "AUTH_REQUIRED", "OWNER_MISMATCH": return .authRequired
        case "NOT_FOUND": return .notFound
        case "IDEMPOTENCY_CONFLICT": return .idempotencyConflict
        case "RESERVATION_EXPIRED": return .staleRevision
        case "QUOTA_EXCEEDED", "UPGRADE_REQUIRED": return .quotaExceeded
        case "CONFIGURATION_UNAVAILABLE", "SERVICE_UNAVAILABLE": return .serviceUnavailable
        case "INVALID_INPUT": return .invalidInput
        default: return .unknown
        }
    }
}

private enum Message {
    static let signedOut = String(
        localized: LocalizedStringResource(
            "Sign in to review and save this recipe.", locale: RecipeLanguage.active
        )
    )
    static let ownerChanged = String(
        localized: LocalizedStringResource(
            "The signed-in account changed, so the review was reset.", locale: RecipeLanguage.active
        )
    )
    static let unavailable = String(
        localized: LocalizedStringResource(
            "Recipe review is temporarily unavailable. You can still enter the details manually.",
            locale: RecipeLanguage.active
        )
    )
    static let invalidInput = String(
        localized: LocalizedStringResource(
            "This recipe couldn't be reviewed as provided. Enter the details manually to continue.",
            locale: RecipeLanguage.active
        )
    )
    static let unexpected = String(
        localized: LocalizedStringResource(
            "Something went wrong. Try again or enter the recipe manually.", locale: RecipeLanguage.active
        )
    )
    static let cancelled = String(
        localized: LocalizedStringResource(
            "The review was canceled.", locale: RecipeLanguage.active
        )
    )
    static let staleRevision = String(
        localized: LocalizedStringResource(
            "This recipe changed while it was being reviewed. Reload to see the latest.",
            locale: RecipeLanguage.active
        )
    )
    static let budgetExhausted = String(
        localized: LocalizedStringResource(
            "Recipe review quota was reached. You can still enter the details manually.",
            locale: RecipeLanguage.active
        )
    )
}
