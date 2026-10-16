// Developer: gengyun
// Purpose: Authenticated HTTP adapter that backs the recipe-translation provider port against the
//          recipe-translations Edge Function without introducing a second wire DTO.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum RecipeTranslationClientError: Error, Equatable, Sendable {
    case authenticationFailed
    case ownerChanged
    case invalidResponse
    case staleRevision
    case quotaExceeded
    case upgradeRequired
    case unavailable
    case invalidInput
}

/// HTTP implementation of `RecipeTranslationProviderPort`. It reuses the established
/// `RecipeDraftCredential` + `RecipeShareHTTPTransport` authenticated-network convention and maps the
/// backend wire response back into the existing `RecipeTranslationProposal` model without changing
/// its Codable shape or SHA256 variant id.
public struct RecipeTranslationClient: RecipeTranslationProviderPort, Sendable {
    public typealias Authenticate = @Sendable () async throws -> RecipeDraftCredential
    public typealias IsOwnerCurrent = @Sendable (RecipeDraftCredential) async -> Bool
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let authenticate: Authenticate
    private let isOwnerCurrent: IsOwnerCurrent
    private let send: Send

    /// `functionBaseURL` is trusted configuration, e.g. https://project.supabase.co/functions/v1.
    public init(
        functionBaseURL: URL,
        authenticate: @escaping Authenticate,
        isOwnerCurrent: @escaping IsOwnerCurrent,
        send: @escaping Send = { try await RecipeShareHTTPTransport.send($0) }
    ) {
        self.baseURL = functionBaseURL
        self.authenticate = authenticate
        self.isOwnerCurrent = isOwnerCurrent
        self.send = send
    }

    public func translate(
        _ request: RecipeTranslationRequest
    ) async throws -> RecipeTranslationProposal {
        try Task.checkCancellation()
        let credential = try await authenticate()
        try Task.checkCancellation()
        guard !credential.bearerToken.isEmpty,
            credential.bearerToken.unicodeScalars.allSatisfy({
                $0.value > 32 && $0.value < 127
            })
        else {
            throw RecipeTranslationClientError.authenticationFailed
        }
        guard await isOwnerCurrent(credential) else {
            throw RecipeTranslationClientError.ownerChanged
        }

        let body = try JSONEncoder().encode(Self.wireBody(for: request))
        guard body.count <= 32 * 1024 else {
            throw RecipeTranslationClientError.invalidInput
        }
        var url = baseURL
        url.appendPathComponent("recipe-translations")
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.httpBody = body
        httpRequest.setValue(
            "Bearer " + credential.bearerToken,
            forHTTPHeaderField: "Authorization"
        )
        httpRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await send(httpRequest)
        try Task.checkCancellation()
        guard await isOwnerCurrent(credential) else {
            throw RecipeTranslationClientError.ownerChanged
        }
        try Self.require(responseData: data, response: response)
        return try Self.proposal(from: data, request: request)
    }

    // MARK: - Wire mapping

    private struct WireBody: Encodable {
        let targetLocale: String
        let recipe: WireRecipe
        let recipeID: String
        let expectedRevision: String
        let proposalID: String

        struct WireRecipe: Encodable {
            let title: String
            let summary: String
            let ingredients: [WireIngredient]
            let steps: [WireStep]
            let sourceURL: String?
            let sourceName: String?

            struct WireIngredient: Encodable {
                let id: String
                let name: String
                let amountText: String

                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case amountText = "amount_text"
                }
            }

            struct WireStep: Encodable {
                let id: String
                let title: String
                let instruction: String
            }

            enum CodingKeys: String, CodingKey {
                case title
                case summary
                case ingredients
                case steps
                case sourceURL = "source_url"
                case sourceName = "source_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case targetLocale = "target_locale"
            case recipe
            case recipeID = "recipe_id"
            case expectedRevision = "expected_revision"
            case proposalID = "proposal_id"
        }
    }

    private struct WireField: Decodable {
        let id: String
        let original: String
        let translated: String
    }

    private struct WireResponse: Decodable {
        let title: String
        let summary: String
        let ingredientNames: [WireField]
        let ingredientAmounts: [WireField]
        let stepInstructions: [WireField]
        let stepTitles: [WireField]
        let sourceURL: String?
        let sourceName: String?

        enum CodingKeys: String, CodingKey {
            case title
            case summary
            case ingredientNames = "ingredient_names"
            case ingredientAmounts = "ingredient_amounts"
            case stepInstructions = "step_instructions"
            case stepTitles = "step_titles"
            case sourceURL = "source_url"
            case sourceName = "source_name"
        }
    }

    private struct WireError: Decodable {
        let code: String
    }

    private static func wireBody(for request: RecipeTranslationRequest) -> WireBody {
        let recipe = request.recipe
        return WireBody(
            targetLocale: request.target.rawValue,
            recipe: WireBody.WireRecipe(
                title: recipe.title,
                summary: recipe.summary,
                ingredients: recipe.ingredients.map {
                    WireBody.WireRecipe.WireIngredient(
                        id: $0.id.uuidString.lowercased(),
                        name: $0.name,
                        amountText: $0.amountText
                    )
                },
                steps: recipe.steps.map {
                    WireBody.WireRecipe.WireStep(
                        id: $0.id.uuidString.lowercased(),
                        title: $0.title,
                        instruction: $0.instruction
                    )
                },
                sourceURL: recipe.sourceURL,
                sourceName: recipe.sourceName
            ),
            recipeID: recipe.id.uuidString.lowercased(),
            expectedRevision: revisionString(recipe.updatedAt),
            proposalID: request.proposalID.uuidString.lowercased()
        )
    }

    private static func proposal(
        from data: Data,
        request: RecipeTranslationRequest
    ) throws -> RecipeTranslationProposal {
        let wire = try JSONDecoder().decode(WireResponse.self, from: data)
        return try RecipeTranslationProposal(
            recipeID: request.recipe.id,
            basedOnUpdate: request.recipe.updatedAt,
            targetLocale: request.target.rawValue,
            title: wire.title,
            summary: wire.summary,
            ingredientNames: wire.ingredientNames.map(fieldChange),
            ingredientAmounts: wire.ingredientAmounts.map(fieldChange),
            stepInstructions: wire.stepInstructions.map(fieldChange),
            stepTitles: wire.stepTitles.map(fieldChange),
            sourceURL: wire.sourceURL,
            sourceName: wire.sourceName
        )
    }

    private static func fieldChange(_ field: WireField) throws -> RecipeTranslationFieldChange {
        guard let id = UUID(uuidString: field.id) else {
            throw RecipeTranslationClientError.invalidResponse
        }
        return RecipeTranslationFieldChange(
            id: id,
            original: field.original,
            translated: field.translated
        )
    }

    private static func require(responseData: Data, response: HTTPURLResponse) throws {
        guard responseData.count <= RecipeShareHTTPTransport.maximumBodyBytes else {
            throw RecipeTranslationClientError.invalidResponse
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard response.statusCode == 200, contentType == "application/json" else {
            let code = (try? JSONDecoder().decode(WireError.self, from: responseData).code) ?? ""
            throw mappedError(code)
        }
    }

    private static func mappedError(_ code: String) -> RecipeTranslationClientError {
        switch code {
        case "STALE_REVISION":
            return .staleRevision
        case "QUOTA_EXCEEDED":
            return .quotaExceeded
        case "UPGRADE_REQUIRED":
            return .upgradeRequired
        case "INVALID_INPUT":
            return .invalidInput
        case "AUTH_REQUIRED", "OWNER_MISMATCH", "NOT_FOUND", "IDEMPOTENCY_CONFLICT":
            return .invalidInput
        case "PROVIDER_UNAVAILABLE", "TRANSLATION_DISABLED", "SERVICE_UNAVAILABLE":
            return .unavailable
        default:
            return .invalidResponse
        }
    }

    private static func revisionString(_ date: Date) -> String {
        Self.revisionFormatter.string(from: millisecondFloor(date))
    }

    private static func millisecondFloor(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
    }

    private static let revisionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
}
