// Developer: gengyun
// Purpose: Models the frozen Recipe Import API and its injectable client boundary.

import Foundation

public struct RecipeImportJobResponse: Decodable, Sendable {
    public enum Status: String, Decodable, Equatable, Sendable {
        case received
        case queued
        case extracting
        case parsing
        case validating
        case completed
        case failed
    }

    public struct Failure: Decodable, Sendable {
        public let code: String
        public let message: String
        public let recoverable: Bool?
        public let suggestedAction: String?
        public let requestID: UUID?

        private enum CodingKeys: String, CodingKey {
            case code
            case message
            case recoverable
            case suggestedAction = "suggested_action"
            case requestID = "request_id"
        }

        public init(
            code: String,
            message: String,
            recoverable: Bool?,
            suggestedAction: String? = nil,
            requestID: UUID? = nil
        ) {
            self.code = code
            self.message = message
            self.recoverable = recoverable
            self.suggestedAction = suggestedAction
            self.requestID = requestID
        }
    }

    public struct Field: Codable, Hashable, Sendable {
        public let rawValue: String?
        public let normalizedValue: RecipeImportFieldValue?
        public let unit: String?
        public let evidenceIDs: [UUID]
        public let confidence: Double?
        public let userConfirmed: Bool
        public let origin: String
        public let updatedAt: String?

        private enum CodingKeys: String, CodingKey {
            case rawValue = "raw_value"
            case normalizedValue = "normalized_value"
            case unit
            case evidenceIDs = "evidence_ids"
            case confidence
            case userConfirmed = "user_confirmed"
            case origin
            case updatedAt = "updated_at"
        }

        public init(
            rawValue: String?,
            normalizedValue: RecipeImportFieldValue? = nil,
            unit: String? = nil,
            evidenceIDs: [UUID] = [],
            confidence: Double? = nil,
            userConfirmed: Bool = false,
            origin: String = "extracted",
            updatedAt: String? = nil
        ) {
            self.rawValue = rawValue
            self.normalizedValue = normalizedValue
            self.unit = unit
            self.evidenceIDs = evidenceIDs
            self.confidence = confidence
            self.userConfirmed = userConfirmed
            self.origin = origin
            self.updatedAt = updatedAt
        }
    }

    public struct Source: Codable, Hashable, Sendable {
        public let inputType: String
        public let originalURL: String?
        public let canonicalURL: String?
        public let sourceArtifactID: UUID?
        public let platform: String?
        public let authorName: String?
        public let sourceTitle: String?
        public let externalContentID: String?

        private enum CodingKeys: String, CodingKey {
            case inputType = "input_type"
            case originalURL = "original_url"
            case canonicalURL = "canonical_url"
            case sourceArtifactID = "source_artifact_id"
            case platform
            case authorName = "author_name"
            case sourceTitle = "source_title"
            case externalContentID = "external_content_id"
        }

        public init(
            inputType: String,
            originalURL: String? = nil,
            canonicalURL: String? = nil,
            sourceArtifactID: UUID? = nil,
            platform: String? = nil,
            authorName: String? = nil,
            sourceTitle: String? = nil,
            externalContentID: String? = nil
        ) {
            self.inputType = inputType
            self.originalURL = originalURL
            self.canonicalURL = canonicalURL
            self.sourceArtifactID = sourceArtifactID
            self.platform = platform
            self.authorName = authorName
            self.sourceTitle = sourceTitle
            self.externalContentID = externalContentID
        }
    }

    public struct Evidence: Codable, Hashable, Sendable {
        public let id: UUID
        public let sourceType: String
        public let origin: String
        public let excerpt: String?
        public let confidence: Double?
        public let timestampStartSeconds: Double?
        public let timestampEndSeconds: Double?
        public let frameReference: String?
        public let sourceArtifactID: UUID?
        public let capturedAt: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case sourceType = "source_type"
            case origin
            case excerpt
            case confidence
            case timestampStartSeconds = "timestamp_start_seconds"
            case timestampEndSeconds = "timestamp_end_seconds"
            case frameReference = "frame_ref"
            case sourceArtifactID = "source_artifact_id"
            case capturedAt = "captured_at"
        }

        public init(
            id: UUID,
            sourceType: String,
            origin: String,
            excerpt: String? = nil,
            confidence: Double? = nil,
            timestampStartSeconds: Double? = nil,
            timestampEndSeconds: Double? = nil,
            frameReference: String? = nil,
            sourceArtifactID: UUID? = nil,
            capturedAt: String? = nil
        ) {
            self.id = id
            self.sourceType = sourceType
            self.origin = origin
            self.excerpt = excerpt
            self.confidence = confidence
            self.timestampStartSeconds = timestampStartSeconds
            self.timestampEndSeconds = timestampEndSeconds
            self.frameReference = frameReference
            self.sourceArtifactID = sourceArtifactID
            self.capturedAt = capturedAt
        }
    }

    public struct Candidate: Codable, Hashable, Sendable {
        public let candidateID: String
        public let title: String?
        public let ingredients: [String]
        public let steps: [String]
        public let evidenceIDs: [UUID]
        public let reviewFields: [String]

        private enum CodingKeys: String, CodingKey {
            case candidateID = "candidate_id"
            case title, ingredients, steps
            case evidenceIDs = "evidence_ids"
            case reviewFields = "review_fields"
        }

        public init(
            candidateID: String, title: String?, ingredients: [String],
            steps: [String], evidenceIDs: [UUID] = [], reviewFields: [String] = []
        ) {
            self.candidateID = candidateID
            self.title = title
            self.ingredients = ingredients
            self.steps = steps
            self.evidenceIDs = evidenceIDs
            self.reviewFields = reviewFields
        }
    }

    public struct Result: Codable, Hashable, Sendable {
        public let recipeID: UUID
        public let status: String
        public let source: Source
        public let fields: [String: Field]
        public let evidence: [Evidence]
        public let reviewFields: [String]?
        public let candidateRecipes: [Candidate]?

        public var resultStatus: RecipeImportResultStatus? {
            RecipeImportResultStatus(rawValue: status)
        }

        private enum CodingKeys: String, CodingKey {
            case recipeID = "recipe_id"
            case status
            case source
            case fields
            case evidence
            case reviewFields = "review_fields"
            case candidateRecipes = "candidate_recipes"
        }

        public init(
            recipeID: UUID,
            status: String,
            source: Source,
            fields: [String: Field],
            evidence: [Evidence] = [],
            reviewFields: [String]? = nil,
            candidateRecipes: [Candidate]? = nil
        ) {
            self.recipeID = recipeID
            self.status = status
            self.source = source
            self.fields = fields
            self.evidence = evidence
            self.reviewFields = reviewFields
            self.candidateRecipes = candidateRecipes
        }
    }

    public let jobID: UUID
    public let clientRequestID: UUID
    public let status: Status
    public let stage: String?
    public let progressHint: String?
    public let attemptCount: Int
    public let queueConfirmedAt: String?
    public let recipeID: UUID?
    public let recipeStatus: String?
    public let existingRecipeID: UUID?
    public let reviewCount: Int?
    public let result: Result?
    public let error: Failure?

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status
        case stage
        case progressHint = "progress_hint"
        case attemptCount = "attempt_count"
        case queueConfirmedAt = "queue_confirmed_at"
        case recipeID = "recipe_id"
        case recipeStatus = "recipe_status"
        case existingRecipeID = "existing_recipe_id"
        case reviewCount = "review_count"
        case result
        case error
    }

    public init(
        jobID: UUID,
        clientRequestID: UUID,
        status: Status,
        stage: String? = nil,
        progressHint: String? = nil,
        attemptCount: Int = 0,
        queueConfirmedAt: String? = nil,
        recipeID: UUID? = nil,
        recipeStatus: String? = nil,
        existingRecipeID: UUID? = nil,
        reviewCount: Int? = nil,
        result: Result? = nil,
        error: Failure? = nil
    ) {
        self.jobID = jobID
        self.clientRequestID = clientRequestID
        self.status = status
        self.stage = stage
        self.progressHint = progressHint
        self.attemptCount = attemptCount
        self.queueConfirmedAt = queueConfirmedAt
        self.recipeID = recipeID
        self.recipeStatus = recipeStatus
        self.existingRecipeID = existingRecipeID
        self.reviewCount = reviewCount
        self.result = result
        self.error = error
    }

    public var isDurablyQueued: Bool {
        guard status != .received, let queueConfirmedAt else {
            return false
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if fractionalFormatter.date(from: queueConfirmedAt) != nil {
            return true
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: queueConfirmedAt) != nil
    }

    public var isActive: Bool {
        switch status {
        case .received, .queued, .extracting, .parsing, .validating:
            true
        case .completed, .failed:
            false
        }
    }
}

public enum RecipeImportFieldValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Decimal)
    case boolean(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if try container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .number(try container.decode(Decimal.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum RecipeImportResultStatus: String, Codable, Sendable {
    case ready
    case needsReview = "needs_review"
}

public struct RecipeImportRecord: Codable, Hashable, Sendable {
    public let jobID: UUID
    public let result: RecipeImportJobResponse.Result
    /// Records explicit local review without altering server fields or evidence.
    public var reviewedAt: Date?
    /// Local tombstone for user-deleted private source bytes. Keeps job evidence
    /// immutable so older snapshots and completed retries remain decodable.
    public var sourceArtifactDeletedAt: Date?
    public var selectedCandidateID: String?

    public init(
        jobID: UUID,
        result: RecipeImportJobResponse.Result,
        reviewedAt: Date? = nil,
        sourceArtifactDeletedAt: Date? = nil,
        selectedCandidateID: String? = nil
    ) {
        self.jobID = jobID
        self.result = result
        self.reviewedAt = reviewedAt
        self.sourceArtifactDeletedAt = sourceArtifactDeletedAt
        self.selectedCandidateID = selectedCandidateID
    }
}

@MainActor
public protocol RecipeImportJobClient {
    func submit(
        receipt: RecipeShareReceipt,
        source: String,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse

    func fetch(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse

    func retry(
        jobID: UUID,
        ownerID: UUID
    ) async throws -> RecipeImportJobResponse
}
