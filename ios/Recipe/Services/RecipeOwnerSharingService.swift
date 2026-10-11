// Developer: gengyun
// Purpose: Connects explicit sharing to the current App session and bounded credential-safe transport.

import Foundation
import RecipeCore
import Supabase

@MainActor
final class RecipeOwnerSharingService {
    static let shared = RecipeOwnerSharingService()

    private let auth: RecipeAuthService
    private let client: SupabaseClient
    private let endpoint: URL?
    private let send: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(
        auth: RecipeAuthService = .shared,
        client: SupabaseClient = RecipeSupabase.client,
        verifiedManagementEndpoint: URL? = nil,
        send: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse) = {
            try await RecipeShareHTTPTransport.send($0)
        }
    ) {
        self.auth = auth
        self.client = client
        // No endpoint ships until the isolated deployment and public host are verified.
        // An ordinary Supabase auth URL is not evidence of a deployed sharing service.
        endpoint = verifiedManagementEndpoint
        self.send = send
    }

    /// Build capability only. A missing endpoint does not prove that remote copies are absent.
    /// This initially unavailable product preserves its existing private deletion flow;
    /// configured owner-sharing builds must use the authoritative deletion coordinator.
    var isConfiguredForOwnerSharing: Bool {
        endpoint != nil
    }

    var currentOwnerID: UUID? {
        guard case .signedIn(let ownerID, _) = auth.state,
            let session = client.auth.currentSession,
            session.user.id == ownerID,
            !session.user.isAnonymous,
            !session.isExpired
        else {
            return nil
        }
        return ownerID
    }

    func publishingClient() throws -> RecipeSharePublishingService? {
        guard let endpoint else { return nil }
        let sessionGeneration = auth.sharingSessionGeneration
        return try RecipeSharePublishingService(
            managementEndpoint: endpoint,
            session: {
                guard self.auth.sharingSessionGeneration == sessionGeneration,
                    let ownerID = self.currentOwnerID,
                    let session = self.client.auth.currentSession
                else {
                    return nil
                }
                // Read credentials on every call; never persist a JWT or refresh another account.
                return RecipeSharePublishingSession(
                    ownerID: ownerID,
                    accessToken: session.accessToken
                )
            },
            send: send
        )
    }

    func consentState(recipeID: UUID, store: RecipeStore) -> RecipeShareConsentState {
        let generation = auth.sharingSessionGeneration
        return RecipeShareConsentState(
            recipeID: recipeID,
            service: try? publishingClient(),
            currentOwnerID: {
                guard self.auth.sharingSessionGeneration == generation else {
                    return nil
                }
                return self.currentOwnerID
            },
            readRecipe: { id in
                store.recipes.first { $0.id == id }
            },
            loadsOwnerRecords: true
        )
    }

    /// Keeps the private recipe unless every matching active public copy was confirmed revoked.
    func deleteRecipe(recipeID: UUID, store: RecipeStore) async throws {
        guard let recipe = store.recipes.first(where: { $0.id == recipeID }) else { return }
        guard let service = try publishingClient() else {
            throw RecipeSharePublishingError.invalidConfiguration
        }
        guard let ownerID = currentOwnerID else {
            throw RecipeSharePublishingError.notSignedIn
        }
        let generation = auth.sharingSessionGeneration
        let copies = try await service.list(recipeID: recipeID, ownerID: ownerID)
        for copy in copies where copy.revokedAt == nil {
            try Task.checkCancellation()
            guard generation == auth.sharingSessionGeneration, currentOwnerID == ownerID else {
                throw RecipeSharePublishingError.accountChanged
            }
            try await service.revoke(copy)
        }
        try Task.checkCancellation()
        guard generation == auth.sharingSessionGeneration, currentOwnerID == ownerID else {
            throw RecipeSharePublishingError.accountChanged
        }
        guard store.recipes.first(where: { $0.id == recipeID })?.updatedAt == recipe.updatedAt
        else {
            throw RecipeShareValidationError.staleRecipe
        }
        try store.deleteRecipe(id: recipeID)
    }

}
