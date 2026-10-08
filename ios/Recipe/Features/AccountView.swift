// Developer: gengyun
// Purpose: Implements RecipePouch account authentication and recovery screens.

import AuthenticationServices
import Foundation
import SwiftUI

@MainActor
struct AccountView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Create Account"
        var id: Self { self }
    }

    @State private var auth = RecipeAuthService.shared
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isUpdatingPassword = false
    @State private var appleNonce: String?
    @State private var localMessage: String?

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView("Checking account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .signedIn(_, let email):
                signedInView(email: email)

            case .passwordRecovery:
                passwordRecoveryView

            default:
                signedOutView
            }
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: auth.state) { _, state in
            // Credentials are transient input; discard them after successful
            // authentication or password recovery.
            if case .signedIn = state {
                password = ""
                newPassword = ""
                confirmPassword = ""
            }
        }
        .onChange(of: auth.nonblockingNotice) { _, notice in
            if let notice {
                localMessage = notice
                auth.dismissNotice()
            }
        }
        .alert(
            "Account",
            isPresented: Binding(
                get: { localMessage != nil },
                set: { if !$0 { localMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { localMessage = nil }
        } message: {
            Text(localMessage ?? "")
        }
    }

    private var signedOutView: some View {
        Form {
            Section {
                Picker("Account action", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue)).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)

                Button {
                    performEmailAction()
                } label: {
                    Text(LocalizedStringKey(mode.rawValue))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmitEmail || isAuthenticating)
                .accessibilityIdentifier("account.submit")

                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Signing in")
                }
            } header: {
                Text("Account")
            }

            if mode == .signIn {
                Section {
                    Button("Forgot Password?") {
                        sendPasswordReset()
                    }
                    .disabled(!isValidEmail || isAuthenticating)
                }
            }

            Section {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = RecipeAuthService.makeAppleNonce()
                    appleNonce = nonce.raw
                    request.nonce = nonce.hashed
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .disabled(isAuthenticating)
                .accessibilityIdentifier("account.apple")
            }

            if let statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: statusIcon)
                        .foregroundStyle(statusIsError ? Color.red : RecipeTheme.accentForeground)
                }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
    }

    private func signedInView(email: String?) -> some View {
        Form {
            Section {
                Label("Signed in", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(RecipeTheme.accentForeground)

                if let email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
            } header: {
                Text("Account")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            try await auth.signOut()
                        } catch {
                            localMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(isAuthenticating)
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
    }

    private var passwordRecoveryView: some View {
        Form {
            Section {
                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)

                Button("Update Password") {
                    guard !isUpdatingPassword else { return }
                    guard newPassword == confirmPassword else {
                        localMessage = String(localized: "The passwords do not match.")
                        return
                    }
                    isUpdatingPassword = true
                    Task {
                        defer { isUpdatingPassword = false }
                        do {
                            try await auth.setRecoveredPassword(newPassword)
                            newPassword = ""
                            confirmPassword = ""
                        } catch {
                            localMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    newPassword.count < 8
                        || confirmPassword.isEmpty
                        || isAuthenticating
                        || isUpdatingPassword
                )
            } header: {
                Text("Choose a new password")
            } footer: {
                Text("Use at least 8 characters.")
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
    }

    private var canSubmitEmail: Bool {
        guard isValidEmail, !password.isEmpty else { return false }
        return mode == .signIn || password.count >= 8
    }

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var isAuthenticating: Bool {
        if case .authenticating = auth.state { return true }
        return false
    }

    private var statusMessage: String? {
        switch auth.state {
        case .needsEmailVerification(let address):
            return String(localized: "Check \(address) to verify your account, then return to RecipePouch.")
        case .passwordResetSent(let address):
            return String(localized: "If an account exists for \(address), check its inbox for a password reset link.")
        case .error(let message):
            return message
        default:
            return nil
        }
    }

    private var statusIsError: Bool {
        if case .error = auth.state { return true }
        return false
    }

    private var statusIcon: String {
        statusIsError ? "exclamationmark.triangle" : "envelope.badge"
    }

    private func performEmailAction() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                switch mode {
                case .signIn:
                    try await auth.signIn(email: trimmedEmail, password: password)
                case .signUp:
                    try await auth.signUp(email: trimmedEmail, password: password)
                }
            } catch {
                localMessage = error.localizedDescription
            }
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await auth.sendPasswordReset(to: trimmedEmail)
            } catch {
                localMessage = error.localizedDescription
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        // The nonce belongs only to this system authorization result.
        // Copy it before the async exchange and clear it even on cancellation.
        let pendingNonce = appleNonce
        appleNonce = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = pendingNonce else {
                localMessage = String(localized: "Apple sign-in did not return a usable identity token.")
                return
            }

            let fullName = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return formatted.isEmpty ? nil : formatted
            }

            Task {
                do {
                    try await auth.signInWithApple(
                        identityToken: identityToken,
                        rawNonce: rawNonce,
                        fullName: fullName
                    )
                } catch {
                    localMessage = error.localizedDescription
                }
            }

        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            localMessage = error.localizedDescription
        }
    }
}
