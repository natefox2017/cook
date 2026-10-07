import CryptoKit
import Foundation
import Observation
import Supabase

enum CookAuthState: Equatable, Sendable {
    case loading
    case signedOut
    case authenticating
    case needsEmailVerification(String)
    case signedIn(userID: UUID, email: String?)
    case passwordResetSent(String)
    case passwordRecovery(userID: UUID)
    case error(String)
}

@MainActor @Observable
final class CookAuthService {
    static let shared = CookAuthService()

    private(set) var state: CookAuthState = .loading
    private let client: SupabaseClient

    init(client: SupabaseClient = CookSupabase.client) {
        self.client = client
        Task { [weak self, client] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                if event == .passwordRecovery, let session {
                    self.state = .passwordRecovery(userID: session.user.id)
                } else if let session {
                    self.state = .signedIn(userID: session.user.id, email: session.user.email)
                } else {
                    self.state = .signedOut
                }
            }
        }
    }

    func signUp(email: String, password: String) async throws {
        state = .authenticating
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                redirectTo: CookSupabase.redirectURL
            )
            if let session = response.session {
                state = .signedIn(userID: session.user.id, email: session.user.email)
            } else {
                state = .needsEmailVerification(email)
            }
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func signIn(email: String, password: String) async throws {
        state = .authenticating
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func sendPasswordReset(to email: String) async throws {
        state = .authenticating
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: CookSupabase.redirectURL)
            state = .passwordResetSent(email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func setRecoveredPassword(_ password: String) async throws {
        do {
            let user = try await client.auth.update(user: UserAttributes(password: password))
            state = .signedIn(userID: user.id, email: user.email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func signInWithApple(identityToken: String, rawNonce: String, fullName: String? = nil) async throws {
        state = .authenticating
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: rawNonce
                )
            )
            if let fullName, !fullName.isEmpty {
                try await client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(fullName)])
                )
            }
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
            state = .signedOut
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func refreshSession() async throws {
        state = .authenticating
        do {
            let session = try await client.auth.refreshSession()
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func handleAuthCallback(_ url: URL) {
        guard url.scheme == CookSupabase.redirectURL.scheme,
              url.host == CookSupabase.redirectURL.host,
              url.path == CookSupabase.redirectURL.path else { return }
        client.auth.handle(url)
    }

    static func makeAppleNonce() -> (raw: String, hashed: String) {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return (raw, digest.map { String(format: "%02x", $0) }.joined())
    }
}
