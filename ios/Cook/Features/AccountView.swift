// Developer: gengyun
// Purpose: Presents account sign-in, recovery, and account-management flows.

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

    @State private var auth = CookAuthService.shared
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
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
        .background(CookTheme.canvas)
        .navigationTitle("Cook Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Cook Account",
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
                        Text(item.rawValue).tag(item)
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

                Button(mode.rawValue) {
                    performEmailAction()
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
            } footer: {
                Text(mode == .signIn
                     ? "Sign in to reconnect the same Cook account on another device."
                     : "Create one Cook account for future cloud sync. App Store purchases remain a separate Apple account entitlement.")
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
                    let nonce = CookAuthService.makeAppleNonce()
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
            } footer: {
                Text("Apple sign-in uses the native Apple authorization sheet, then exchanges the verified identity token with Cook’s Supabase Auth project.")
            }

            if let statusMessage {
                Section("Status") {
                    Label(statusMessage, systemImage: statusIcon)
                        .foregroundStyle(statusIsError ? Color.red : CookTheme.accentForeground)
                }
            }
        }
        .listSectionSpacing(CookSpacing.medium)
        .scrollContentBackground(.hidden)
    }

    private func signedInView(email: String?) -> some View {
        Form {
            Section {
                Label("Signed in", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(CookTheme.accentForeground)

                if let email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
            } header: {
                Text("Cook Account")
            }

            Section {
                Text("Your Cook account identifies future private cloud data. It is separate from the Apple ID that owns an App Store subscription.")
                    .foregroundStyle(.secondary)
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
        .listSectionSpacing(CookSpacing.medium)
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
                    guard newPassword == confirmPassword else {
                        localMessage = "The passwords do not match."
                        return
                    }
                    Task {
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
                .disabled(newPassword.count < 8 || confirmPassword.isEmpty || isAuthenticating)
            } header: {
                Text("Choose a new password")
            } footer: {
                Text("Use at least 8 characters.")
            }
        }
        .listSectionSpacing(CookSpacing.medium)
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
            return "Check \(address) to verify your account, then return to Cook."
        case .passwordResetSent(let address):
            return "A password reset link was sent to \(address)."
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
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = appleNonce else {
                localMessage = "Apple sign-in did not return a usable identity token."
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
