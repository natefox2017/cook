// Developer: gengyun
// Purpose: Runs the original Foundation-only share transport with synthetic URLSession responses.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private final class FakeShareProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var stops = 0

    static var captured: [URLRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return requests
    }

    static var stopCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return stops
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let url = request.url!
        let scenario = url.lastPathComponent
        if scenario == "wait" {
            return
        }
        if scenario == "offline" || scenario == "timeout" {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(
                    scenario == "offline" ? .notConnectedToInternet : .timedOut
                ))
            return
        }
        if scenario == "nonhttp" {
            client?.urlProtocol(
                self,
                didReceive: URLResponse(
                    url: url, mimeType: "application/json", expectedContentLength: 0,
                    textEncodingName: nil
                ), cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var status = 200
        if scenario.hasPrefix("status-") {
            status = Int(scenario.dropFirst(7))!
        }
        var headers = ["Content-Type": "application/json"]
        if scenario == "declared" {
            headers["Content-Length"] = String(RecipeShareHTTPTransport.maximumBodyBytes + 1)
        }
        if scenario == "misreported" {
            headers["Content-Length"] = "1"
        }
        let responseURL = scenario == "mismatch" ? URL(string: "https://other.invalid/x")! : url
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: responseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            )!, cacheStoragePolicy: .notAllowed)
        if ["exact", "chunked", "misreported"].contains(scenario) {
            let block = Data(repeating: 65, count: RecipeShareHTTPTransport.maximumBodyBytes / 2)
            client?.urlProtocol(self, didLoad: block)
            client?.urlProtocol(self, didLoad: block)
            if scenario != "exact" {
                client?.urlProtocol(self, didLoad: Data([66]))
            }
        } else if status != 204 && scenario != "declared" {
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.stops += 1
        Self.lock.unlock()
    }
}

private enum TestFailure: Error {
    case assertion(String)
}

private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() {
        throw TestFailure.assertion(message)
    }
}

private func request(_ path: String, method: String = "GET") -> URLRequest {
    var value = URLRequest(url: URL(string: "https://share.invalid/" + path)!)
    value.httpMethod = method
    value.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
    value.setValue("application/json", forHTTPHeaderField: "Accept")
    value.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if method == "POST" || method == "PUT" {
        value.httpBody = Data("{\"idempotencyKey\":\"synthetic\"}".utf8)
        value.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if method == "PUT" {
        value.setValue("\"v7\"", forHTTPHeaderField: "If-Match")
    }
    return value
}

private func expectTransportError(
    _ path: String, _ expected: RecipeShareHTTPTransportError,
    configuration: URLSessionConfiguration
) async throws {
    do {
        _ = try await RecipeShareHTTPTransport.send(request(path), configuration: configuration)
        throw TestFailure.assertion("Expected transport rejection: " + path)
    } catch let error as RecipeShareHTTPTransportError {
        try check(error == expected, "Wrong transport error: " + path)
    }
}

@main
private enum TransportTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [FakeShareProtocol.self]
        configuration.timeoutIntervalForRequest = 91
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = ["Cookie": "synthetic-session-cookie"]
        let initialCache = configuration.urlCache
        var cases = 0

        for method in ["POST", "GET", "PUT", "DELETE"] {
            let original = request("status-" + (method == "DELETE" ? "204" : "201"), method: method)
            let (data, response) = try await RecipeShareHTTPTransport.send(
                original, configuration: configuration
            )
            let captured = FakeShareProtocol.captured.last!
            try check(captured.url == original.url, "URL changed")
            try check(captured.httpMethod == original.httpMethod, "Method changed")
            for header in ["Authorization", "Accept", "Content-Type", "If-Match", "Cache-Control"] {
                try check(
                    captured.value(forHTTPHeaderField: header)
                        == original.value(forHTTPHeaderField: header), "Header changed")
            }
            try check(captured.httpBody == original.httpBody, "Body changed")
            try check(
                captured.value(forHTTPHeaderField: "Cookie") == nil, "Configuration cookie leaked")
            try check(captured.cachePolicy == .reloadIgnoringLocalCacheData, "Caching was enabled")
            try check(captured.timeoutInterval == 20, "Request timeout is unbounded")
            try check(
                response.statusCode == (method == "DELETE" ? 204 : 201), "Success status changed")
            try check(method != "DELETE" || data.isEmpty, "204 must retain empty body")
            cases += 1
        }
        try check(configuration.timeoutIntervalForRequest == 91, "Caller timeout mutated")
        try check(configuration.httpShouldSetCookies, "Caller cookies mutated")
        try check(configuration.urlCache === initialCache, "Caller cache mutated")
        try check(
            configuration.httpAdditionalHeaders?["Cookie"] as? String == "synthetic-session-cookie",
            "Caller headers mutated")
        cases += 1

        for status in [200, 401, 403, 404, 409, 413, 429, 503] {
            let count = FakeShareProtocol.captured.count
            let (_, response) = try await RecipeShareHTTPTransport.send(
                request("status-\(status)"), configuration: configuration
            )
            try check(response.statusCode == status, "HTTP status changed")
            try check(FakeShareProtocol.captured.count == count + 1, "Transport retried")
            cases += 1
        }
        let (exact, _) = try await RecipeShareHTTPTransport.send(
            request("exact"), configuration: configuration)
        try check(exact.count == RecipeShareHTTPTransport.maximumBodyBytes, "Exact limit rejected")
        cases += 1
        for scenario in ["declared", "chunked", "misreported"] {
            try await expectTransportError(
                scenario, .responseTooLarge, configuration: configuration)
            cases += 1
        }
        for scenario in ["nonhttp", "mismatch"] {
            try await expectTransportError(scenario, .invalidResponse, configuration: configuration)
            cases += 1
        }
        for scenario in ["offline", "timeout"] {
            do {
                _ = try await RecipeShareHTTPTransport.send(
                    request(scenario), configuration: configuration)
                throw TestFailure.assertion("Network error became success")
            } catch let error as URLError {
                try check(
                    error.code == (scenario == "offline" ? .notConnectedToInternet : .timedOut),
                    "Wrong network error")
            }
            cases += 1
        }

        // Exercise the actual delegate policy without URLProtocol's unsupported Linux redirect callback.
        // This proves the refusal decision, not Apple URLSession's native redirect-following integration.
        let delegate = RecipeShareHTTPTransfer()
        let session = URLSession(configuration: .ephemeral)
        defer {
            session.invalidateAndCancel()
        }
        let task = session.dataTask(with: request("redirect"))
        for host in ["share.invalid", "other.invalid"] {
            delegate.urlSession(
                session, task: task,
                willPerformHTTPRedirection: HTTPURLResponse(
                    url: request("redirect").url!, statusCode: 302, httpVersion: nil,
                    headerFields: nil)!,
                newRequest: URLRequest(url: URL(string: "https://" + host + "/target")!),
                completionHandler: { redirected in
                    precondition(redirected == nil, "Redirect could forward credentials")
                })
            cases += 1
        }
        let redirectCount = FakeShareProtocol.captured.count
        do {
            let _: (Data, HTTPURLResponse) = try await withCheckedThrowingContinuation {
                continuation in
                delegate.start(
                    request("status-201"), configuration: configuration, continuation: continuation)
            }
            throw TestFailure.assertion("Rejected redirect restarted transfer")
        } catch RecipeShareHTTPTransportError.redirectRejected {
            try check(
                FakeShareProtocol.captured.count == redirectCount, "Redirect sent a second request")
        }
        cases += 1

        let beforeCancel = FakeShareProtocol.captured.count
        let cancelled = Task {
            withUnsafeCurrentTask {
                $0?.cancel()
            }
            return try await RecipeShareHTTPTransport.send(
                request("status-201"), configuration: configuration)
        }
        do {
            _ = try await cancelled.value
            throw TestFailure.assertion("Pre-cancelled request succeeded")
        } catch is CancellationError {
            try check(
                FakeShareProtocol.captured.count == beforeCancel, "Pre-cancelled task sent HTTP")
        }
        cases += 1

        // Repeated immediate cancellation exercises registration/resume races without live networking.
        for _ in 0..<30 {
            let racing = Task {
                try await RecipeShareHTTPTransport.send(
                    request("wait"), configuration: configuration)
            }
            racing.cancel()
            do {
                _ = try await racing.value
                throw TestFailure.assertion("Cancellation race returned success")
            } catch is CancellationError {
            }
        }
        cases += 1
        let beforeWait = FakeShareProtocol.captured.count
        let stops = FakeShareProtocol.stopCount
        let waiting = Task {
            try await RecipeShareHTTPTransport.send(request("wait"), configuration: configuration)
        }
        for _ in 0..<200 {
            if FakeShareProtocol.captured.count > beforeWait {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        try check(FakeShareProtocol.captured.count > beforeWait, "Synthetic request never started")
        waiting.cancel()
        do {
            _ = try await waiting.value
            throw TestFailure.assertion("Cancelled in-flight request succeeded")
        } catch is CancellationError {
        }
        for _ in 0..<200 {
            if FakeShareProtocol.stopCount > stops {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        try check(FakeShareProtocol.stopCount > stops, "Cancellation did not stop URLSession task")
        cases += 1

        async let first = RecipeShareHTTPTransport.send(
            request("status-201"), configuration: configuration)
        async let second = RecipeShareHTTPTransport.send(
            request("status-409"), configuration: configuration)
        let pair = try await (first, second)
        try check(
            pair.0.1.statusCode == 201 && pair.1.1.statusCode == 409, "Parallel responses mixed")
        cases += 1
        var unsafe = request("status-201")
        unsafe.url = URL(string: "http://share.invalid/status-201")!
        do {
            _ = try await RecipeShareHTTPTransport.send(unsafe, configuration: configuration)
            throw TestFailure.assertion("HTTP request accepted")
        } catch RecipeShareHTTPTransportError.invalidRequest {
        }
        cases += 1
        var oversized = request("status-201", method: "POST")
        oversized.httpBody = Data(
            repeating: 65, count: RecipeShareHTTPTransport.maximumBodyBytes + 1)
        let beforeInvalid = FakeShareProtocol.captured.count
        do {
            _ = try await RecipeShareHTTPTransport.send(oversized, configuration: configuration)
            throw TestFailure.assertion("Oversized request body accepted")
        } catch RecipeShareHTTPTransportError.invalidRequest {
            try check(
                FakeShareProtocol.captured.count == beforeInvalid, "Invalid body reached network")
        }
        cases += 1
        print(
            "PASS: \(cases) Foundation-only transport vectors; native/fullCore/JWT/staging NOT RUN."
        )
    }
}
