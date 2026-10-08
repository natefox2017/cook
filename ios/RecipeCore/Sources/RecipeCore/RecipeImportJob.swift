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

        private enum CodingKeys: String, CodingKey {
            case code
            case message
            case recoverable
            case suggestedAction = "suggested_action"
        }

        public init(
            code: String,
            message: String,
            recoverable: Bool?,
            suggestedAction: String? = nil
        ) {
            self.code = code
            self.message = message
            self.recoverable = recoverable
            self.suggestedAction = suggestedAction
        }
    }

    public struct Field: Decodable, Sendable {
        public let rawValue: String?
        public let evidenceIDs: [UUID]
        public let userConfirmed: Bool
        public let origin: String

        private enum CodingKeys: String, CodingKey {
            case rawValue = "raw_value"
            case evidenceIDs = "evidence_ids"
            case userConfirmed = "user_confirmed"
            case origin
        }

        public init(
            rawValue: String?,
            evidenceIDs: [UUID] = [],
            userConfirmed: Bool = false,
            origin: String = "extracted"
        ) {
            self.rawValue = rawValue
            self.evidenceIDs = evidenceIDs
            self.userConfirmed = userConfirmed
            self.origin = origin
        }
    }

    public struct Source: Decodable, Sendable {
        public let inputType: String
        public let originalURL: String?
        public let canonicalURL: String?
        public let platform: String?
        public let authorName: String?
        public let sourceTitle: String?

        private enum CodingKeys: String, CodingKey {
            case inputType = "input_type"
            case originalURL = "original_url"
            case canonicalURL = "canonical_url"
            case platform
            case authorName = "author_name"
            case sourceTitle = "source_title"
        }

        public init(
            inputType: String,
            originalURL: String? = nil,
            canonicalURL: String? = nil,
            platform: String? = nil,
            authorName: String? = nil,
            sourceTitle: String? = nil
        ) {
            self.inputType = inputType
            self.originalURL = originalURL
            self.canonicalURL = canonicalURL
            self.platform = platform
            self.authorName = authorName
            self.sourceTitle = sourceTitle
        }
    }

    public struct Evidence: Decodable, Sendable {
        public let id: UUID
        public let sourceType: String
        public let origin: String
        public let excerpt: String?
        public let confidence: Double?

        private enum CodingKeys: String, CodingKey {
            case id
            case sourceType = "source_type"
            case origin
            case excerpt
            case confidence
        }

        public init(
            id: UUID,
            sourceType: String,
            origin: String,
            excerpt: String? = nil,
            confidence: Double? = nil
        ) {
            self.id = id
            self.sourceType = sourceType
            self.origin = origin
            self.excerpt = excerpt
            self.confidence = confidence
        }
    }

    public struct Result: Decodable, Sendable {
        public let recipeID: UUID
        public let status: String
        public let source: Source
        public let fields: [String: Field]
        public let evidence: [Evidence]
        public let reviewFields: [String]?

        private enum CodingKeys: String, CodingKey {
            case recipeID = "recipe_id"
            case status
            case source
            case fields
            case evidence
            case reviewFields = "review_fields"
        }

        public init(
            recipeID: UUID,
            status: String,
            source: Source,
            fields: [String: Field],
            evidence: [Evidence] = [],
            reviewFields: [String]? = nil
        ) {
            self.recipeID = recipeID
            self.status = status
            self.source = source
            self.fields = fields
            self.evidence = evidence
            self.reviewFields = reviewFields
        }
    }

    public let jobID: UUID
    public let clientRequestID: UUID
    public let status: Status
    public let stage: String?
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
            .withFractionalSeconds
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
