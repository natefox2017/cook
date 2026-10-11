// Developer: gengyun
// Purpose: Sends explicitly approved public snapshots through an injected owner-authenticated transport.

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum RecipeSharePublishingError: Error, Equatable, Sendable {
    case invalidConfiguration
    case notSignedIn
    case accountChanged
    case invalidResponse
    case httpStatus(Int)
}

/// Ephemeral credentials supplied by the App's current auth session, never serialized or cached.
public struct RecipeSharePublishingSession: Sendable {
    public let ownerID: UUID
    public let accessToken: String

    public init(ownerID: UUID, accessToken: String) {
        self.ownerID = ownerID
        self.accessToken = accessToken
    }
}

/// The owner binding is local; management JSON cannot nominate a different owner.
public struct RecipePublishedShare: Sendable {
    public let authenticatedOwnerID: UUID
    public let shareID: UUID
    public let slug: String
    public let shareVersion: Int
    public let scope: RecipeShareScope
    public let createdAt: Date
    public let updatedAt: Date
    public let revokedAt: Date?
    public let publicURL: URL
}

/// Source-only adapter. Creating it does not enable sharing or start a network request.
/// Callers must retain one idempotency key per confirmed create intent across retries.
/// The injected transport must reject redirects before forwarding credentials and bound
/// downloaded bodies to 2 MiB; the response checks below are a second line of defense.
@MainActor
public struct RecipeSharePublishingService {
    private let endpoint: URL
    private let session: @MainActor () async throws -> RecipeSharePublishingSession?
    private let send: @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)

    public init(
        managementEndpoint: URL,
        session: @escaping @MainActor () async throws -> RecipeSharePublishingSession?,
        send: @escaping @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) throws {
        guard managementEndpoint.scheme == "https",
            managementEndpoint.host != nil,
            managementEndpoint.user == nil,
            managementEndpoint.password == nil,
            managementEndpoint.query == nil,
            managementEndpoint.fragment == nil,
            managementEndpoint.path == "/functions/v1/recipe-share-manage"
        else {
            throw RecipeSharePublishingError.invalidConfiguration
        }
        endpoint = managementEndpoint
        self.session = session
        self.send = send
    }

    public func create(
        recipe: Recipe,
        approval: RecipeShareApproval,
        ownerID: UUID,
        idempotencyKey: UUID
    ) async throws -> RecipePublishedShare {
        let body = try approvedBody(
            recipe: recipe, approval: approval, idempotencyKey: idempotencyKey
        )
        let data = try await request(
            method: "POST", ownerID: ownerID, body: body, successfulStatuses: [200, 201]
        )
        let result = try decode(data, ownerID: ownerID)
        guard result.scope == approval.scope, result.revokedAt == nil else {
            throw RecipeSharePublishingError.invalidResponse
        }
        return result
    }

    public func get(shareID: UUID, ownerID: UUID) async throws -> RecipePublishedShare {
        let data = try await request(
            method: "GET", ownerID: ownerID, shareID: shareID, successfulStatuses: [200]
        )
        let result = try decode(data, ownerID: ownerID)
        guard result.shareID == shareID else {
            throw RecipeSharePublishingError.invalidResponse
        }
        return result
    }

    public func update(
        _ share: RecipePublishedShare,
        recipe: Recipe,
        approval: RecipeShareApproval
    ) async throws -> RecipePublishedShare {
        guard share.revokedAt == nil, share.shareVersion < Int.max else {
            throw RecipeSharePublishingError.invalidResponse
        }
        let body = try approvedBody(recipe: recipe, approval: approval, idempotencyKey: nil)
        let data = try await request(
            method: "PUT", ownerID: share.authenticatedOwnerID,
            shareID: share.shareID, body: body,
            version: share.shareVersion, successfulStatuses: [200]
        )
        let result = try decode(data, ownerID: share.authenticatedOwnerID)
        guard result.shareID == share.shareID,
            result.slug == share.slug,
            result.publicURL == share.publicURL,
            result.shareVersion == share.shareVersion + 1,
            result.scope == approval.scope,
            result.revokedAt == nil
        else {
            throw RecipeSharePublishingError.invalidResponse
        }
        return result
    }

    /// Returning normally means the server confirmed 204; no local Recipe is deleted here.
    public func revoke(_ share: RecipePublishedShare) async throws {
        _ = try await request(
            method: "DELETE", ownerID: share.authenticatedOwnerID,
            shareID: share.shareID, successfulStatuses: [204]
        )
    }

    private struct ApprovedBody: Encodable {
        let idempotencyKey: UUID?
        let sourceRecipeID: UUID
        let sourceRecipeUpdatedAt: Date
        let scope: RecipeShareScope
        let hasDistributionRights: Bool
        let snapshot: PublicRecipeSnapshot
    }

    private func approvedBody(
        recipe: Recipe, approval: RecipeShareApproval, idempotencyKey: UUID?
    ) throws -> Data {
        let snapshot = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(ApprovedBody(
            idempotencyKey: idempotencyKey,
            sourceRecipeID: recipe.id,
            sourceRecipeUpdatedAt: approval.expectedUpdatedAt,
            scope: approval.scope,
            hasDistributionRights: approval.hasDistributionRights,
            snapshot: snapshot
        ))
        guard data.count <= 2 * 1024 * 1024 else {
            throw RecipeShareValidationError.contentTooLarge
        }
        return data
    }

    private func currentSession(ownerID: UUID) async throws -> RecipeSharePublishingSession {
        guard let credentials = try await session(),
            !credentials.accessToken.isEmpty,
            !credentials.accessToken.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw RecipeSharePublishingError.notSignedIn
        }
        guard credentials.ownerID == ownerID else {
            throw RecipeSharePublishingError.accountChanged
        }
        return credentials
    }

    private func request(
        method: String, ownerID: UUID, shareID: UUID? = nil,
        body: Data? = nil, version: Int? = nil, successfulStatuses: Set<Int>
    ) async throws -> Data {
        try Task.checkCancellation()
        let credentials = try await currentSession(ownerID: ownerID)
        try Task.checkCancellation()
        let url = shareID.map { endpoint.appendingPathComponent($0.uuidString.lowercased()) }
            ?? endpoint
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let version {
            request.setValue("\"v\(version)\"", forHTTPHeaderField: "If-Match")
        }
        let (data, response) = try await send(request)
        try Task.checkCancellation()
        // A response in flight for A cannot become B's public link after switching accounts.
        _ = try await currentSession(ownerID: ownerID)
        try Task.checkCancellation()
        guard response.url == url else {
            throw RecipeSharePublishingError.invalidResponse
        }
        guard successfulStatuses.contains(response.statusCode) else {
            // Do not surface untrusted response text or JWTs through error descriptions.
            throw RecipeSharePublishingError.httpStatus(response.statusCode)
        }
        guard data.count <= 2 * 1024 * 1024 else {
            throw RecipeSharePublishingError.invalidResponse
        }
        return data
    }

    private struct Metadata: Decodable {
        let shareID: UUID
        let slug: String
        let shareVersion: Int
        let scope: RecipeShareScope
        let createdAt: Date
        let updatedAt: Date
        let revokedAt: Date?
        let publicURL: URL
    }

    private func decode(_ data: Data, ownerID: UUID) throws -> RecipePublishedShare {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            // PostgREST returns timestamptz UTC using +00:00 as well as Z.
            guard value.hasSuffix("Z") || value.hasSuffix("+00:00") else {
                throw RecipeSharePublishingError.invalidResponse
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw RecipeSharePublishingError.invalidResponse
            }
            return date
        }
        guard let metadata = try? decoder.decode(Metadata.self, from: data),
            metadata.shareVersion > 0,
            RecipePublicShareURL.isValid(metadata.publicURL),
            metadata.publicURL.lastPathComponent == metadata.slug
        else {
            throw RecipeSharePublishingError.invalidResponse
        }
        return RecipePublishedShare(
            authenticatedOwnerID: ownerID, shareID: metadata.shareID,
            slug: metadata.slug, shareVersion: metadata.shareVersion,
            scope: metadata.scope, createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt, revokedAt: metadata.revokedAt,
            publicURL: metadata.publicURL
        )
    }
}
