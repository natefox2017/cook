// Developer: gengyun
// Purpose: Decode and encode the frozen DEV-425 commercial access/usage wire contract independently of billing and save internals.

import Foundation

public enum RecipeAccessContractError: Error, Equatable, Sendable {
    case invalidInput
    case invalidResponse
}

private struct AccessKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    init?(intValue: Int) {
        return nil
    }
}

/// Required members still have to exist; unknown wire keys are never ignored.
private func accessContainer(_ decoder: any Decoder, _ keys: [String]) throws
    -> KeyedDecodingContainer<AccessKey>
{
    let container = try decoder.container(keyedBy: AccessKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == Set(keys) else {
        throw RecipeAccessContractError.invalidResponse
    }
    return container
}

private func accessDecode<T: Decodable>(
    _ type: T.Type, _ container: KeyedDecodingContainer<AccessKey>, _ key: String
) throws -> T {
    try container.decode(type, forKey: AccessKey(stringValue: key))
}

private func accessRequire(_ condition: Bool) throws {
    guard condition else {
        throw RecipeAccessContractError.invalidResponse
    }
}

private func accessText(_ text: String, _ maximum: Int) -> Bool {
    (1...maximum).contains(text.unicodeScalars.count)
}

/// Canonical lowercase RFC UUID text; uppercase is rejected.
private func accessUUID(_ value: String) -> Bool {
    value.range(
        of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
        options: .regularExpression) == value.startIndex..<value.endIndex
}

private func accessHash(_ value: String) -> Bool {
    value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) == value
        .startIndex..<value.endIndex
}

private func accessDaysInMonth(_ month: Int, _ year: Int) -> Int? {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12:
        return 31
    case 4, 6, 9, 11:
        return 30
    case 2:
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    default:
        return nil
    }
}

/// ISO 8601 UTC with optional millisecond fraction, validated against a real calendar date without
/// normalization. Mirrors the TypeScript round-trip check: invalid dates (e.g. 2026-02-30) reject,
/// and the fractional second is preserved so reset_at/period_start comparisons match JS exactly.
private let accessTimestampRegex = try! NSRegularExpression(
    pattern: #"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,3}))?Z$"#)

private func accessTimestampDate(_ value: String) -> Date? {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard
        let match = accessTimestampRegex.firstMatch(in: value, range: range),
        match.range == range
    else {
        return nil
    }
    func field(_ index: Int) -> Int {
        let r = match.range(at: index)
        return Int(value[Range(r, in: value)!])!
    }
    let year = field(1)
    let month = field(2)
    let day = field(3)
    let hour = field(4)
    let minute = field(5)
    let second = field(6)
    guard
        (1...12).contains(month), (0...23).contains(hour), (0...59).contains(minute),
        (0...59).contains(second), let days = accessDaysInMonth(month, year),
        (1...days).contains(day)
    else {
        return nil
    }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    let fraction = match.range(at: 7)
    if fraction.location != NSNotFound {
        let fractionRange = Range(fraction, in: value)!
        let millis = Int(
            value[fractionRange].padding(toLength: 3, withPad: "0", startingAt: 0))!
        components.nanosecond = millis * 1_000_000
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: components)
}

private func accessTimestamp(_ value: String) -> Bool {
    accessTimestampDate(value) != nil
}

/// Counts above this bound are rejected so Swift and TypeScript agree on representable integers.
private let accessSafeIntegerMax = 9_007_199_254_740_991

private func accessNonNegative(_ value: Int) -> Bool {
    value >= 0 && value <= accessSafeIntegerMax
}

private func accessPositive(_ value: Int) -> Bool {
    value >= 1 && value <= accessSafeIntegerMax
}

/// Candidate IDs are bounded opaque strings, not UUIDs: candidateIdentity.ts emits
/// `candidate-v2-<32hex>[-n]` and legacy `candidate-<index>-<hash>` remains intact.
private func accessCandidateID(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) == value
        .startIndex..<value.endIndex
}

/// One candidate per usage operation; the server verifies membership of the owned job result.
private func accessCandidateIDs(_ values: [String]) -> Bool {
    values.count == 1 && values.allSatisfy(accessCandidateID)
}

/// V1 save routes accept only smart_import (import job source) or ai_edit (draft approval source).
private func accessSaveRoute(_ capability: RecipeCapability, _ source: RecipeUsageSource) -> Bool {
    switch capability {
    case .smartImport:
        return source.origin == .importJob && source.candidateIDs?.count == 1
    case .aiEdit:
        return source.origin == .draftApproval
    default:
        return false
    }
}

/// Fixed commercial capability vocabulary. Unknown wire identifiers are rejected.
public enum RecipeCapability: String, Codable, Hashable, Sendable {
    case smartImport = "smart_import"
    case aiEdit = "ai_edit"
    case handsFreeCooking = "hands_free_cooking"
    case weeklyTemplates = "weekly_templates"
    case weeklyGroceries = "weekly_groceries"
    case autoPlan = "auto_plan"
    case recipeQuestion = "recipe_question"
    case recipeTranslation = "recipe_translation"
    case mediaImport = "media_import"
    case pdfExport = "pdf_export"

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeCapability(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// freeTest ships without StoreKit networking or purchase entry points; commercial is an
/// explicit build configuration with a separate server-side switch.
public enum RecipeReleaseStage: String, Decodable, Hashable, Sendable {
    case freeTest = "freeTest"
    case commercial = "commercial"

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeReleaseStage(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }
}

public enum RecipeEntitlementStatus: String, Decodable, Hashable, Sendable {
    case free
    case premium
    case expired

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeEntitlementStatus(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }
}

public enum RecipeQuotaPeriodType: String, Decodable, Hashable, Sendable {
    case isoWeek = "iso_week"
    case utcMonth = "utc_month"
    case lifetime

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeQuotaPeriodType(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }
}

public enum RecipeTier: String, Decodable, Hashable, Sendable {
    case free
    case premium

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeTier(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }
}

public enum RecipeReservationStatus: String, Decodable, Hashable, Sendable {
    case reserved
    case dispatchedUnknown = "dispatched_unknown"
    case committed
    case released
    case expired

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeReservationStatus(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }
}

public enum RecipeUsageOrigin: String, Codable, Hashable, Sendable {
    case importJob = "import_job"
    case draftApproval = "draft_approval"

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RecipeUsageOrigin(rawValue: value) else {
            throw RecipeAccessContractError.invalidResponse
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The persisted origin a usage operation settles against, so the server loads a trusted result
/// instead of a client success flag. An import settle references one owned job plus exactly one
/// candidate; an AI edit references the persisted pending draft session and turn.
public struct RecipeUsageSource: Codable, Hashable, Sendable {
    public let origin: RecipeUsageOrigin
    public let jobID: String?
    public let candidateIDs: [String]?
    public let sessionID: String?
    public let turnRequestID: String?

    public init(importJobID: String, candidateIDs: [String]) throws {
        guard accessUUID(importJobID) && accessCandidateIDs(candidateIDs) else {
            throw RecipeAccessContractError.invalidInput
        }
        self.origin = .importJob
        self.jobID = importJobID
        self.candidateIDs = candidateIDs
        self.sessionID = nil
        self.turnRequestID = nil
    }

    public init(sessionID: String, turnRequestID: String) throws {
        guard accessUUID(sessionID) && accessUUID(turnRequestID) else {
            throw RecipeAccessContractError.invalidInput
        }
        self.origin = .draftApproval
        self.jobID = nil
        self.candidateIDs = nil
        self.sessionID = sessionID
        self.turnRequestID = turnRequestID
    }

    private enum CodingKeys: String, CodingKey {
        case origin
        case jobID = "job_id"
        case candidateIDs = "candidate_ids"
        case sessionID = "session_id"
        case turnRequestID = "turn_request_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder, ["origin", "job_id", "candidate_ids", "session_id", "turn_request_id"])
        let origin = try accessDecode(RecipeUsageOrigin.self, container, "origin")
        let job = try accessDecode(String?.self, container, "job_id")
        let candidates = try accessDecode([String]?.self, container, "candidate_ids")
        let session = try accessDecode(String?.self, container, "session_id")
        let turn = try accessDecode(String?.self, container, "turn_request_id")
        switch origin {
        case .importJob:
            guard
                let job, let candidates, session == nil, turn == nil, accessUUID(job),
                accessCandidateIDs(candidates)
            else {
                throw RecipeAccessContractError.invalidResponse
            }
            self.origin = .importJob
            self.jobID = job
            self.candidateIDs = candidates
            self.sessionID = nil
            self.turnRequestID = nil
        case .draftApproval:
            guard
                job == nil, candidates == nil, let session, let turn,
                accessUUID(session), accessUUID(turn)
            else {
                throw RecipeAccessContractError.invalidResponse
            }
            self.origin = .draftApproval
            self.jobID = nil
            self.candidateIDs = nil
            self.sessionID = session
            self.turnRequestID = turn
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(jobID, forKey: .jobID)
        try container.encode(candidateIDs, forKey: .candidateIDs)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(turnRequestID, forKey: .turnRequestID)
    }
}

/// Unit vocabulary is fixed so Swift and TypeScript agree on what a settled unit counts.
public struct RecipeQuota: Decodable, Hashable, Sendable {
    public let units: String
    public let periodType: RecipeQuotaPeriodType
    public let periodStart: String?
    public let resetAt: String?
    public let limit: Int
    public let used: Int
    public let reserved: Int
    public let remaining: Int

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder,
            ["units", "period_type", "period_start", "reset_at", "limit", "used", "reserved",
                "remaining"])
        units = try accessDecode(String.self, container, "units")
        periodType = try accessDecode(RecipeQuotaPeriodType.self, container, "period_type")
        periodStart = try accessDecode(String?.self, container, "period_start")
        resetAt = try accessDecode(String?.self, container, "reset_at")
        limit = try accessDecode(Int.self, container, "limit")
        used = try accessDecode(Int.self, container, "used")
        reserved = try accessDecode(Int.self, container, "reserved")
        remaining = try accessDecode(Int.self, container, "remaining")
        try accessRequire(
            [
                "successful_imports", "successful_edits", "successful_answers",
                "successful_translations", "media_tasks",
            ].contains(units))
        try accessRequire(
            accessNonNegative(limit) && accessNonNegative(used) && accessNonNegative(reserved)
                && accessNonNegative(remaining))
        // A downgraded owner can carry used > limit (observed counters) with remaining clamped to zero.
        try accessRequire(remaining == max(0, limit - used - reserved))
        switch periodType {
        case .lifetime:
            try accessRequire(periodStart == nil && resetAt == nil)
        case .isoWeek, .utcMonth:
            guard
                let start = periodStart, let reset = resetAt,
                let startDate = accessTimestampDate(start),
                let resetDate = accessTimestampDate(reset)
            else {
                throw RecipeAccessContractError.invalidResponse
            }
            try accessRequire(resetDate > startDate)
        }
    }
}

public struct RecipeCapabilityAccess: Decodable, Hashable, Sendable {
    public let id: RecipeCapability
    public let entitled: Bool
    public let quota: RecipeQuota?

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["id", "entitled", "quota"])
        id = try accessDecode(RecipeCapability.self, container, "id")
        entitled = try accessDecode(Bool.self, container, "entitled")
        quota = try accessDecode(RecipeQuota?.self, container, "quota")
    }
}

public struct RecipeEntitlement: Decodable, Hashable, Sendable {
    public let status: RecipeEntitlementStatus
    public let validUntil: String?

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["status", "valid_until"])
        status = try accessDecode(RecipeEntitlementStatus.self, container, "status")
        validUntil = try accessDecode(String?.self, container, "valid_until")
        if status == .free {
            try accessRequire(validUntil == nil)
        }
        if let valid = validUntil {
            try accessRequire(accessTimestamp(valid))
        }
    }
}

public struct RecipeAccessResponse: Decodable, Hashable, Sendable {
    public let ownerID: String
    public let serverTime: String
    public let policyVersion: Int
    public let stage: RecipeReleaseStage
    public let entitlement: RecipeEntitlement
    public let capabilities: [RecipeCapabilityAccess]

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder, ["owner_id", "server_time", "policy_version", "stage", "entitlement",
                "capabilities"])
        ownerID = try accessDecode(String.self, container, "owner_id")
        serverTime = try accessDecode(String.self, container, "server_time")
        policyVersion = try accessDecode(Int.self, container, "policy_version")
        stage = try accessDecode(RecipeReleaseStage.self, container, "stage")
        entitlement = try accessDecode(RecipeEntitlement.self, container, "entitlement")
        capabilities = try accessDecode([RecipeCapabilityAccess].self, container, "capabilities")
        try accessRequire(
            accessUUID(ownerID) && accessTimestamp(serverTime) && accessPositive(policyVersion))
        try accessRequire(!capabilities.isEmpty && capabilities.count <= 10)
        try accessRequire(Set(capabilities.map(\.id)).count == capabilities.count)
    }
}

public struct RecipeReservationRequest: Codable, Hashable, Sendable {
    public let operationID: String
    public let capability: RecipeCapability
    public let inputHash: String
    public let estimatedUnits: Int
    public let source: RecipeUsageSource

    private enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case capability
        case inputHash = "input_hash"
        case estimatedUnits = "estimated_units"
        case source
    }

    public init(
        operationID: String, capability: RecipeCapability, inputHash: String,
        estimatedUnits: Int, source: RecipeUsageSource
    ) throws {
        // One unit per operation: smart_import settles one candidate, ai_edit one approved edit.
        guard accessUUID(operationID) && accessHash(inputHash) && estimatedUnits == 1 else {
            throw RecipeAccessContractError.invalidInput
        }
        guard accessSaveRoute(capability, source) else {
            throw RecipeAccessContractError.invalidInput
        }
        self.operationID = operationID
        self.capability = capability
        self.inputHash = inputHash
        self.estimatedUnits = estimatedUnits
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder, ["operation_id", "capability", "input_hash", "estimated_units", "source"])
        let operationID = try accessDecode(String.self, container, "operation_id")
        let capability = try accessDecode(RecipeCapability.self, container, "capability")
        let inputHash = try accessDecode(String.self, container, "input_hash")
        let estimatedUnits = try accessDecode(Int.self, container, "estimated_units")
        let source = try accessDecode(RecipeUsageSource.self, container, "source")
        do {
            try self.init(
                operationID: operationID, capability: capability, inputHash: inputHash,
                estimatedUnits: estimatedUnits, source: source)
        } catch {
            throw RecipeAccessContractError.invalidResponse
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationID, forKey: .operationID)
        try container.encode(capability, forKey: .capability)
        try container.encode(inputHash, forKey: .inputHash)
        try container.encode(estimatedUnits, forKey: .estimatedUnits)
        try container.encode(source, forKey: .source)
    }
}

public struct RecipeReservation: Decodable, Hashable, Sendable {
    public let operationID: String
    public let ownerID: String
    public let capability: RecipeCapability
    public let periodStart: String?
    public let policyVersion: Int
    public let tierAtReserve: RecipeTier
    public let reservedUnits: Int
    public let status: RecipeReservationStatus
    public let reservedUntil: String

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder,
            [
                "operation_id", "owner_id", "capability", "period_start", "policy_version",
                "tier_at_reserve", "reserved_units", "status", "reserved_until",
            ])
        operationID = try accessDecode(String.self, container, "operation_id")
        ownerID = try accessDecode(String.self, container, "owner_id")
        capability = try accessDecode(RecipeCapability.self, container, "capability")
        periodStart = try accessDecode(String?.self, container, "period_start")
        policyVersion = try accessDecode(Int.self, container, "policy_version")
        tierAtReserve = try accessDecode(RecipeTier.self, container, "tier_at_reserve")
        reservedUnits = try accessDecode(Int.self, container, "reserved_units")
        status = try accessDecode(RecipeReservationStatus.self, container, "status")
        reservedUntil = try accessDecode(String.self, container, "reserved_until")
        try accessRequire(
            accessUUID(operationID) && accessUUID(ownerID) && accessPositive(policyVersion))
        try accessRequire(accessPositive(reservedUnits) && accessTimestamp(reservedUntil))
        if let start = periodStart {
            try accessRequire(accessTimestamp(start))
        }
    }
}

public struct RecipeUsageCommitRequest: Codable, Hashable, Sendable {
    public let capability: RecipeCapability
    public let inputHash: String
    public let source: RecipeUsageSource

    private enum CodingKeys: String, CodingKey {
        case capability
        case inputHash = "input_hash"
        case source
    }

    public init(capability: RecipeCapability, inputHash: String, source: RecipeUsageSource) throws {
        guard accessHash(inputHash) && accessSaveRoute(capability, source) else {
            throw RecipeAccessContractError.invalidInput
        }
        self.capability = capability
        self.inputHash = inputHash
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["capability", "input_hash", "source"])
        let capability = try accessDecode(RecipeCapability.self, container, "capability")
        let inputHash = try accessDecode(String.self, container, "input_hash")
        let source = try accessDecode(RecipeUsageSource.self, container, "source")
        do {
            try self.init(capability: capability, inputHash: inputHash, source: source)
        } catch {
            throw RecipeAccessContractError.invalidResponse
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capability, forKey: .capability)
        try container.encode(inputHash, forKey: .inputHash)
        try container.encode(source, forKey: .source)
    }
}

public struct RecipeUsageCommitResponse: Decodable, Hashable, Sendable {
    public let operationID: String
    public let status: String
    public let committedUnits: Int
    public let periodStart: String?

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder, ["operation_id", "status", "committed_units", "period_start"])
        operationID = try accessDecode(String.self, container, "operation_id")
        status = try accessDecode(String.self, container, "status")
        committedUnits = try accessDecode(Int.self, container, "committed_units")
        periodStart = try accessDecode(String?.self, container, "period_start")
        try accessRequire(accessUUID(operationID) && status == "committed")
        try accessRequire(committedUnits == 1)
        if let start = periodStart {
            try accessRequire(accessTimestamp(start))
        }
    }
}

/// Import/edit settle through the finalize alias; the server authoritatively produces the stable
/// recipe ID and payload hash and never accepts a client success boolean. One candidate is settled
/// per finalize, so the single recipe ID is unambiguous.
public struct RecipeUsageFinalizeRequest: Codable, Hashable, Sendable {
    public let capability: RecipeCapability
    public let inputHash: String
    public let source: RecipeUsageSource

    private enum CodingKeys: String, CodingKey {
        case capability
        case inputHash = "input_hash"
        case source
    }

    public init(capability: RecipeCapability, inputHash: String, source: RecipeUsageSource) throws {
        guard accessHash(inputHash) && accessSaveRoute(capability, source) else {
            throw RecipeAccessContractError.invalidInput
        }
        self.capability = capability
        self.inputHash = inputHash
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["capability", "input_hash", "source"])
        let capability = try accessDecode(RecipeCapability.self, container, "capability")
        let inputHash = try accessDecode(String.self, container, "input_hash")
        let source = try accessDecode(RecipeUsageSource.self, container, "source")
        do {
            try self.init(capability: capability, inputHash: inputHash, source: source)
        } catch {
            throw RecipeAccessContractError.invalidResponse
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capability, forKey: .capability)
        try container.encode(inputHash, forKey: .inputHash)
        try container.encode(source, forKey: .source)
    }
}

public struct RecipeUsageFinalizeResponse: Decodable, Hashable, Sendable {
    public let operationID: String
    public let status: String
    public let recipeID: String
    public let payloadHash: String
    public let committedUnits: Int
    public let periodStart: String?

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(
            decoder,
            ["operation_id", "status", "recipe_id", "payload_hash", "committed_units",
                "period_start"])
        operationID = try accessDecode(String.self, container, "operation_id")
        status = try accessDecode(String.self, container, "status")
        recipeID = try accessDecode(String.self, container, "recipe_id")
        payloadHash = try accessDecode(String.self, container, "payload_hash")
        committedUnits = try accessDecode(Int.self, container, "committed_units")
        periodStart = try accessDecode(String?.self, container, "period_start")
        try accessRequire(accessUUID(operationID) && status == "finalized")
        try accessRequire(accessUUID(recipeID) && accessHash(payloadHash))
        try accessRequire(committedUnits == 1)
        if let start = periodStart {
            try accessRequire(accessTimestamp(start))
        }
    }
}

public struct RecipeUsageAckResponse: Decodable, Hashable, Sendable {
    public let operationID: String
    public let status: String

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["operation_id", "status"])
        operationID = try accessDecode(String.self, container, "operation_id")
        status = try accessDecode(String.self, container, "status")
        try accessRequire(accessUUID(operationID) && status == "acked")
    }
}

public struct RecipeUsageAPIError: Decodable, Hashable, Sendable, Error {
    public let code: String
    public let message: String
    public let recoverable: Bool
    public let requestID: String
    public static let statuses: [String: Int] = [
        "AUTH_REQUIRED": 401,
        "OWNER_MISMATCH": 403,
        "NOT_FOUND": 404,
        "IDEMPOTENCY_CONFLICT": 409,
        "RESERVATION_EXPIRED": 409,
        "INVALID_INPUT": 422,
        "QUOTA_EXCEEDED": 402,
        "UPGRADE_REQUIRED": 402,
        "CONFIGURATION_UNAVAILABLE": 503,
        "SERVICE_UNAVAILABLE": 503,
        "INTERNAL_ERROR": 500,
    ]

    public init(from decoder: any Decoder) throws {
        let container = try accessContainer(decoder, ["code", "message", "recoverable", "request_id"])
        code = try accessDecode(String.self, container, "code")
        message = try accessDecode(String.self, container, "message")
        recoverable = try accessDecode(Bool.self, container, "recoverable")
        requestID = try accessDecode(String.self, container, "request_id")
        try accessRequire(
            Self.statuses[code] != nil && accessText(message, 300) && accessUUID(requestID))
    }
}
