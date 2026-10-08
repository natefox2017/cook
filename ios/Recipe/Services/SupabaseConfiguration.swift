// Developer: gengyun
// Purpose: Builds the Supabase client from Recipe project configuration without exposing secret keys.

import Foundation
import Supabase

enum RecipeSupabase {
    static let redirectURL = URL(string: "cook://auth/callback")!

    static let client: SupabaseClient = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "RecipeSupabaseURL") as? String,
              let url = URL(string: urlString),
              let key = Bundle.main.object(forInfoDictionaryKey: "RecipeSupabasePublishableKey") as? String,
              !key.isEmpty else {
            preconditionFailure("Recipe Supabase URL and publishable key are required.")
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
