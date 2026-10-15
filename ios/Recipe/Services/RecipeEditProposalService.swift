// Developer: gengyun
// Purpose: Bounded session-scoped client for the recipe-edit-proposals Edge Function.

import CryptoKit
import Foundation
import RecipeCore

/// The three DEV-431 wire intents. Vocabulary is frozen with the backend and the
/// recipe_edit_proposals intent check constraint.
enum RecipeEditIntent: String, CaseIterable, Identifiable, Sendable {
    case substitute
    case simplify
    case dietary

    var id: String {
        rawValue
    }
}

enum RecipeEditProposalServiceError: LocalizedError {
    case notSignedIn
    case invalidConfiguration
    case invalidResponse
    case staleRevision
    case needsManualEdit
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return RecipeLanguage.localized("Sign in to adjust this recipe.")
        case .invalidConfiguration:
            return RecipeLanguage.localized("The recipe adjustment service is not configured.")
        case .invalidResponse:
            return RecipeLanguage.localized("The recipe adjustment service returned an invalid response.")
        case .staleRevision:
            return RecipeLanguage.localized("This recipe changed. Get a new suggestion before saving.")
        case .needsManualEdit:
            return RecipeLanguage.localized("This change needs your review. Edit the recipe manually.")
        case .transport(let message):
            return message
        }
    }
}

/// Wire edit change: the three value-replacement paths only. `reason` and
/// `warnings` are per-change and are replayed verbatim on approval.
struct RecipeEditWireChange: Codable, Sendable {
    let path: String
    let original: String
    let proposed: String
    let reason: String
    let warnings: [String]
}

struct RecipeEditProposalSource: Decodable, Sendable {
    let recipeID: String
    let sourceRevision: String
    let snapshotHash: String

    enum CodingKeys: String, CodingKey {
        case recipeID = "recipe_id"
        case sourceRevision = "source_revision"
        case snapshotHash = "snapshot_hash"
    }
}

struct RecipeEditProposalResponse: Decodable, Sendable {
    let proposalID: String
    let status: String
    let intent: String
    let source: RecipeEditProposalSource
    let changes: [RecipeEditWireChange]
    let reasons: [String]
    let warnings: [String]
    let inputHash: String
    let needsManualEdit: Bool

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case status
        case intent
        case source
        case changes
        case reasons
        case warnings
        case inputHash = "input_hash"
        case needsManualEdit = "needs_manual_edit"
    }
}

struct RecipeEditApproveResponse: Decodable, Sendable {
    let proposalID: String
    let status: String
    let operationID: String
    let targetID: String
    let payloadHash: String

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case status
        case operationID = "operation_id"
        case targetID = "target_id"
        case payloadHash = "payload_hash"
    }
}

/// A decoded proposal plus the transport fields the approval round-trip needs.
/// The Swift `RecipeEditProposal` feeds the review UI; `wireChanges` preserves the
/// per-change reason/warnings the server requires back verbatim on approval.
struct RecipeEditProposalRequestResult: Sendable {
    let proposal: RecipeEditProposal?
    let proposalID: String
    let operationID: String
    let wireChanges: [RecipeEditWireChange]
    let needsManualEdit: Bool
    let reasons: [String]
    let warnings: [String]
}

/// Explicit approval target: "apply" keeps the current recipe id, "variant" writes
/// a new private recipe under a client-stable variant id.
enum RecipeEditApplyMode: String, Codable, Sendable {
    case apply
    case variant
}

struct RecipeEditAckResponse: Decodable, Sendable {
    let operationID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case status
    }
}

/// Locally persisted recovery intent for the approve → write → ACK window. It
/// survives a crash between the server approval (usage finalize) and the local
/// durable write so the exact reviewed changes can be re-applied to the correct
/// target without re-invoking the provider. `targetID` is set only after the
/// server approves, so a nil value means the approval (and usage finalize) has
/// not happened yet and the recovery path must replay the approval.
struct RecipeEditPendingCommit: Codable, Sendable {
    let operationID: String
    let proposalID: String
    let mode: RecipeEditApplyMode
    let variantID: String?
    let sourceRecipeID: String
    let basedOnUpdate: Date
    let changes: [RecipeEditWireChange]
    let reasons: [String]
    let warnings: [String]
    let targetID: String?

    init(
        operationID: String,
        proposalID: String,
        mode: RecipeEditApplyMode,
        variantID: String?,
        sourceRecipeID: String,
        basedOnUpdate: Date,
        changes: [RecipeEditWireChange],
        reasons: [String],
        warnings: [String],
        targetID: String? = nil
    ) {
        self.operationID = operationID
        self.proposalID = proposalID
        self.mode = mode
        self.variantID = variantID
        self.sourceRecipeID = sourceRecipeID
        self.basedOnUpdate = basedOnUpdate
        self.changes = changes
        self.reasons = reasons
        self.warnings = warnings
        self.targetID = targetID
    }
}

/// Single in-flight pending commit per owner. The edit review sheet is modal, so
/// only one approval can be in the approve → write → ACK window at a time.
struct RecipeEditPendingCommitStore {
    private let key: String
    private let defaults: UserDefaults

    init(ownerID: String, defaults: UserDefaults = .standard) {
        self.key = "recipe.edit.pending.commit.\(ownerID)"
        self.defaults = defaults
    }

    func save(_ commit: RecipeEditPendingCommit) throws {
        let data = try JSONEncoder().encode(commit)
        defaults.set(data, forKey: key)
    }

    func load() -> RecipeEditPendingCommit? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(RecipeEditPendingCommit.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// Smallest bounded transport adapter for the recipe-edit-proposals endpoint.
/// Generation and usage settlement stay server-side (DEV-431); this client only
/// creates a reviewable proposal and confirms an explicit approval.
@MainActor
final class RecipeEditProposalService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias SessionProvider = @Sendable () async throws -> (accessToken: String, userID: UUID)

    private let baseURL: URL
    private let publishableKey: String
    private let transport: Transport
    private let sessionProvider: SessionProvider

    private static let maximumSupplementCharacters = 500

    convenience init(
        bundle: Bundle = .main,
        transport: Transport? = nil,
        sessionProvider: SessionProvider? = nil
    ) throws {
        guard
            let origin = bundle.object(forInfoDictionaryKey: "RecipeSupabaseURL") as? String,
            let url = URL(string: origin),
            url.scheme == "https",
            let host = url.host,
            host.hasSuffix(".supabase.co"),
            let key = bundle.object(forInfoDictionaryKey: "RecipeSupabasePublishableKey") as? String,
            !key.isEmpty
        else {
            throw RecipeEditProposalServiceError.invalidConfiguration
        }
        self.init(
            baseURL: url.appendingPathComponent("functions/v1/recipe-edit-proposals"),
            publishableKey: key,
            transport: transport ?? { try await RecipeShareHTTPTransport.send($0) },
            sessionProvider: sessionProvider ?? {
                let session = try await RecipeSupabase.client.auth.session
                return (session.accessToken, session.user.id)
            }
        )
    }

    init(
        baseURL: URL,
        publishableKey: String,
        transport: @escaping Transport,
        sessionProvider: @escaping SessionProvider
    ) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.transport = transport
        self.sessionProvider = sessionProvider
    }

    func createProposal(
        recipe: Recipe,
        intent: RecipeEditIntent,
        supplement: String?,
        operationID: UUID = UUID()
    ) async throws -> RecipeEditProposalRequestResult {
        if let supplement {
            guard supplement.unicodeScalars.count <= Self.maximumSupplementCharacters else {
                throw RecipeEditProposalServiceError.invalidResponse
            }
        }
        let session: (accessToken: String, userID: UUID)
        do {
            session = try await sessionProvider()
        } catch {
            throw RecipeEditProposalServiceError.notSignedIn
        }
        let sourceRevision = Self.revision(for: recipe)
        let snapshot = Self.snapshot(for: recipe, sourceRevision: sourceRevision)
        let snapshotHash = try Self.snapshotHash(for: snapshot)

        let recipeBody: [String: Any] = [
            "id": recipe.id.uuidString.lowercased(),
            "updated_at": sourceRevision,
            "snapshot_hash": snapshotHash,
            "ingredients": snapshot.ingredients,
            "steps": snapshot.steps,
        ]
        var body: [String: Any] = [
            "operation_id": operationID.uuidString.lowercased(),
            "intent": intent.rawValue,
            "recipe": recipeBody,
        ]
        if let supplement {
            body["supplement"] = supplement
        }

        let response: RecipeEditProposalResponse = try await perform(
            path: [],
            body: body,
            accessToken: session.accessToken,
            statuses: [200, 201]
        )

        let changes = try response.changes.map(Self.parseChange)
        let proposal: RecipeEditProposal?
        if response.needsManualEdit || changes.isEmpty {
            proposal = nil
        } else {
            proposal = RecipeEditProposal(
                recipeID: recipe.id,
                basedOnUpdate: recipe.updatedAt,
                changes: changes,
                reasons: response.reasons,
                warnings: response.warnings
            )
        }
        return RecipeEditProposalRequestResult(
            proposal: proposal,
            proposalID: response.proposalID,
            operationID: operationID.uuidString.lowercased(),
            wireChanges: response.changes,
            needsManualEdit: response.needsManualEdit,
            reasons: response.reasons,
            warnings: response.warnings
        )
    }

    func approve(
        proposalID: String,
        reviewed: RecipeEditProposal,
        wireChanges: [RecipeEditWireChange],
        recipe: Recipe,
        mode: RecipeEditApplyMode,
        variantID: UUID?
    ) async throws -> RecipeEditApproveResponse {
        let session: (accessToken: String, userID: UUID)
        do {
            session = try await sessionProvider()
        } catch {
            throw RecipeEditProposalServiceError.notSignedIn
        }
        let reviewedChanges = try Self.reviewedWireChanges(
            reviewed: reviewed, wireChanges: wireChanges
        )
        let sourceRevision = Self.revision(for: recipe)
        let snapshot = Self.snapshot(for: recipe, sourceRevision: sourceRevision)
        let expectedSnapshotHash = try Self.snapshotHash(for: snapshot)
        var body: [String: Any] = [
            "changes": reviewedChanges.map {
                [
                    "path": $0.path,
                    "original": $0.original,
                    "proposed": $0.proposed,
                    "reason": $0.reason,
                    "warnings": $0.warnings,
                ]
            },
            "expected_snapshot_hash": expectedSnapshotHash,
            "mode": mode.rawValue,
        ]
        if mode == .variant {
            body["variant_id"] = variantID?.uuidString.lowercased()
        }
        return try await perform(
            path: [proposalID, "approve"],
            body: body,
            accessToken: session.accessToken,
            statuses: [200]
        )
    }

    /// Confirms the local durable write to the server. Must be called only after the
    /// approved receipt has been applied to the correct local target.
    func ack(proposalID: String, operationID: String) async throws -> RecipeEditAckResponse {
        let session: (accessToken: String, userID: UUID)
        do {
            session = try await sessionProvider()
        } catch {
            throw RecipeEditProposalServiceError.notSignedIn
        }
        return try await perform(
            path: [proposalID, "ack"],
            body: ["operation_id": operationID],
            accessToken: session.accessToken,
            statuses: [200]
        )
    }

    /// Replays the reviewed (possibly user-edited) changes with their original
    /// per-change reason/warnings, matching the server's approval payload.
    static func reviewedWireChanges(
        reviewed: RecipeEditProposal,
        wireChanges: [RecipeEditWireChange]
    ) throws -> [RecipeEditWireChange] {
        let byPath = Dictionary(uniqueKeysWithValues: wireChanges.map { ($0.path, $0) })
        return try reviewed.changes.map { change -> RecipeEditWireChange in
            let path = change.wirePath
            guard let original = byPath[path] else {
                throw RecipeEditProposalServiceError.invalidResponse
            }
            return RecipeEditWireChange(
                path: path,
                original: change.originalText,
                proposed: change.proposedText,
                reason: original.reason,
                warnings: original.warnings
            )
        }
    }

    /// Deterministic variant id so a crash-and-replay of the same operation always
    /// writes the same private recipe instead of a duplicate.
    static func stableVariantID(operationID: String) -> UUID {
        let digest = SHA256.hash(data: Data("recipe-edit-variant:\(operationID)".utf8))
        let bytes = digest.withUnsafeBytes { Array($0.prefix(16)) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Rebuilds the exact reviewed proposal a pending commit persisted, so recovery
    /// can re-apply the same changes without re-invoking the provider.
    static func proposal(from pending: RecipeEditPendingCommit) -> RecipeEditProposal? {
        guard let recipeID = UUID(uuidString: pending.sourceRecipeID) else {
            return nil
        }
        do {
            let changes = try pending.changes.map(parseChange)
            return RecipeEditProposal(
                recipeID: recipeID,
                basedOnUpdate: pending.basedOnUpdate,
                changes: changes,
                reasons: pending.reasons,
                warnings: pending.warnings
            )
        } catch {
            return nil
        }
    }

    // MARK: - Transport

    private func perform<T: Decodable>(
        path: [String],
        body: [String: Any],
        accessToken: String,
        statuses: Set<Int>
    ) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        var url = baseURL
        for part in path {
            url.appendPathComponent(part)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport(request)
        } catch {
            throw RecipeEditProposalServiceError.transport(
                RecipeLanguage.localized("Could not reach the recipe adjustment service.")
            )
        }
        let responseData = result.0
        let response = result.1
        guard responseData.count <= RecipeShareHTTPTransport.maximumBodyBytes else {
            throw RecipeEditProposalServiceError.invalidResponse
        }
        guard statuses.contains(response.statusCode) else {
            if let server = try? JSONDecoder().decode(
                RecipeEditServerError.self, from: responseData
            ) {
                switch server.error.code {
                case "STALE_REVISION":
                    throw RecipeEditProposalServiceError.staleRevision
                case "NEEDS_MANUAL_EDIT":
                    throw RecipeEditProposalServiceError.needsManualEdit
                default:
                    throw RecipeEditProposalServiceError.transport(server.error.message)
                }
            }
            throw RecipeEditProposalServiceError.transport(
                RecipeLanguage.localized("Could not adjust this recipe right now.")
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: responseData)
        } catch {
            throw RecipeEditProposalServiceError.invalidResponse
        }
    }

    private struct RecipeEditServerError: Decodable {
        let error: Payload

        struct Payload: Decodable {
            let code: String
            let message: String
        }
    }

    // MARK: - Snapshot

    private struct SnapshotPayload: Codable {
        struct Ingredient: Codable {
            let id: String
            let name: String
            let amount: String
        }
        struct Step: Codable {
            let id: String
            let instruction: String
        }
        let id: String
        let updated_at: String
        let ingredients: [Ingredient]
        let steps: [Step]
    }

    private struct Snapshot {
        let id: String
        let updatedAt: String
        let ingredients: [[String: String]]
        let steps: [[String: String]]
    }

    private static let revisionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func revision(for recipe: Recipe) -> String {
        revisionFormatter.string(from: recipe.updatedAt)
    }

    private static func snapshot(for recipe: Recipe, sourceRevision: String) -> Snapshot {
        let ingredients = recipe.ingredients.map { ingredient in
            [
                "id": ingredient.id.uuidString.lowercased(),
                "name": ingredient.name,
                "amount": ingredient.amountText,
            ]
        }
        let steps = recipe.steps.map { step in
            [
                "id": step.id.uuidString.lowercased(),
                "instruction": step.instruction,
            ]
        }
        return Snapshot(
            id: recipe.id.uuidString.lowercased(),
            updatedAt: sourceRevision,
            ingredients: ingredients,
            steps: steps
        )
    }

    /// Deterministic SHA-256 over the canonical snapshot. It only needs to be stable
    /// on-device (the server stores it opaquely) so a changed recipe always yields a
    /// different revision hash on approval.
    private static func snapshotHash(for snapshot: Snapshot) throws -> String {
        let payload = SnapshotPayload(
            id: snapshot.id,
            updated_at: snapshot.updatedAt,
            ingredients: snapshot.ingredients.map {
                SnapshotPayload.Ingredient(
                    id: $0["id"] ?? "", name: $0["name"] ?? "", amount: $0["amount"] ?? ""
                )
            },
            steps: snapshot.steps.map {
                SnapshotPayload.Step(id: $0["id"] ?? "", instruction: $0["instruction"] ?? "")
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func parseChange(_ change: RecipeEditWireChange) throws -> RecipeEditChange {
        let parts = change.path.split(separator: ":")
        guard parts.count == 3, let id = UUID(uuidString: String(parts[1])) else {
            throw RecipeEditProposalServiceError.invalidResponse
        }
        switch (parts[0], parts[2]) {
        case ("ingredient", "name"):
            return .ingredientName(id: id, original: change.original, proposed: change.proposed)
        case ("ingredient", "amount"):
            return .ingredientAmount(id: id, original: change.original, proposed: change.proposed)
        case ("step", "instruction"):
            return .stepInstruction(id: id, original: change.original, proposed: change.proposed)
        default:
            throw RecipeEditProposalServiceError.invalidResponse
        }
    }
}

private extension RecipeEditChange {
    /// Mirrors the backend wire path exactly (lowercase RFC UUIDs).
    var wirePath: String {
        switch self {
        case .ingredientName(let id, _, _):
            return "ingredient:\(id.uuidString.lowercased()):name"
        case .ingredientAmount(let id, _, _):
            return "ingredient:\(id.uuidString.lowercased()):amount"
        case .stepInstruction(let id, _, _):
            return "step:\(id.uuidString.lowercased()):instruction"
        }
    }

    var originalText: String {
        switch self {
        case .ingredientName(_, let original, _),
            .ingredientAmount(_, let original, _),
            .stepInstruction(_, let original, _):
            return original
        }
    }

    var proposedText: String {
        switch self {
        case .ingredientName(_, _, let proposed),
            .ingredientAmount(_, _, let proposed),
            .stepInstruction(_, _, let proposed):
            return proposed
        }
    }
}
