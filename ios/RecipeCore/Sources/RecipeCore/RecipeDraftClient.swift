// Developer: gengyun
// Purpose: Send explicit owner draft operations without saving recipes or dispatching providers.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct RecipeDraftCredential: Sendable {
    public let ownerID: UUID
    public let generation: UUID
    public let bearerToken: String

    /// The auth bridge must replace generation on every login/logout/session replacement.
    public init(ownerID: UUID, generation: UUID, bearerToken: String) {
        self.ownerID = ownerID
        self.generation = generation
        self.bearerToken = bearerToken
    }
}

public struct RecipeDraftClient: Sendable {
    public typealias Authenticate = @Sendable (UUID) async throws -> RecipeDraftCredential
    public typealias IsOwnerCurrent = @Sendable (RecipeDraftCredential) async -> Bool
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let enabled: Bool
    private let authenticate: Authenticate
    private let isOwnerCurrent: IsOwnerCurrent
    private let send: Send

    /// functionBaseURL is trusted configuration, e.g. https://project.supabase.co/functions/v1.
    public init(
        functionBaseURL: URL,
        enabled: Bool = false,
        authenticate: @escaping Authenticate,
        isOwnerCurrent: @escaping IsOwnerCurrent,
        send: @escaping Send = { try await RecipeShareHTTPTransport.send($0) }
    ) throws {
        guard functionBaseURL.scheme == "https", let host = functionBaseURL.host, !host.isEmpty,
            functionBaseURL.user == nil, functionBaseURL.password == nil,
            functionBaseURL.query == nil, functionBaseURL.fragment == nil
        else {
            throw RecipeDraftClientError.invalidInput
        }
        baseURL = functionBaseURL.appendingPathComponent("recipe-draft-sessions")
        self.enabled = enabled
        self.authenticate = authenticate
        self.isOwnerCurrent = isOwnerCurrent
        self.send = send
    }

    public func createSession(jobID: UUID, clientRequestID: UUID, ownerID: UUID) async throws
        -> RecipeDraftSession
    {
        let result: RecipeDraftSession = try await perform(
            path: [], ownerID: ownerID,
            body: CreateBody(jobID: text(jobID), clientRequestID: text(clientRequestID)),
            statuses: [200, 201]
        )
        try draftRequire(
            result.jobID == text(jobID) && result.clientRequestID == text(clientRequestID))
        return result
    }

    public func fetchSession(sessionID: UUID, ownerID: UUID) async throws -> RecipeDraftSession {
        let result: RecipeDraftSession = try await perform(
            path: [text(sessionID)], ownerID: ownerID)
        try draftRequire(result.sessionID == text(sessionID))
        return result
    }

    public func createTurn(
        sessionID: UUID, requestID: UUID, expectedRevision: RecipeDraftRevision,
        message: String, ownerID: UUID
    ) async throws -> RecipeDraftTurn {
        guard draftText(message, 0, 2000) else {
            throw RecipeDraftClientError.invalidInput
        }
        let result: RecipeDraftTurn = try await perform(
            path: [text(sessionID), "turns"], ownerID: ownerID,
            body: TurnBody(
                requestID: text(requestID), expectedRevision: expectedRevision, message: message),
            statuses: [200, 202], turnStatus: true
        )
        try draftRequire(result.sessionID == text(sessionID) && result.requestID == text(requestID))
        return result
    }

    public func fetchTurn(sessionID: UUID, requestID: UUID, ownerID: UUID) async throws
        -> RecipeDraftTurn
    {
        let result: RecipeDraftTurn = try await perform(
            path: [text(sessionID), "turns", text(requestID)], ownerID: ownerID)
        try draftRequire(result.sessionID == text(sessionID) && result.requestID == text(requestID))
        return result
    }

    public func approveTurn(
        sessionID: UUID, turnRequestID: UUID, requestID: UUID,
        expectedRevision: RecipeDraftRevision,
        action: String, selectedPaths: [String], ownerID: UUID
    ) async throws -> RecipeDraftApprovalReceipt {
        guard draftApproval(action, selectedPaths) else {
            throw RecipeDraftClientError.invalidInput
        }
        let result: RecipeDraftApprovalReceipt = try await perform(
            path: [text(sessionID), "turns", text(turnRequestID), "approval"], ownerID: ownerID,
            body: ApprovalBody(
                requestID: text(requestID), expectedRevision: expectedRevision, action: action,
                selectedPaths: selectedPaths)
        )
        // A durable replay can return an old receipt while the session has advanced further.
        try draftRequire(
            result.sessionID == text(sessionID) && result.turnRequestID == text(turnRequestID)
                && result.requestID == text(requestID) && result.action == action
                && result.selectedPaths == selectedPaths)
        return result
    }

    private func text(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private func current(_ credential: RecipeDraftCredential) async throws {
        let valid = await isOwnerCurrent(credential)
        try Task.checkCancellation()
        guard valid else {
            throw RecipeDraftClientError.ownerChanged
        }
    }

    private func perform<T: Decodable>(
        path: [String], ownerID: UUID, body: (any Encodable)? = nil,
        statuses: Set<Int> = [200], turnStatus: Bool = false
    ) async throws -> T {
        try Task.checkCancellation()
        if body != nil && !enabled {
            throw RecipeDraftClientError.disabled
        }
        let data = try body.map { try JSONEncoder().encode($0) }
        guard (data?.count ?? 0) <= 32768 else {
            throw RecipeDraftClientError.invalidInput
        }
        let credential = try await authenticate(ownerID)
        try Task.checkCancellation()
        guard credential.ownerID == ownerID, !credential.bearerToken.isEmpty,
            credential.bearerToken.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 })
        else {
            throw RecipeDraftClientError.ownerChanged
        }
        try await current(credential)
        var url = baseURL
        for part in path {
            url.appendPathComponent(part)
        }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = data
        request.setValue("Bearer " + credential.bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (responseData, response) = try await send(request)
        try Task.checkCancellation()
        try await current(credential)
        try draftRequire(responseData.count <= RecipeShareHTTPTransport.maximumBodyBytes)
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.split(
            separator: ";", omittingEmptySubsequences: false
        ).first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try draftRequire(contentType == "application/json" && response.url == request.url)
        let decoder = JSONDecoder()
        do {
            if !statuses.contains(response.statusCode) {
                let error = try decoder.decode(RecipeDraftAPIError.self, from: responseData)
                try draftRequire(RecipeDraftAPIError.statuses[error.code] == response.statusCode)
                throw error
            }
            let result = try decoder.decode(T.self, from: responseData)
            if turnStatus {
                guard let turn = result as? RecipeDraftTurn else {
                    throw RecipeDraftClientError.invalidResponse
                }
                try draftRequire(
                    (response.statusCode == 202 && turn.state == "pending")
                        || (response.statusCode == 200 && turn.state == "terminal"))
            }
            try await current(credential)
            return result
        } catch let error as RecipeDraftAPIError {
            throw error
        } catch let error as RecipeDraftClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RecipeDraftClientError.invalidResponse
        }
    }

    private struct CreateBody: Encodable {
        let jobID: String
        let clientRequestID: String
        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case clientRequestID = "client_request_id"
        }
    }
    private struct TurnBody: Encodable {
        let requestID: String
        let expectedRevision: RecipeDraftRevision
        let message: String
        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case expectedRevision = "expected_revision"
            case message
        }
    }
    private struct ApprovalBody: Encodable {
        let requestID: String
        let expectedRevision: RecipeDraftRevision
        let action: String
        let selectedPaths: [String]
        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case expectedRevision = "expected_revision"
            case action
            case selectedPaths = "selected_paths"
        }
    }
}
