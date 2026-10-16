// Developer: gengyun
// Purpose: Builds the Supabase client from Recipe project configuration without exposing secret keys.

import Foundation
import Supabase

enum RecipeSupabase {
    static let redirectURL = URL(string: "recipePals://auth/callback")!
    static let productionAuthStorageService = "com.modelhub.cook.supabase-auth"
    static let uiTestAuthStorageService = "com.shopkivoo.recipe.uitesting-auth"
    static let qaAuthStorageService = "com.shopkivoo.recipe.qa.supabase-auth"

    static let client: SupabaseClient = {
        #if RECIPE_QA
            return makeQAClient()
        #else
            #if DEBUG
                if RecipeUITestNamespace.isUITesting {
                    return makeUITestClient()
                }
            #endif
            return makeProductionClient()
        #endif
    }()

    /// Uses the captured per-invocation JWT without SupabaseClient's auth adapter.
    static let accountDeletionFunctions: FunctionsClient = {
        #if RECIPE_QA
            let configuration = qaConfiguration()
        #else
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
        #endif
        return FunctionsClient(
            url: configuration.url.appendingPathComponent("functions/v1"),
            headers: ["apikey": configuration.key]
        )
    }()

    /// Optional owner-sharing management endpoint. Absent or invalid configuration keeps
    /// sharing unavailable (`nil`), so a build never fakes publication without a verified
    /// deployed host. `RecipeSharePublishingService` re-validates the same shape before use.
    static let shareManagementEndpoint: URL? = {
        guard
            let string = Bundle.main.object(forInfoDictionaryKey: "RecipeShareManagementEndpointURL")
                as? String,
            !string.isEmpty,
            let url = URL(string: string),
            url.scheme == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil,
            url.path == "/functions/v1/recipe-share-manage"
        else {
            return nil
        }
        return url
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

    #if RECIPE_QA
        private static func makeQAClient() -> SupabaseClient {
            let configuration = qaConfiguration()
            return SupabaseClient(
                supabaseURL: configuration.url,
                supabaseKey: configuration.key,
                options: .init(
                    auth: .init(
                        storage: KeychainLocalStorage(service: qaAuthStorageService)
                    )
                )
            )
        }

        /// QA builds read only the explicit `RECIPE_QA_SUPABASE_URL` /
        /// `RECIPE_QA_SUPABASE_PUBLISHABLE_KEY` build settings (surfaced through
        /// Info.plist). Missing, empty, or invalid values fail closed here and
        /// never silently fall back to the ordinary production configuration.
        private static func qaConfiguration() -> (url: URL, key: String) {
            guard
                let urlString = Bundle.main.object(forInfoDictionaryKey: "RecipeQASupabaseURL")
                    as? String,
                !urlString.isEmpty,
                let url = URL(string: urlString),
                url.scheme == "https",
                url.host != nil,
                url.user == nil,
                url.password == nil
            else {
                preconditionFailure(
                    "Recipe QA Supabase URL (RECIPE_QA_SUPABASE_URL) is missing or invalid."
                )
            }
            guard
                let key = Bundle.main.object(
                    forInfoDictionaryKey: "RecipeQASupabasePublishableKey"
                ) as? String,
                !key.isEmpty
            else {
                preconditionFailure(
                    "Recipe QA Supabase publishable key "
                        + "(RECIPE_QA_SUPABASE_PUBLISHABLE_KEY) is missing or empty."
                )
            }
            return (url, key)
        }
    #endif
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
