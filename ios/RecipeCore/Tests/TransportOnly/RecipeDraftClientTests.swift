// Developer: gengyun
// Purpose: Exercise the original Foundation draft client, strict DTOs, and bounded transport on Linux.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private let owner = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
private let job = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!
private let sessionID = UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!
private let turnID = UUID(uuidString: "a0000000-0000-4000-8000-000000000004")!
private let key = UUID(uuidString: "a0000000-0000-4000-8000-000000000005")!
private let approvalID = UUID(uuidString: "a0000000-0000-4000-8000-000000000006")!
private let evidenceID = "a0000000-0000-4000-8000-000000000007"
private let initialGeneration = UUID(uuidString: "a0000000-0000-4000-8000-000000000008")!
private let fingerprint = String(repeating: "a", count: 64)
private func wire(_ id: UUID) -> String {
    id.uuidString.lowercased()
}

private func context() -> [String: Any] {
    [
        "status": "needs_review",
        "fields": [
            "title": [
                "raw_value": NSNull(), "evidence_ids": [evidenceID], "user_confirmed": false,
                "origin": "extracted",
            ]
        ], "evidence": [["id": evidenceID, "excerpt": "Source soup"]], "review_fields": ["title"],
    ]
}
private func session() -> [String: Any] {
    [
        "session_id": wire(sessionID), "job_id": wire(job), "client_request_id": wire(key),
        "revision": "1", "source_fingerprint": "immutable", "context_hash": fingerprint,
        "context": context(), "overlay": [:],
        "budget": ["reserved_tokens": 0, "settled_tokens": 0, "dispatch_count": 0],
    ]
}
private func receipt() -> [String: Any] {
    [
        "session_id": wire(sessionID), "turn_request_id": wire(turnID),
        "request_id": wire(approvalID), "action": "accept", "selected_paths": ["title"],
        "applied_revision": "2",
    ]
}
private func proposal() -> [String: Any] {
    [
        "status": "proposal", "origin": "AI_suggested", "requires_approval": true,
        "questions": [
            ["path": "ingredients", "question": "Which ingredient?", "evidence_ids": [evidenceID]]
        ],
        "suggestions": [
            [
                "path": "title", "raw_value": "soup", "reason": "Source excerpt",
                "evidence_ids": [evidenceID],
            ]
        ],
    ]
}
private func turn(pending: Bool = false) -> [String: Any] {
    [
        "session_id": wire(sessionID), "request_id": wire(turnID), "based_revision": "1",
        "context_hash": fingerprint, "state": pending ? "pending" : "terminal",
        "result": pending ? NSNull() : proposal(), "decision": NSNull(),
    ]
}

private final class Harness: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBody = Data()
    private var storedStatus = 200
    private var storedType = "application/json;charset=utf-8"
    private var storedWait = false
    private var storedRequests: [URLRequest] = []
    private var storedStops = 0
    private var storedAuthCalls = 0
    private var storedGeneration = initialGeneration
    private var storedOwner = owner

    func configure(
        _ value: Any, status: Int = 200, contentType: String = "application/json;charset=utf-8",
        wait: Bool = false
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        lock.lock()
        storedBody = data
        storedStatus = status
        storedType = contentType
        storedWait = wait
        storedRequests = []
        storedStops = 0
        lock.unlock()
    }
    func response(_ request: URLRequest) -> (Data, Int, String, Bool) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
        return (storedBody, storedStatus, storedType, storedWait)
    }
    func stopped() {
        lock.lock()
        storedStops += 1
        lock.unlock()
    }
    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }
    var stops: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStops
    }
    var authCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAuthCalls
    }
    func credential(_ requested: UUID) -> RecipeDraftCredential {
        lock.lock()
        defer { lock.unlock() }
        storedAuthCalls += 1
        return RecipeDraftCredential(
            ownerID: requested, generation: storedGeneration, bearerToken: "synthetic-secret")
    }
    func isCurrent(_ credential: RecipeDraftCredential) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedOwner == credential.ownerID && storedGeneration == credential.generation
    }
    func replace(owner next: UUID = owner) {
        lock.lock()
        storedOwner = next
        storedGeneration = UUID()
        lock.unlock()
    }
}
private final class DraftProtocol: URLProtocol, @unchecked Sendable {
    static let harness = Harness()
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    override func startLoading() {
        let (data, status, contentType, wait) = Self.harness.response(request)
        if wait {
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.harness.stopped()
    }
}
private func client(enabled: Bool = true) throws -> RecipeDraftClient {
    let h = DraftProtocol.harness
    return try RecipeDraftClient(
        functionBaseURL: URL(string: "https://unit.test/functions/v1")!, enabled: enabled,
        authenticate: { h.credential($0) }, isOwnerCurrent: { h.isCurrent($0) },
        send: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DraftProtocol.self]
            return try await RecipeShareHTTPTransport.send($0, configuration: configuration)
        })
}
@MainActor
private func expectFailure(
    _ operation: () async throws -> Void, _ expected: RecipeDraftClientError? = nil
) async throws {
    do {
        try await operation()
        fatalError("Expected failure")
    } catch let error as RecipeDraftClientError {
        if let expected {
            precondition(error == expected)
        }
    } catch {
        if expected != nil {
            throw error
        }
    }
}
private func invalid<T: Decodable>(_ type: T.Type, _ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    do {
        _ = try JSONDecoder().decode(type, from: data)
        fatalError("Expected invalid DTO")
    } catch {}
}

private actor PhaseSignal {
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var checks = 0
    func nextCheck() -> Int {
        checks += 1
        return checks
    }
    func signal() {
        entered = true
        waiter?.resume()
        waiter = nil
    }
    func wait() async {
        if entered {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }
}

@main
private struct DraftTests {
    static func main() async throws {
        let h = DraftProtocol.harness
        let c = try client()
        let revision = try RecipeDraftRevision("1")
        var vectors = 0
        for status in [200, 201] {
            try h.configure(session(), status: status)
            let value = try await c.createSession(jobID: job, clientRequestID: key, ownerID: owner)
            precondition(value.jobID == wire(job))
            let request = h.requests[0]
            precondition(
                request.url!.absoluteString
                    == "https://unit.test/functions/v1/recipe-draft-sessions")
            precondition(
                request.httpMethod == "POST"
                    && request.value(forHTTPHeaderField: "Authorization")
                        == "Bearer synthetic-secret"
            )
            let body =
                try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            precondition(body == ["job_id": wire(job), "client_request_id": wire(key)])
            vectors += 1
        }
        try h.configure(session())
        _ = try await c.fetchSession(sessionID: sessionID, ownerID: owner)
        precondition(h.requests[0].httpBody == nil && h.requests[0].httpMethod == "GET")
        vectors += 1
        for pending in [true, false] {
            try h.configure(turn(pending: pending), status: pending ? 202 : 200)
            let result = try await c.createTurn(
                sessionID: sessionID, requestID: turnID, expectedRevision: revision,
                message: "Review", ownerID: owner)
            precondition(result.state == (pending ? "pending" : "terminal"))
            precondition(
                h.requests[0].url!.path == "/functions/v1/recipe-draft-sessions/" + wire(sessionID)
                    + "/turns")
            let body =
                try JSONSerialization.jsonObject(with: h.requests[0].httpBody!) as! [String: String]
            precondition(
                body == ["request_id": wire(turnID), "expected_revision": "1", "message": "Review"])
            vectors += 1
            try h.configure(turn(pending: pending))
            _ = try await c.fetchTurn(sessionID: sessionID, requestID: turnID, ownerID: owner)
            vectors += 1
        }
        try h.configure(receipt())
        let old = try await c.approveTurn(
            sessionID: sessionID, turnRequestID: turnID, requestID: approvalID,
            expectedRevision: RecipeDraftRevision("9223372036854775807"), action: "accept",
            selectedPaths: ["title"], ownerID: owner)
        precondition(old.appliedRevision.rawValue == "2")
        let approvalBody =
            try JSONSerialization.jsonObject(with: h.requests[0].httpBody!) as! [String: Any]
        precondition(
            Set(approvalBody.keys)
                == Set(["request_id", "expected_revision", "action", "selected_paths"]))
        vectors += 1
        var decided = turn()
        decided["decision"] = receipt()
        try h.configure(decided)
        let decidedTurn = try await c.fetchTurn(
            sessionID: sessionID, requestID: turnID, ownerID: owner)
        precondition(decidedTurn.decision?.appliedRevision.rawValue == "2")
        vectors += 1
        var rejected = receipt()
        rejected["action"] = "reject"
        rejected["selected_paths"] = [String]()
        try h.configure(rejected)
        _ = try await c.approveTurn(
            sessionID: sessionID, turnRequestID: turnID, requestID: approvalID,
            expectedRevision: revision, action: "reject", selectedPaths: [], ownerID: owner)
        vectors += 1
        var changedReceipt = receipt()
        changedReceipt["request_id"] = wire(key)
        try h.configure(changedReceipt)
        try await expectFailure(
            {
                _ = try await c.approveTurn(
                    sessionID: sessionID, turnRequestID: turnID, requestID: approvalID,
                    expectedRevision: revision, action: "accept", selectedPaths: ["title"],
                    ownerID: owner)
            }, .invalidResponse)
        vectors += 1
        var largeContext = context()
        var largeFields: [String: Any] = [:]
        for index in 0..<100 {
            largeFields["steps[\(index)].instruction"] = [
                "raw_value": String(repeating: "x", count: 1000), "evidence_ids": [String](),
                "user_confirmed": true, "origin": "user",
            ]
        }
        largeContext["fields"] = largeFields
        largeContext["review_fields"] = [String]()
        largeContext["evidence"] = [[String: String]]()
        largeContext["status"] = "ready"
        var largeSession = session()
        largeSession["context"] = largeContext
        let largeData = try JSONSerialization.data(withJSONObject: largeSession)
        precondition(largeData.count > 32768)
        try h.configure(largeSession)
        _ = try await c.fetchSession(sessionID: sessionID, ownerID: owner)
        vectors += 1
        var approvedContext = context()
        approvedContext["status"] = "ready"
        approvedContext["review_fields"] = [String]()
        approvedContext["fields"] = [
            "title": [
                "raw_value": "Soup", "evidence_ids": [evidenceID], "user_confirmed": true,
                "origin": "AI_suggested",
            ]
        ]
        var approvedSession = session()
        approvedSession["revision"] = "2"
        approvedSession["context"] = approvedContext
        approvedSession["overlay"] = [
            "title": [
                "raw_value": "Soup", "evidence_ids": [evidenceID], "user_confirmed": true,
                "origin": "AI_suggested", "confirmed_revision": "2",
            ]
        ]
        _ = try JSONDecoder().decode(
            RecipeDraftSession.self, from: JSONSerialization.data(withJSONObject: approvedSession))
        vectors += 1
        for value in ["3", 2] as [Any] {
            var bad = approvedSession
            bad["overlay"] = [
                "title": [
                    "raw_value": "Soup", "evidence_ids": [evidenceID], "user_confirmed": true,
                    "origin": "AI_suggested", "confirmed_revision": value,
                ]
            ]
            try invalid(RecipeDraftSession.self, bad)
            vectors += 1
        }
        var scalarContext = approvedContext
        scalarContext["fields"] = [
            "title": [
                "raw_value": "e\u{301}", "evidence_ids": [evidenceID], "user_confirmed": true,
                "origin": "AI_suggested",
            ]
        ]
        var scalarSession = approvedSession
        scalarSession["context"] = scalarContext
        scalarSession["overlay"] = [
            "title": [
                "raw_value": "é", "evidence_ids": [evidenceID], "user_confirmed": true,
                "origin": "AI_suggested", "confirmed_revision": "2",
            ]
        ]
        try invalid(RecipeDraftSession.self, scalarSession)
        vectors += 1
        scalarSession["overlay"] = [
            "title": [
                "raw_value": "e\u{301}", "evidence_ids": [evidenceID], "user_confirmed": true,
                "origin": "AI_suggested", "confirmed_revision": "2",
            ]
        ]
        let scalarDecoded = try JSONDecoder().decode(
            RecipeDraftSession.self, from: JSONSerialization.data(withJSONObject: scalarSession))
        precondition(scalarDecoded.overlay["title"]!.rawValue.utf8.elementsEqual("e\u{301}".utf8))
        vectors += 1
        for kind in ["questions", "suggestions"] {
            var scalarProposal = proposal()
            let values = ["é", "e\u{301}"]
            if kind == "questions" {
                scalarProposal[kind] = values.map {
                    ["path": "title", "question": $0, "evidence_ids": [evidenceID]] as [String: Any]
                }
            } else {
                scalarProposal[kind] = values.map {
                    ["path": "title", "raw_value": $0, "reason": $0, "evidence_ids": [evidenceID]]
                        as [String: Any]
                }
            }
            _ = try JSONDecoder().decode(
                RecipeDraftGenerationResult.self,
                from: JSONSerialization.data(withJSONObject: scalarProposal))
            vectors += 1
            var items = scalarProposal[kind] as! [[String: Any]]
            items[1] = items[0]
            scalarProposal[kind] = items
            try invalid(RecipeDraftGenerationResult.self, scalarProposal)
            vectors += 1
        }
        let finalChecks = PhaseSignal()
        let changedAfterDecode = try RecipeDraftClient(
            functionBaseURL: URL(string: "https://unit.test")!, authenticate: { h.credential($0) },
            isOwnerCurrent: { credential in
                let check = await finalChecks.nextCheck()
                if check == 3 { h.replace() }
                return h.isCurrent(credential)
            },
            send: { request in
                return (
                    try JSONSerialization.data(withJSONObject: session()),
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        try await expectFailure(
            { _ = try await changedAfterDecode.fetchSession(sessionID: sessionID, ownerID: owner) },
            .ownerChanged)
        vectors += 1
        let disabled = try client(enabled: false)
        try h.configure(session())
        let authBefore = h.authCalls
        try await expectFailure(
            {
                _ = try await disabled.createSession(
                    jobID: job, clientRequestID: key, ownerID: owner)
            }, .disabled)
        precondition(h.requests.isEmpty && h.authCalls == authBefore)
        try await expectFailure(
            {
                _ = try await disabled.createTurn(
                    sessionID: sessionID, requestID: turnID, expectedRevision: revision,
                    message: "Review", ownerID: owner)
            }, .disabled)
        try await expectFailure(
            {
                _ = try await disabled.approveTurn(
                    sessionID: sessionID, turnRequestID: turnID, requestID: approvalID,
                    expectedRevision: revision, action: "accept", selectedPaths: ["title"],
                    ownerID: owner)
            }, .disabled)
        precondition(h.requests.isEmpty && h.authCalls == authBefore)
        vectors += 2
        _ = try await disabled.fetchSession(sessionID: sessionID, ownerID: owner)
        vectors += 1
        for value in ["0", "01", "9223372036854775808", "-1", "1.0", " 1"] {
            do {
                _ = try RecipeDraftRevision(value)
                fatalError("Bad revision")
            } catch {}
            vectors += 1
        }
        for rev: Any in [1, 9_007_199_254_740_992] {
            var value = session()
            value["revision"] = rev
            try invalid(RecipeDraftSession.self, value)
            vectors += 1
        }
        for (type, mutate) in [
            ("extra", { (s: inout [String: Any]) in s["owner_id"] = wire(owner) }),
            ("missing", { (s: inout [String: Any]) in s.removeValue(forKey: "job_id") }),
            (
                "uppercase",
                { (s: inout [String: Any]) in s["session_id"] = wire(sessionID).uppercased() }
            ),
            ("fingerprint", { (s: inout [String: Any]) in s["source_fingerprint"] = "" }),
            ("hash", { (s: inout [String: Any]) in s["context_hash"] = "x" }),
            (
                "budget",
                { (s: inout [String: Any]) in
                    s["budget"] = [
                        "reserved_tokens": 32768, "settled_tokens": 1, "dispatch_count": 0,
                    ]
                }
            ),
        ] {
            var value = session()
            mutate(&value)
            try invalid(RecipeDraftSession.self, value)
            _ = type
            vectors += 1
        }
        for mutate in [
            { (v: inout [String: Any]) in v["review_fields"] = ["private"] },
            { (v: inout [String: Any]) in v["review_fields"] = ["title", "title"] },
            { (v: inout [String: Any]) in v["evidence"] = [["id": evidenceID, "excerpt": ""]] },
            { (v: inout [String: Any]) in v["evidence"] = [] },
            { (v: inout [String: Any]) in
                v["fields"] = [
                    "ingredients[100].name": [
                        "raw_value": "x", "evidence_ids": [], "user_confirmed": false,
                        "origin": "user",
                    ]
                ]
            },
        ] {
            var value = context()
            mutate(&value)
            try invalid(RecipeDraftContext.self, value)
            vectors += 1
        }
        var missing = context()
        missing["fields"] = [:]
        missing["evidence"] = []
        missing["review_fields"] = ["title", "ingredients", "steps"]
        _ = try JSONDecoder().decode(
            RecipeDraftContext.self, from: JSONSerialization.data(withJSONObject: missing))
        vectors += 1
        for mutate in [
            { (v: inout [String: Any]) in v["state"] = "queued" },
            { (v: inout [String: Any]) in v["result"] = NSNull() },
            { (v: inout [String: Any]) in v.removeValue(forKey: "decision") },
            { (v: inout [String: Any]) in v["decision"] = ["extra": 1] },
        ] {
            var value = turn()
            mutate(&value)
            try invalid(RecipeDraftTurn.self, value)
            vectors += 1
        }
        var pendingDecision = turn(pending: true)
        pendingDecision["decision"] = receipt()
        try invalid(RecipeDraftTurn.self, pendingDecision)
        vectors += 1
        for mutate in [
            { (v: inout [String: Any]) in v["origin"] = "model" },
            { (v: inout [String: Any]) in v["requires_approval"] = false },
            { (v: inout [String: Any]) in
                v["questions"] = [
                    ["path": "private", "question": "?", "evidence_ids": [evidenceID]]
                ]
            },
            { (v: inout [String: Any]) in
                v["suggestions"] = [
                    [
                        "path": "ingredients", "raw_value": "x", "reason": "x",
                        "evidence_ids": [evidenceID],
                    ]
                ]
            },
        ] {
            var value = proposal()
            mutate(&value)
            try invalid(RecipeDraftGenerationResult.self, value)
            vectors += 1
        }
        for code in ["INVALID_INPUT", "PROVIDER_OUTCOME_UNKNOWN"] {
            _ = try JSONDecoder().decode(
                RecipeDraftGenerationResult.self,
                from: JSONSerialization.data(withJSONObject: [
                    "status": "unavailable", "code": code,
                ]))
            vectors += 1
        }
        try invalid(RecipeDraftGenerationResult.self, ["status": "rejected", "code": "SECRET"])
        vectors += 1
        for (code, status) in RecipeDraftAPIError.statuses {
            try h.configure(
                [
                    "code": code, "message": "Safe error", "recoverable": false,
                    "request_id": wire(key),
                ], status: status)
            do {
                _ = try await c.fetchSession(sessionID: sessionID, ownerID: owner)
                fatalError("Expected API error")
            } catch let error as RecipeDraftAPIError {
                precondition(error.code == code)
            }
            vectors += 1
        }
        for (value, status, type) in [
            (session(), 204, "application/json"), (session(), 200, "text/html"),
            (["code": "SECRET"], 500, "application/json"),
            (
                [
                    "code": "NOT_FOUND", "message": "Safe", "recoverable": false,
                    "request_id": wire(key),
                ], 401, "application/json"
            ),
        ] {
            try h.configure(value, status: status, contentType: type)
            try await expectFailure(
                { _ = try await c.fetchSession(sessionID: sessionID, ownerID: owner) },
                .invalidResponse)
            vectors += 1
        }
        for pending in [true, false] {
            try h.configure(turn(pending: pending), status: pending ? 200 : 202)
            try await expectFailure(
                {
                    _ = try await c.createTurn(
                        sessionID: sessionID, requestID: turnID, expectedRevision: revision,
                        message: "", ownerID: owner)
                }, .invalidResponse)
            vectors += 1
        }
        var wrong = session()
        wrong["session_id"] = wire(job)
        try h.configure(wrong)
        try await expectFailure(
            { _ = try await c.fetchSession(sessionID: sessionID, ownerID: owner) }, .invalidResponse
        )
        vectors += 1
        for text in [
            String(repeating: "😀", count: 2000), String(repeating: "e\u{301}", count: 1000),
        ] {
            try h.configure(turn(pending: true), status: 202)
            _ = try await c.createTurn(
                sessionID: sessionID, requestID: turnID, expectedRevision: revision, message: text,
                ownerID: owner)
            vectors += 1
            try await expectFailure(
                {
                    _ = try await c.createTurn(
                        sessionID: sessionID, requestID: turnID, expectedRevision: revision,
                        message: text + "x", ownerID: owner)
                }, .invalidInput)
            vectors += 1
        }
        try h.configure(session())
        let switched = try RecipeDraftClient(
            functionBaseURL: URL(string: "https://unit.test")!, authenticate: { h.credential($0) },
            isOwnerCurrent: { h.isCurrent($0) },
            send: { request in
                h.replace(owner: UUID())
                h.replace(owner: owner)
                return (
                    try JSONSerialization.data(withJSONObject: session()),
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        try await expectFailure(
            { _ = try await switched.fetchSession(sessionID: sessionID, ownerID: owner) },
            .ownerChanged)
        vectors += 1
        for stage in ["auth", "check", "finalcheck"] {
            let signal = PhaseSignal()
            let delayed = try RecipeDraftClient(
                functionBaseURL: URL(string: "https://unit.test")!,
                authenticate: {
                    if stage == "auth" {
                        await signal.signal()
                        try? await Task.sleep(for: .seconds(30))
                    }
                    return h.credential($0)
                },
                isOwnerCurrent: { credential in
                    let check = await signal.nextCheck()
                    if stage == "check" || (stage == "finalcheck" && check == 3) {
                        await signal.signal()
                        try? await Task.sleep(for: .seconds(30))
                    }
                    return h.isCurrent(credential)
                },
                send: { request in
                    if stage != "finalcheck" {
                        fatalError("Cancelled preparation must not send")
                    }
                    return (
                        try JSONSerialization.data(withJSONObject: session()),
                        HTTPURLResponse(
                            url: request.url!, statusCode: 200, httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"])!
                    )
                })
            let task = Task { try await delayed.fetchSession(sessionID: sessionID, ownerID: owner) }
            await signal.wait()
            task.cancel()
            do {
                _ = try await task.value
                fatalError("Cancelled")
            } catch is CancellationError {}
            vectors += 1
        }
        for value in [wire(sessionID) + "\n", fingerprint + "\n", "title\n"] {
            if value.hasPrefix("title") {
                precondition(!draftPath(value))
            } else if value.hasPrefix(fingerprint) {
                precondition(!draftHash(value))
            } else {
                precondition(!draftUUID(value))
            }
            vectors += 1
        }
        for escaped in [#""\ud800""#, #""\udfff""#] {
            let bytes = Data(
                ("{\"raw_value\":" + escaped
                    + ",\"evidence_ids\":[],\"user_confirmed\":false,\"origin\":\"user\"}").utf8)
            do {
                _ = try JSONDecoder().decode(RecipeDraftField.self, from: bytes)
                fatalError("Lone surrogate accepted")
            } catch {}
            vectors += 1
        }
        var maxSession = session()
        maxSession["revision"] = "9223372036854775807"
        try h.configure(maxSession)
        let maxResult = try await c.fetchSession(sessionID: sessionID, ownerID: owner)
        precondition(maxResult.revision.rawValue == "9223372036854775807")
        vectors += 1
        for scheme in [
            "http://unit.test", "https://user@unit.test", "https://unit.test?query=x",
            "https://unit.test#fragment",
        ] {
            do {
                _ = try RecipeDraftClient(
                    functionBaseURL: URL(string: scheme)!, authenticate: { h.credential($0) },
                    isOwnerCurrent: { h.isCurrent($0) })
                fatalError("Invalid base accepted")
            } catch {}
            vectors += 1
        }
        let invalidOwner = try RecipeDraftClient(
            functionBaseURL: URL(string: "https://unit.test")!,
            authenticate: { _ in
                RecipeDraftCredential(ownerID: UUID(), generation: UUID(), bearerToken: "token")
            }, isOwnerCurrent: { _ in true }, send: { _ in fatalError("Wrong owner sends") })
        try await expectFailure(
            { _ = try await invalidOwner.fetchSession(sessionID: sessionID, ownerID: owner) },
            .ownerChanged)
        vectors += 1
        let lateSignal = PhaseSignal()
        let late = try RecipeDraftClient(
            functionBaseURL: URL(string: "https://unit.test")!, authenticate: { h.credential($0) },
            isOwnerCurrent: { h.isCurrent($0) },
            send: { request in
                await lateSignal.signal()
                try? await Task.sleep(for: .seconds(30))
                return (
                    try JSONSerialization.data(withJSONObject: session()),
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        let lateTask = Task { try await late.fetchSession(sessionID: sessionID, ownerID: owner) }
        await lateSignal.wait()
        lateTask.cancel()
        do {
            _ = try await lateTask.value
            fatalError("Late result")
        } catch is CancellationError {}
        vectors += 1
        try h.configure(session(), wait: true)
        let task = Task { try await c.fetchSession(sessionID: sessionID, ownerID: owner) }
        for _ in 0..<10000 {
            if !h.requests.isEmpty {
                break
            }
            await Task.yield()
        }
        precondition(!h.requests.isEmpty)
        task.cancel()
        do {
            _ = try await task.value
            fatalError("Cancelled send")
        } catch is CancellationError {}
        precondition(h.stops > 0)
        vectors += 1
        print(
            "PASS \(vectors) draft client vectors (original DTO/client/transport, no domain stubs)")
    }
}
