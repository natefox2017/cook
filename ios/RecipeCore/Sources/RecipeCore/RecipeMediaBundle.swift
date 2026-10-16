// Developer: gengyun
// Purpose: Frozen DEV-78 media-import save DTOs and injectable client boundary for the recipe-media-save endpoints.

import Foundation

/// Per-member reservation returned by `POST /recipe-media-save/reserve`. The media member has a nil
/// `candidateID`; each candidate member carries its stable `candidate_id`.
public struct RecipeMediaReservation: Decodable, Hashable, Sendable {
    public let candidateID: String?
    public let operationID: String
    public let ownerID: String
    public let capability: String
    public let periodStart: String?
    public let policyVersion: Int
    public let tierAtReserve: String
    public let reservedUnits: Int
    public let status: String
    public let reservedUntil: String

    private enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case operationID = "operation_id"
        case ownerID = "owner_id"
        case capability
        case periodStart = "period_start"
        case policyVersion = "policy_version"
        case tierAtReserve = "tier_at_reserve"
        case reservedUnits = "reserved_units"
        case status
        case reservedUntil = "reserved_until"
    }
}

/// Success payload of `POST /recipe-media-save/reserve`.
public struct RecipeMediaBundleReserveResponse: Decodable, Hashable, Sendable {
    public let code: String
    public let operationID: String
    public let media: RecipeMediaReservation
    public let candidates: [RecipeMediaReservation]

    private enum CodingKeys: String, CodingKey {
        case code
        case operationID = "operation_id"
        case media
        case candidates
    }
}

/// The recipe-media-save error body is a bare `{code, message}` pair (unlike recipe-usage's validated
/// `{code,message,recoverable,request_id}` shape).
public struct RecipeMediaSaveAPIError: Decodable, Hashable, Sendable, Error {
    public let code: String
    public let message: String
}

/// Response of `POST /recipe-media-save/finalize` and `/release`; the `code` is authoritative (the HTTP
/// status is always 200), so the caller must read `code` to know whether the media settled.
public struct RecipeMediaActionResponse: Decodable, Hashable, Sendable {
    public let code: String
    public let operationID: String

    private enum CodingKeys: String, CodingKey {
        case code
        case operationID = "operation_id"
    }
}

/// Injectable boundary for the DEV-78 media-import save endpoints. Per-candidate smart_import
/// finalize/release stays the existing DEV-430 recipe-usage flow; only the media_import unit is
/// reserved/finalized/released here.
public protocol RecipeMediaSaveClient: Sendable {
    /// Atomically reserves the media_import unit plus one smart_import unit per selected candidate.
    func reserveMediaBundle(
        ownerID: UUID,
        jobID: UUID,
        candidateIDs: [String]
    ) async throws -> RecipeMediaBundleReserveResponse

    /// Settles the reserved media_import unit (binding the durable owned job as a media task). The
    /// request body is only `{job_id}`; the server derives the payload/hash from the owned job result.
    func finalizeMedia(ownerID: UUID, jobID: UUID) async throws -> RecipeMediaActionResponse

    /// Best-effort release of the reserved media_import unit that will not be settled.
    func releaseMedia(ownerID: UUID, jobID: UUID) async throws -> RecipeMediaActionResponse
}
