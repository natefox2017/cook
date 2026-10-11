// Developer: gengyun
// Purpose: Sends owner-share requests without redirects, persistent credentials, or unbounded downloads.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum RecipeShareHTTPTransportError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case redirectRejected
}

/// Inject `send` into the existing publishing client; this transport never obtains an auth session.
public enum RecipeShareHTTPTransport {
    public static let maximumBodyBytes = 2 * 1024 * 1024

    public static func send(
        _ request: URLRequest,
        configuration: URLSessionConfiguration = .ephemeral
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard let url = request.url,
            url.scheme == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil,
            url.fragment == nil,
            request.httpBodyStream == nil,
            (request.httpBody?.count ?? 0) <= maximumBodyBytes
        else {
            throw RecipeShareHTTPTransportError.invalidRequest
        }
        // Snapshot the caller without mutating it. Background sessions cannot provide this data-task contract.
        guard configuration.identifier == nil,
            let supplied = configuration.copy() as? URLSessionConfiguration
        else {
            throw RecipeShareHTTPTransportError.invalidRequest
        }
        // Always create an ephemeral session; only synthetic protocol classes are injectable.
        let isolated = URLSessionConfiguration.ephemeral
        isolated.protocolClasses = supplied.protocolClasses
        isolated.httpShouldSetCookies = false
        isolated.httpCookieStorage = nil
        isolated.urlCredentialStorage = nil
        isolated.urlCache = nil
        isolated.httpAdditionalHeaders = nil
        isolated.requestCachePolicy = .reloadIgnoringLocalCacheData
        isolated.timeoutIntervalForRequest = 20
        isolated.timeoutIntervalForResource = 25
        var outgoing = request
        outgoing.cachePolicy = .reloadIgnoringLocalCacheData
        outgoing.timeoutInterval = 20
        let operation = RecipeShareHTTPTransfer()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(outgoing, configuration: isolated, continuation: continuation)
            }
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}

/// URLSession callbacks and Swift cancellation may race; the lock protects every mutable field.
final class RecipeShareHTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private typealias Output = (Data, HTTPURLResponse)
    private let lock = NSLock()
    private var result: Result<Output, Error>?
    private var continuation: CheckedContinuation<Output, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()

    func start(
        _ request: URLRequest,
        configuration: URLSessionConfiguration,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) {
        lock.lock()
        // Cancellation before registration must resume the continuation without starting a request.
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        // If cancellation won after registration, invalidation already cancelled this suspended task.
        task.resume()
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ outcome: Result<Output, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        let continuation = self.continuation
        let session = self.session
        let task = self.task
        self.continuation = nil
        self.session = nil
        self.task = nil
        data.removeAll()
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: outcome)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Refuse all redirects before any owner bearer token could reach a second request.
        finish(.failure(RecipeShareHTTPTransportError.redirectRejected))
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
            http.url == dataTask.originalRequest?.url
        else {
            finish(.failure(RecipeShareHTTPTransportError.invalidResponse))
            completionHandler(.cancel)
            return
        }
        guard http.expectedContentLength <= RecipeShareHTTPTransport.maximumBodyBytes else {
            finish(.failure(RecipeShareHTTPTransportError.responseTooLarge))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        self.response = http
        let isActive = result == nil
        lock.unlock()
        completionHandler(isActive ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        guard chunk.count <= RecipeShareHTTPTransport.maximumBodyBytes - data.count else {
            lock.unlock()
            finish(.failure(RecipeShareHTTPTransportError.responseTooLarge))
            return
        }
        data.append(chunk)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = self.response
        let body = data
        lock.unlock()
        guard let response else {
            finish(.failure(RecipeShareHTTPTransportError.invalidResponse))
            return
        }
        // HTTP failures remain HTTP responses; the publishing client owns status interpretation/retry.
        finish(.success((body, response)))
    }
}
