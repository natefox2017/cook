// Developer: gengyun
// Purpose: App-level adapter that wires the core RecipeTranslationClient to the signed-in session
//          and persists an approved translation variant through RecipeStore.

import CryptoKit
import Foundation
import RecipeCore
import Supabase

enum RecipeTranslationCoordinatorError: LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            RecipeLanguage.localized("The translation service is not configured.")
        }
    }
}

/// Session-scoped translation entry point. It owns only the credential minting for the
/// shared `RecipeTranslationClient`; provider generation, quota settlement, and revision
/// validation stay on the backend. Saving is a local `upsert` of the deterministic variant.
@MainActor
final class RecipeTranslationCoordinator {
    private let client: RecipeTranslationClient

    init(bundle: Bundle = .main) throws {
        guard
            let origin = bundle.object(forInfoDictionaryKey: "RecipeSupabaseURL") as? String,
            let url = URL(string: origin),
            url.scheme == "https",
            let host = url.host,
            host.hasSuffix(".supabase.co")
        else {
            throw RecipeTranslationCoordinatorError.invalidConfiguration
        }

        let functionBaseURL = url.appendingPathComponent("functions/v1")
        client = RecipeTranslationClient(
            functionBaseURL: functionBaseURL,
            authenticate: {
                let credential: RecipeDraftCredential? = await MainActor.run {
                    let auth = RecipeAuthService.shared
                    guard case .signedIn(let ownerID, _) = auth.state else {
                        return nil
                    }
                    guard let session = RecipeSupabase.client.auth.currentSession,
                        session.user.id == ownerID, !session.isExpired
                    else {
                        return nil
                    }
                    return RecipeDraftCredential(
                        ownerID: ownerID,
                        generation: RecipeTranslationBridge.generationUUID(
                            auth.sharingSessionGeneration),
                        bearerToken: session.accessToken
                    )
                }
                guard let credential else {
                    throw RecipeTranslationClientError.authenticationFailed
                }
                return credential
            },
            isOwnerCurrent: { credential in
                await MainActor.run {
                    let auth = RecipeAuthService.shared
                    guard case .signedIn(let ownerID, _) = auth.state,
                        ownerID == credential.ownerID
                    else {
                        return false
                    }
                    return RecipeTranslationBridge.generationUUID(auth.sharingSessionGeneration)
                        == credential.generation
                }
            }
        )
    }

    /// Requests a reviewable translation. The source recipe is never mutated; canceling the
    /// returned proposal has no side effects.
    func translate(
        recipe: Recipe,
        target: RecipeTranslationTarget
    ) async throws -> RecipeTranslationProposal {
        guard let ownerID = Self.currentOwnerID() else {
            throw RecipeTranslationClientError.authenticationFailed
        }
        let generation = Self.currentGeneration()
        let fingerprint = Self.fingerprint(recipe: recipe, target: target)

        // Reuse the metering identity only for the exact same request (owner + recipe id + revision
        // + target + translatable content). Any change is a separate, independently persisted attempt.
        let proposalID: UUID
        if let pending = try Self.loadPending(ownerID: ownerID, fingerprint: fingerprint) {
            proposalID = pending.proposalID
        } else {
            proposalID = UUID()
            try Self.savePending(ownerID: ownerID, fingerprint: fingerprint, proposalID: proposalID)
        }

        let proposal: RecipeTranslationProposal
        do {
            proposal = try await client.translate(
                RecipeTranslationRequest(recipe: recipe, target: target, proposalID: proposalID))
        } catch {
            // Failure / unknown outcome / cancellation: retain this attempt so a same-request retry
            // or sheet reentry replays the same metered operation instead of charging twice.
            throw error
        }

        // Success fence: the account and session must still be the one that dispatched this attempt.
        guard Self.currentOwnerID() == ownerID, Self.currentGeneration() == generation else {
            throw RecipeTranslationClientError.ownerChanged
        }
        try Self.clearPending(ownerID: ownerID, fingerprint: fingerprint, proposalID: proposalID)
        return proposal
    }

    /// Approves a reviewed proposal into a deterministic variant and persists it locally.
    /// The variant id encodes the source recipe and target locale, so a re-translation of the
    /// same recipe never creates a duplicate. The variant carries its `translationProvenance`
    /// (source recipe id, target locale, and provenance marker) into durable saved state.
    func save(
        proposal: RecipeTranslationProposal,
        original: Recipe,
        in store: RecipeStore
    ) throws -> Recipe {
        let variant = try proposal.approvedVariant(from: original)
        try store.upsert(variant)
        return variant
    }

    // MARK: - Pending attempt identity

    /// One durable in-flight metering identity. The store is keyed by owner + request fingerprint,
    /// so every distinct request keeps its own proposal id and a failed attempt never overwrites
    /// another. No JWT or whole-recipe payload is persisted.
    private struct PendingAttempt: Codable, Equatable {
        let proposalID: UUID
    }

    private static func currentOwnerID() -> UUID? {
        guard case .signedIn(let ownerID, _) = RecipeAuthService.shared.state else {
            return nil
        }
        return ownerID
    }

    private static func currentGeneration() -> Int {
        RecipeAuthService.shared.sharingSessionGeneration
    }

    /// Canonical fingerprint of the exact request: recipe id, revision, target locale, and the
    /// ordered translatable fields (optional source preserved as null vs empty). Object keys are
    /// sorted via the encoder; ingredient/step array order is preserved. Never separator-joined.
    private static func fingerprint(recipe: Recipe, target: RecipeTranslationTarget) -> String {
        struct Content: Encodable {
            struct Ingredient: Encodable {
                let id: String
                let name: String
                let amountText: String

                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case amountText = "amount_text"
                }
            }

            struct Step: Encodable {
                let id: String
                let title: String
                let instruction: String
            }

            let recipeID: String
            let revision: Double
            let targetLocale: String
            let title: String
            let summary: String
            let sourceURL: String?
            let sourceName: String?
            let ingredients: [Ingredient]
            let steps: [Step]

            enum CodingKeys: String, CodingKey {
                case recipeID = "recipe_id"
                case revision
                case targetLocale = "target_locale"
                case title
                case summary
                case sourceURL = "source_url"
                case sourceName = "source_name"
                case ingredients
                case steps
            }
        }

        let content = Content(
            recipeID: recipe.id.uuidString.lowercased(),
            revision: recipe.updatedAt.timeIntervalSince1970,
            targetLocale: target.rawValue,
            title: recipe.title,
            summary: recipe.summary,
            sourceURL: recipe.sourceURL,
            sourceName: recipe.sourceName,
            ingredients: recipe.ingredients.map {
                Content.Ingredient(
                    id: $0.id.uuidString.lowercased(),
                    name: $0.name,
                    amountText: $0.amountText
                )
            },
            steps: recipe.steps.map {
                Content.Step(
                    id: $0.id.uuidString.lowercased(),
                    title: $0.title,
                    instruction: $0.instruction
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Strings, numbers and arrays of strings cannot fail to encode.
        let data = try! encoder.encode(content)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static var pendingFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recipe-translation-pending.json")
    }

    /// Fixed-width concatenation of the lowercase owner UUID and the 64-hex fingerprint; no
    /// separator is needed because both components have fixed length.
    private static func identityKey(ownerID: UUID, fingerprint: String) -> String {
        ownerID.uuidString.lowercased() + fingerprint
    }

    /// Loads the store. Only a missing file is a valid empty store; any read or decode failure
    /// throws (fail closed) and never overwrites unknown persisted work.
    private static func loadStore() throws -> [String: PendingAttempt] {
        let url = pendingFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecipeTranslationClientError.invalidResponse
        }
        do {
            return try JSONDecoder().decode([String: PendingAttempt].self, from: data)
        } catch {
            throw RecipeTranslationClientError.invalidResponse
        }
    }

    private static func loadPending(ownerID: UUID, fingerprint: String) throws -> PendingAttempt? {
        try loadStore()[identityKey(ownerID: ownerID, fingerprint: fingerprint)]
    }

    private static func savePending(
        ownerID: UUID,
        fingerprint: String,
        proposalID: UUID
    ) throws {
        var store = try loadStore()
        store[identityKey(ownerID: ownerID, fingerprint: fingerprint)] = PendingAttempt(
            proposalID: proposalID)
        let data = try JSONEncoder().encode(store)
        try FileManager.default.createDirectory(
            at: pendingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: pendingFileURL, options: .atomic)
    }

    private static func clearPending(
        ownerID: UUID,
        fingerprint: String,
        proposalID: UUID
    ) throws {
        var store = try loadStore()
        let key = identityKey(ownerID: ownerID, fingerprint: fingerprint)
        // Clear only this exact stored attempt; never a different unknown attempt.
        guard store[key]?.proposalID == proposalID else {
            return
        }
        store[key] = nil
        let data = try JSONEncoder().encode(store)
        try data.write(to: pendingFileURL, options: .atomic)
    }
}

/// Small deterministic bridge so the translation client's account-switch credential can be
/// minted from `RecipeAuthService`'s monotonic session generation without new global state.
/// Mirrors the draft editor's frozen UUID mapping so credentials stay interchangeable.
private enum RecipeTranslationBridge {
    static func generationUUID(_ generation: Int) -> UUID {
        // A 64-bit counter always renders 16 hex digits; zero-padding keeps a valid UUID string.
        let text = String(format: "%032llx", UInt64(bitPattern: Int64(generation)))
        return UUID(uuidString: text) ?? UUID()
    }
}
