// Developer: gengyun
// Purpose: App-level adapter that wires the core RecipeTranslationClient to the signed-in session
//          and persists an approved translation variant through RecipeStore.

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
        try await client.translate(RecipeTranslationRequest(recipe: recipe, target: target))
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
