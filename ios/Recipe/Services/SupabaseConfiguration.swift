// Developer: gengyun
// Purpose: Builds the Supabase client from Recipe project configuration without exposing secret keys.

import Foundation
import Supabase

enum RecipeSupabase {
    static let redirectURL = URL(string: "recipePals://auth/callback")!
    static let productionAuthStorageService = "com.modelhub.cook.supabase-auth"
    static let uiTestAuthStorageService = "com.shopkivoo.recipe.uitesting-auth"

    static let client: SupabaseClient = {
        #if DEBUG
            if RecipeUITestNamespace.isUITesting {
                return makeUITestClient()
            }
        #endif
        return makeProductionClient()
    }()

    /// Uses the captured per-invocation JWT without SupabaseClient's auth adapter.
    static let accountDeletionFunctions: FunctionsClient = {
        #if DEBUG
            if RecipeUITestNamespace.isUITesting {
                let session = makeUITestNetworkSession()
                return FunctionsClient(
                    url: URL(string: "https://uitesting.recipe.invalid/functions/v1")!,
                    headers: ["apikey": "sb_publishable_ui_test_only"],
                    fetch: { request in
                        try await session.data(for: request)
                    }
                )
            }
        #endif
        let configuration = productionConfiguration()
        return FunctionsClient(
            url: configuration.url.appendingPathComponent("functions/v1"),
            headers: ["apikey": configuration.key]
        )
    }()

    #if DEBUG
        private static func makeUITestNetworkSession() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RecipeUITestNetworkURLProtocol.self]
            return URLSession(configuration: configuration)
        }

        static func makeUITestClient() -> SupabaseClient {
            let session = makeUITestNetworkSession()
            return SupabaseClient(
                supabaseURL: URL(string: "https://uitesting.recipe.invalid")!,
                supabaseKey: "sb_publishable_ui_test_only",
                options: .init(
                    auth: .init(
                        storage: KeychainLocalStorage(
                            service: uiTestAuthStorageService
                        )
                    ),
                    global: .init(session: session)
                )
            )
        }
    #endif

    private static func makeProductionClient() -> SupabaseClient {
        let configuration = productionConfiguration()
        return SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.key,
            options: .init(
                auth: .init(
                    storage: KeychainLocalStorage(service: productionAuthStorageService)
                )
            )
        )
    }

    private static func productionConfiguration() -> (url: URL, key: String) {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "RecipeSupabaseURL")
                as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "RecipeSupabasePublishableKey")
                as? String,
            !key.isEmpty
        else {
            preconditionFailure("Recipe Supabase URL and publishable key are required.")
        }
        return (url, key)
    }
}

#if DEBUG
    final class RecipeUITestNetworkURLProtocol: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        // URLSession callbacks use arbitrary queues; every access stays under this lock.
        nonisolated(unsafe) private static var recordedHosts: [String] = []

        static var interceptedHosts: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedHosts
        }

        static func reset() {
            lock.lock()
            defer { lock.unlock() }
            recordedHosts.removeAll()
        }

        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }

        override func startLoading() {
            Self.lock.lock()
            let host = request.url?.host ?? ""
            Self.recordedHosts.append(host)
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }

        override func stopLoading() {
        }
    }
#endif
