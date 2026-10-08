// Developer: gengyun
// Purpose: Loads Supabase configuration without embedding credentials.

import Foundation
import Supabase

enum CookSupabase {
    static let redirectURL = URL(string: "cook://auth/callback")!

    static let client: SupabaseClient = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "CookSupabaseURL") as? String,
              let url = URL(string: urlString),
              let key = Bundle.main.object(forInfoDictionaryKey: "CookSupabasePublishableKey") as? String,
              !key.isEmpty else {
            preconditionFailure("Cook Supabase URL and publishable key are required.")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: .init(
                auth: .init(
                    storage: KeychainLocalStorage(service: "com.modelhub.cook.supabase-auth")
                )
            )
        )
    }()
}
