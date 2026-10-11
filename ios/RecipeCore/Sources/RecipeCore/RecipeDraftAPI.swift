// Developer: gengyun
// Purpose: Decode the strict owner draft wire contract independently of private Recipe models.

import Foundation

public enum RecipeDraftClientError: Error, Equatable, Sendable {
    case invalidInput
    case invalidResponse
    case disabled
    case ownerChanged
}

public struct RecipeDraftRevision: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ value: String) throws {
        guard
            value.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) == value
                .startIndex..<value.endIndex,
            let number = UInt64(value), number <= 9_223_372_036_854_775_807
        else {
            throw RecipeDraftClientError.invalidInput
        }
        rawValue = value
    }
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

private struct DraftKey: CodingKey {
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

/// Required nullable members still have to exist; unknown wire keys are never ignored.
private func draftContainer(_ decoder: any Decoder, _ keys: [String]) throws
    -> KeyedDecodingContainer<DraftKey>
{
    let container = try decoder.container(keyedBy: DraftKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == Set(keys) else {
        throw RecipeDraftClientError.invalidResponse
    }
    return container
}

private func draftDecode<T: Decodable>(
    _ type: T.Type, _ container: KeyedDecodingContainer<DraftKey>, _ key: String
) throws -> T {
    try container.decode(type, forKey: DraftKey(stringValue: key))
}

func draftRequire(_ condition: Bool) throws {
    guard condition else {
        throw RecipeDraftClientError.invalidResponse
    }
}
func draftText(_ text: String, _ minimum: Int, _ maximum: Int) -> Bool {
    (minimum...maximum).contains(text.unicodeScalars.count)
}
func draftText(_ text: String, _ maximum: Int) -> Bool {
    draftText(text, 1, maximum)
}
func draftUUID(_ value: String) -> Bool {
    value.range(
        of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
        options: .regularExpression) == value.startIndex..<value.endIndex
}
func draftHash(_ value: String) -> Bool {
    value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) == value
        .startIndex..<value.endIndex
}
func draftPath(_ value: String, review: Bool = false) -> Bool {
    if review && ["ingredients", "steps"].contains(value) {
        return true
    }
    return value.range(
        of:
            #"^(title|servings|ingredients\[([0-9]|[1-9][0-9])\]\.(name|raw_text|amount)|steps\[([0-9]|[1-9][0-9])\]\.instruction)$"#,
        options: .regularExpression) == value.startIndex..<value.endIndex
}
func draftIDs(_ values: [String], minimum: Int = 0) -> Bool {
    values.count >= minimum && values.count <= 60 && Set(values).count == values.count
        && values.allSatisfy(draftUUID)
}

public struct RecipeDraftField: Decodable, Hashable, Sendable {
    public let rawValue: String?
    public let evidenceIDs: [String]
    public let userConfirmed: Bool
    public let origin: String
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder, ["raw_value", "evidence_ids", "user_confirmed", "origin"])
        rawValue = try draftDecode(String?.self, container, "raw_value")
        evidenceIDs = try draftDecode([String].self, container, "evidence_ids")
        userConfirmed = try draftDecode(Bool.self, container, "user_confirmed")
        origin = try draftDecode(String.self, container, "origin")
        try draftRequire(rawValue.map { draftText($0, 1500) } ?? true)
        try draftRequire(draftIDs(evidenceIDs) && draftText(origin, 64))
    }
}

public struct RecipeDraftOverlayField: Decodable, Hashable, Sendable {
    public let rawValue: String
    public let evidenceIDs: [String]
    public let userConfirmed: Bool
    public let origin: String
    public let confirmedRevision: RecipeDraftRevision
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder,
            ["raw_value", "evidence_ids", "user_confirmed", "origin", "confirmed_revision"])
        rawValue = try draftDecode(String.self, container, "raw_value")
        evidenceIDs = try draftDecode([String].self, container, "evidence_ids")
        userConfirmed = try draftDecode(Bool.self, container, "user_confirmed")
        origin = try draftDecode(String.self, container, "origin")
        confirmedRevision = try draftDecode(
            RecipeDraftRevision.self, container, "confirmed_revision")
        try draftRequire(draftText(rawValue, 1500) && draftIDs(evidenceIDs, minimum: 1))
        try draftRequire(userConfirmed && origin == "AI_suggested")
    }
}

public struct RecipeDraftEvidence: Decodable, Hashable, Sendable {
    public let id: String
    public let excerpt: String
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(decoder, ["id", "excerpt"])
        id = try draftDecode(String.self, container, "id")
        excerpt = try draftDecode(String.self, container, "excerpt")
        try draftRequire(draftUUID(id) && draftText(excerpt, 1500))
    }
}

public struct RecipeDraftContext: Decodable, Hashable, Sendable {
    public let status: String
    public let fields: [String: RecipeDraftField]
    public let evidence: [RecipeDraftEvidence]
    public let reviewFields: [String]
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder, ["status", "fields", "evidence", "review_fields"])
        status = try draftDecode(String.self, container, "status")
        fields = try draftDecode([String: RecipeDraftField].self, container, "fields")
        evidence = try draftDecode([RecipeDraftEvidence].self, container, "evidence")
        reviewFields = try draftDecode([String].self, container, "review_fields")
        try draftRequire(
            ["ready", "needs_review"].contains(status) && fields.count <= 100
                && fields.keys.allSatisfy { draftPath($0) })
        try draftRequire(evidence.count <= 60 && Set(evidence.map(\.id)).count == evidence.count)
        try draftRequire(evidence.reduce(0) { $0 + $1.excerpt.unicodeScalars.count } <= 20000)
        let ids = Set(evidence.map(\.id))
        try draftRequire(fields.values.allSatisfy { Set($0.evidenceIDs).isSubset(of: ids) })
        try draftRequire(
            reviewFields.count <= 100 && Set(reviewFields).count == reviewFields.count
                && reviewFields.allSatisfy { draftPath($0, review: true) })
    }
}

public struct RecipeDraftBudget: Decodable, Hashable, Sendable {
    public let reservedTokens: Int
    public let settledTokens: Int
    public let dispatchCount: Int
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder, ["reserved_tokens", "settled_tokens", "dispatch_count"])
        reservedTokens = try draftDecode(Int.self, container, "reserved_tokens")
        settledTokens = try draftDecode(Int.self, container, "settled_tokens")
        dispatchCount = try draftDecode(Int.self, container, "dispatch_count")
        try draftRequire(
            (0...32768).contains(reservedTokens) && (0...32768).contains(settledTokens)
                && reservedTokens + settledTokens <= 32768 && (0...8).contains(dispatchCount))
    }
}

public struct RecipeDraftSession: Decodable, Hashable, Sendable {
    public let sessionID: String
    public let jobID: String
    public let clientRequestID: String
    public let revision: RecipeDraftRevision
    public let sourceFingerprint: String
    public let contextHash: String
    public let context: RecipeDraftContext
    public let overlay: [String: RecipeDraftOverlayField]
    public let budget: RecipeDraftBudget
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder,
            [
                "session_id", "job_id", "client_request_id", "revision", "source_fingerprint",
                "context_hash", "context", "overlay", "budget",
            ])
        sessionID = try draftDecode(String.self, container, "session_id")
        jobID = try draftDecode(String.self, container, "job_id")
        clientRequestID = try draftDecode(String.self, container, "client_request_id")
        revision = try draftDecode(RecipeDraftRevision.self, container, "revision")
        sourceFingerprint = try draftDecode(String.self, container, "source_fingerprint")
        contextHash = try draftDecode(String.self, container, "context_hash")
        context = try draftDecode(RecipeDraftContext.self, container, "context")
        overlay = try draftDecode([String: RecipeDraftOverlayField].self, container, "overlay")
        budget = try draftDecode(RecipeDraftBudget.self, container, "budget")
        try draftRequire(
            [sessionID, jobID, clientRequestID].allSatisfy(draftUUID)
                && draftText(sourceFingerprint, 512) && draftHash(contextHash))
        try draftRequire(overlay.count <= 100 && overlay.keys.allSatisfy { draftPath($0) })
        for (path, value) in overlay {
            try draftRequire(
                UInt64(value.confirmedRevision.rawValue)! <= UInt64(revision.rawValue)!)
            guard let field = context.fields[path] else {
                throw RecipeDraftClientError.invalidResponse
            }
            try draftRequire(
                field.rawValue.map { draftExactText($0, value.rawValue) } == true
                    && field.evidenceIDs == value.evidenceIDs
                    && field.userConfirmed == value.userConfirmed
                    && draftExactText(field.origin, value.origin))
        }
    }
}

public struct RecipeDraftQuestion: Decodable, Hashable, Sendable {
    public let path: String
    public let question: String
    public let evidenceIDs: [String]
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(decoder, ["path", "question", "evidence_ids"])
        path = try draftDecode(String.self, container, "path")
        question = try draftDecode(String.self, container, "question")
        evidenceIDs = try draftDecode([String].self, container, "evidence_ids")
        try draftRequire(
            draftPath(path, review: true) && draftText(question, 300)
                && draftIDs(evidenceIDs, minimum: 1))
    }
}

public struct RecipeDraftSuggestion: Decodable, Hashable, Sendable {
    public let path: String
    public let rawValue: String
    public let evidenceIDs: [String]
    public let reason: String
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder, ["path", "raw_value", "evidence_ids", "reason"])
        path = try draftDecode(String.self, container, "path")
        rawValue = try draftDecode(String.self, container, "raw_value")
        evidenceIDs = try draftDecode([String].self, container, "evidence_ids")
        reason = try draftDecode(String.self, container, "reason")
        try draftRequire(
            draftPath(path) && draftText(rawValue, 1500) && draftText(reason, 500)
                && draftIDs(evidenceIDs, minimum: 1))
    }
}

public struct RecipeDraftApprovalReceipt: Decodable, Hashable, Sendable {
    public let sessionID: String
    public let turnRequestID: String
    public let requestID: String
    public let action: String
    public let selectedPaths: [String]
    public let appliedRevision: RecipeDraftRevision
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder,
            [
                "session_id", "turn_request_id", "request_id", "action", "selected_paths",
                "applied_revision",
            ])
        sessionID = try draftDecode(String.self, container, "session_id")
        turnRequestID = try draftDecode(String.self, container, "turn_request_id")
        requestID = try draftDecode(String.self, container, "request_id")
        action = try draftDecode(String.self, container, "action")
        selectedPaths = try draftDecode([String].self, container, "selected_paths")
        appliedRevision = try draftDecode(RecipeDraftRevision.self, container, "applied_revision")
        try draftRequire([sessionID, turnRequestID, requestID].allSatisfy(draftUUID))
        try draftRequire(draftApproval(action, selectedPaths))
    }
}

public struct RecipeDraftTurn: Decodable, Hashable, Sendable {
    public let sessionID: String
    public let requestID: String
    public let basedRevision: RecipeDraftRevision
    public let contextHash: String
    public let state: String
    public let result: RecipeDraftGenerationResult?
    public let decision: RecipeDraftApprovalReceipt?
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder,
            [
                "session_id", "request_id", "based_revision", "context_hash", "state", "result",
                "decision",
            ])
        sessionID = try draftDecode(String.self, container, "session_id")
        requestID = try draftDecode(String.self, container, "request_id")
        basedRevision = try draftDecode(RecipeDraftRevision.self, container, "based_revision")
        contextHash = try draftDecode(String.self, container, "context_hash")
        state = try draftDecode(String.self, container, "state")
        result = try draftDecode(RecipeDraftGenerationResult?.self, container, "result")
        decision = try draftDecode(RecipeDraftApprovalReceipt?.self, container, "decision")
        try draftRequire(draftUUID(sessionID) && draftUUID(requestID) && draftHash(contextHash))
        try draftRequire(
            (state == "pending" && result == nil && decision == nil)
                || (state == "terminal" && result != nil))
        if let decision {
            try draftRequire(decision.sessionID == sessionID && decision.turnRequestID == requestID)
        }
    }
}

public struct RecipeDraftAPIError: Decodable, Hashable, Sendable, Error {
    public let code: String
    public let message: String
    public let recoverable: Bool
    public let requestID: String
    public static let statuses: [String: Int] = [
        "AUTH_REQUIRED": 401, "NOT_FOUND": 404, "JOB_NOT_READY": 409,
        "STALE_REVISION": 409, "IDEMPOTENCY_CONFLICT": 409, "TURN_ALREADY_DECIDED": 409,
        "REVISION_EXHAUSTED": 409, "INPUT_TOO_LARGE": 413, "INVALID_INPUT": 422,
        "INVALID_EVIDENCE": 422, "INVALID_REVIEW_PATH": 422, "BUDGET_EXHAUSTED": 429,
        "DRAFT_DISABLED": 503, "PROVIDER_UNAVAILABLE": 503, "INTERNAL_ERROR": 500,
    ]
    public init(from decoder: any Decoder) throws {
        let container = try draftContainer(
            decoder, ["code", "message", "recoverable", "request_id"])
        code = try draftDecode(String.self, container, "code")
        message = try draftDecode(String.self, container, "message")
        recoverable = try draftDecode(Bool.self, container, "recoverable")
        requestID = try draftDecode(String.self, container, "request_id")
        try draftRequire(
            Self.statuses[code] != nil && draftText(message, 300) && draftUUID(requestID))
    }
}

func draftExactText(_ left: String, _ right: String) -> Bool {
    left.utf8.elementsEqual(right.utf8)
}

func draftApproval(_ action: String, _ paths: [String]) -> Bool {
    Set(paths).count == paths.count && paths.allSatisfy { draftPath($0) }
        && ((action == "accept" && (1...20).contains(paths.count))
            || (action == "reject" && paths.isEmpty))
}

public enum RecipeDraftGenerationResult: Decodable, Hashable, Sendable {
    case noReviewNeeded
    case rejected(code: String)
    case unavailable(code: String)
    case proposal(questions: [RecipeDraftQuestion], suggestions: [RecipeDraftSuggestion])

    public init(from decoder: any Decoder) throws {
        let initial = try decoder.container(keyedBy: DraftKey.self)
        let status = try draftDecode(String.self, initial, "status")
        switch status {
        case "no_review_needed":
            _ = try draftContainer(decoder, ["status"])
            self = .noReviewNeeded
        case "rejected", "unavailable":
            let container = try draftContainer(decoder, ["status", "code"])
            let code = try draftDecode(String.self, container, "code")
            try draftRequire(
                [
                    "INVALID_INPUT", "INVALID_EVIDENCE", "INVALID_REVIEW_PATH",
                    "INVALID_PROVIDER_OUTPUT", "INPUT_BUDGET", "OUTPUT_BUDGET", "STALE_REVISION",
                    "PROVIDER_TIMEOUT", "PROVIDER_UNAVAILABLE", "PROVIDER_OUTCOME_UNKNOWN",
                ].contains(code))
            self = status == "rejected" ? .rejected(code: code) : .unavailable(code: code)
        case "proposal":
            let container = try draftContainer(
                decoder, ["status", "origin", "requires_approval", "questions", "suggestions"])
            try draftRequire(draftDecode(String.self, container, "origin") == "AI_suggested")
            try draftRequire(draftDecode(Bool.self, container, "requires_approval"))
            let questions = try draftDecode([RecipeDraftQuestion].self, container, "questions")
            let suggestions = try draftDecode(
                [RecipeDraftSuggestion].self, container, "suggestions")
            try draftRequire(
                questions.count <= 3 && suggestions.count <= 20
            )
            // Wire uniqueItems compares Unicode scalars, not Swift's normalized String equality.
            for index in questions.indices {
                let item = questions[index]
                try draftRequire(
                    !questions.prefix(index).contains {
                        $0.path == item.path && draftExactText($0.question, item.question)
                            && $0.evidenceIDs == item.evidenceIDs
                    })
            }
            for index in suggestions.indices {
                let item = suggestions[index]
                try draftRequire(
                    !suggestions.prefix(index).contains {
                        $0.path == item.path && draftExactText($0.rawValue, item.rawValue)
                            && draftExactText($0.reason, item.reason)
                            && $0.evidenceIDs == item.evidenceIDs
                    })
            }
            self = .proposal(questions: questions, suggestions: suggestions)
        default: throw RecipeDraftClientError.invalidResponse
        }
    }
}
