// Developer: gengyun
// Purpose: Implements Supabase email, Apple, and Google authentication flows.

import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

enum RecipeAuthState: Equatable, Sendable {
    case loading
    case signedOut
    case authenticating
    case emailCodeSent(String)
    case needsEmailVerification(String)
    case signedIn(userID: UUID, email: String?)
    case passwordResetSent(String)
    case passwordRecovery(userID: UUID)
    case error(String)
}

@MainActor @Observable
final class RecipeAuthService {
    static let shared = RecipeAuthService()
    private static let pendingPasswordRecoveryKey = "recipe.auth.pending_password_recovery"
    private static let pendingPasswordRecoveryEmailKey =
        "recipe.auth.pending_password_recovery_email_hash"

    private(set) var state: RecipeAuthState = .loading
    private(set) var nonblockingNotice: String?
    /// Advances after each accepted callback so the root view can present Account.
    private(set) var authCallbackGeneration = 0
    private let client: SupabaseClient
    private let defaults: UserDefaults

    init(
        client: SupabaseClient = RecipeSupabase.client,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        Task { [weak self, client] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else {
                    return
                }
                if event == .passwordRecovery, let session {
                    self.state = .passwordRecovery(userID: session.user.id)
                } else if let session {
                    if case .passwordRecovery(let recoveryUserID) = self.state,
                        recoveryUserID == session.user.id
                    {
                        continue
                    }
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
                redirectTo: RecipeSupabase.redirectURL
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

    func sendEmailCode(to email: String) async throws {
        state = .authenticating
        do {
            try await client.auth.signInWithOTP(
                email: email,
                shouldCreateUser: true
            )
            state = .emailCodeSent(email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func verifyEmailCode(_ code: String, for email: String) async throws {
        state = .authenticating
        do {
            let response = try await client.auth.verifyOTP(
                email: email,
                token: code,
                type: .email
            )
            guard let session = response.session else {
                throw AuthFlowError.missingSession
            }
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func signInWithGoogle() async throws {
        state = .authenticating
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: RecipeSupabase.redirectURL
            )
            state = .signedIn(userID: session.user.id, email: session.user.email)
        } catch {
            if let sessionError = error as? ASWebAuthenticationSessionError,
                sessionError.code == .canceledLogin
            {
                state = .signedOut
                return
            }
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func sendPasswordReset(to email: String) async throws {
        state = .authenticating
        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: RecipeSupabase.redirectURL
            )
            // PKCE callbacks are generic sign-ins, so retain the reset intent across app restarts.
            defaults.set(
                passwordRecoveryEmailHash(for: email),
                forKey: Self.pendingPasswordRecoveryEmailKey
            )
            defaults.set(true, forKey: Self.pendingPasswordRecoveryKey)
            state = .passwordResetSent(email)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func setRecoveredPassword(_ password: String) async throws {
        let recoveryState = state
        do {
            let user = try await client.auth.update(user: UserAttributes(password: password))
            state = .signedIn(userID: user.id, email: user.email)
        } catch {
            // Keep the recovery form available so the user can correct or retry
            // without reopening the email link after a recoverable failure.
            state = recoveryState
            throw error
        }
    }

    func signInWithApple(identityToken: String, rawNonce: String, fullName: String? = nil)
        async throws
    {
        state = .authenticating
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: rawNonce
                )
            )
            // The verified session is the success boundary. Apple only
            // provides a person's name on first consent, and an optional
            // profile update must not turn a valid login into an auth error.
            state = .signedIn(userID: session.user.id, email: session.user.email)
            if let fullName, !fullName.isEmpty {
                do {
                    try await client.auth.update(
                        user: UserAttributes(data: ["full_name": .string(fullName)])
                    )
                } catch {
                    nonblockingNotice =
                        "Signed in successfully, but your name couldn't be saved. You can update your profile later."
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    func dismissNotice() {
        nonblockingNotice = nil
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
        let acceptedSchemes = [
            RecipeSupabase.redirectURL.scheme,
            RecipeSupabase.legacyRedirectURL.scheme,
        ]
        guard acceptedSchemes.contains(url.scheme ?? ""),
            url.host == RecipeSupabase.redirectURL.host,
            url.path == RecipeSupabase.redirectURL.path
        else {
            return
        }

        let isExplicitRecoveryCallback = callbackType(in: url) == "recovery"
        Task {
            do {
                let session = try await client.auth.session(from: url)
                let pendingRecoveryEmailHash = defaults.string(
                    forKey: Self.pendingPasswordRecoveryEmailKey
                )
                let callbackEmailMatchesPendingReset =
                    session.user.email.map {
                        passwordRecoveryEmailHash(for: $0) == pendingRecoveryEmailHash
                    } ?? false
                let isPasswordRecovery =
                    isExplicitRecoveryCallback
                    || (defaults.bool(forKey: Self.pendingPasswordRecoveryKey)
                        && callbackEmailMatchesPendingReset)

                // Consume the marker only after the PKCE code has been exchanged successfully.
                defaults.removeObject(forKey: Self.pendingPasswordRecoveryKey)
                defaults.removeObject(forKey: Self.pendingPasswordRecoveryEmailKey)
                authCallbackGeneration += 1
                if isPasswordRecovery {
                    state = .passwordRecovery(userID: session.user.id)
                }
            } catch {
                state = .error(error.localizedDescription)
                authCallbackGeneration += 1
            }
        }
    }

    private func callbackType(in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        if let type = queryItems.first(where: {
            $0.name == "type"
        })?.value {
            return type
        }
        if let flow = queryItems.first(where: {
            $0.name == "flow"
        })?.value {
            return flow
        }
        guard let fragment = components.fragment,
            let fragmentComponents = URLComponents(string: "?\(fragment)")
        else {
            return nil
        }
        let fragmentItems = fragmentComponents.queryItems ?? []
        return fragmentItems.first(where: {
            $0.name == "type"
        })?.value
            ?? fragmentItems.first(where: {
                $0.name == "flow"
            })?.value
    }

    private func passwordRecoveryEmailHash(for email: String) -> String {
        let normalizedEmail =
            email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let digest = SHA256.hash(data: Data(normalizedEmail.utf8))
        return digest.map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func makeAppleNonce() -> (raw: String, hashed: String) {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return (
            raw,
            digest.map {
                String(format: "%02x", $0)
            }.joined()
        )
    }
}

private enum AuthFlowError: LocalizedError {
    case missingSession

    var errorDescription: String? {
        "Email verification completed without an authenticated session."
    }
}
