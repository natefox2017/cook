// Developer: gengyun
// Purpose: Defines the injectable commercial usage bridge contract and the structured failure vocabulary.

import Foundation

/// Structured outcome vocabulary for the frozen recipe-usage error codes. HTTP statuses are derived
/// only from the server code; the client never authors quota numbers or entitlement claims.
public enum RecipeUsageFailure: Error, Equatable, Sendable {
    public enum Code: String, Sendable {
        case authRequired
        case ownerMismatch
        case notFound
        case idempotencyConflict
        case reservationExpired
        case invalidInput
        case quotaExceeded
        case upgradeRequired
        case configurationUnavailable
        case serviceUnavailable
        case internalError
    }

    /// A transport-level failure that produced no validated server error body.
    case transport(String)
    /// A validated server error decoded from the frozen `RecipeUsageAPIError` shape.
    case api(Code, recoverable: Bool, message: String?, requestID: String?)

    /// Maps a validated server code to its structured client code.
    public init(apiError: RecipeUsageAPIError) {
        let code: Code
        switch apiError.code {
        case "AUTH_REQUIRED": code = .authRequired
        case "OWNER_MISMATCH": code = .ownerMismatch
        case "NOT_FOUND": code = .notFound
        case "IDEMPOTENCY_CONFLICT": code = .idempotencyConflict
        case "RESERVATION_EXPIRED": code = .reservationExpired
        case "INVALID_INPUT": code = .invalidInput
        case "QUOTA_EXCEEDED": code = .quotaExceeded
        case "UPGRADE_REQUIRED": code = .upgradeRequired
        case "CONFIGURATION_UNAVAILABLE": code = .configurationUnavailable
        case "SERVICE_UNAVAILABLE": code = .serviceUnavailable
        default: code = .internalError
        }
        self = .api(code, recoverable: apiError.recoverable, message: apiError.message, requestID: apiError.requestID)
    }

    /// 402 reserve/settle outcomes that must persist an `awaiting_upgrade` operation instead of
    /// discarding the user's input.
    public var isAwaitingUpgrade: Bool {
        guard case let .api(code, _, _, _) = self else { return false }
        return code == .quotaExceeded || code == .upgradeRequired
    }

    /// Transient server/config failures that are safe to retry without changing the operation.
    public var isRetryableService: Bool {
        guard case let .api(code, _, _, _) = self else { return false }
        return code == .serviceUnavailable || code == .configurationUnavailable
    }

    /// The reservation is no longer valid; recovery must reserve a fresh operation, never reuse it.
    public var isReservationExpired: Bool {
        guard case let .api(code, _, _, _) = self else { return false }
        return code == .reservationExpired
    }

    public var isIdempotencyConflict: Bool {
        guard case let .api(code, _, _, _) = self else { return false }
        return code == .idempotencyConflict
    }
}

/// Injectable boundary for the frozen commercial access/usage routes. Implementations own HTTP and
/// authentication; the recovery orchestration above it stays pure and testable.
public protocol RecipeUsageClient: Sendable {
    /// Server-owned access snapshot: entitlement stage and every quota number.
    func access(ownerID: UUID) async throws -> RecipeAccessResponse

    /// Reserves exactly one unit for one candidate; the operation ID is the durable idempotency key.
    func reserve(ownerID: UUID, request: RecipeReservationRequest) async throws -> RecipeReservation

    /// Settles a reserved operation and returns the server-authored stable recipe ID and payload hash.
    func finalize(
        ownerID: UUID,
        operationID: String,
        request: RecipeUsageFinalizeRequest
    ) async throws -> RecipeUsageFinalizeResponse

    /// Confirms device persistence after finalize; never creates a second commit fact.
    func acknowledge(ownerID: UUID, operationID: String) async throws -> RecipeUsageAckResponse

    /// Releases a reservation that was never settled (cancel before finalize).
    func release(ownerID: UUID, operationID: String) async throws -> RecipeReservation
}
