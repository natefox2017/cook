// Developer: gengyun
// Purpose: Presents RecipePouch account sign-in, recovery, and session controls in a compact sheet.

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

    let onExpand: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var auth = RecipeAuthService.shared
    @State private var mode: Mode = .signIn
    @State private var isEmailExpanded = false
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isUpdatingPassword = false
    @State private var dismissAfterAuthentication = false
    @State private var appleNonce: String?
    @State private var localMessage: String?
    @State private var nonblockingMessage: String?

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView("Checking account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .signedIn(_, let address):
                signedInView(email: address)

            case .passwordRecovery:
                passwordRecoveryView

            default:
                signedOutView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RecipeTheme.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("account.close")
            }
        }
        .onChange(of: mode) { _, _ in
            localMessage = nil
        }
        .onChange(of: auth.state) { _, state in
            if case .signedIn = state {
                password = ""
                newPassword = ""
                confirmPassword = ""
                if dismissAfterAuthentication {
                    dismissAfterAuthentication = false
                    dismiss()
                }
            }
        }
        .onChange(of: auth.nonblockingNotice) { _, notice in
            if let notice {
                nonblockingMessage = notice
                auth.dismissNotice()
            }
        }
    }

    private var signedOutView: some View {
        ScrollView {
            VStack(spacing: 18) {
                header(
                    "Welcome to RecipePouch",
                    symbol: "leaf.fill",
                    subtitle: "Save and sync your recipes."
                )

                VStack(spacing: 16) {
                    SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
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

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 1)
                        Text("or")
                            .font(RecipeTheme.text(13, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 1)
                    }
                    .accessibilityHidden(true)

                    if isEmailExpanded {
                        emailForm
                    } else {
                        Button {
                            localMessage = nil
                            isEmailExpanded = true
                            onExpand()
                        } label: {
                            Label("Continue with email", systemImage: "envelope")
                                .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .headline))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(RecipeTheme.accentForeground)
                                .background(
                                    RecipeTheme.accent.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isAuthenticating)
                        .accessibilityIdentifier("account.email")
                    }
                }
                .padding(16)
                .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))

                if let feedback {
                    feedbackView(feedback)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            Picker("Account action", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Text(LocalizedStringKey(item.rawValue)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account.mode")

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .accountInputStyle()

            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .submitLabel(.go)
                .onSubmit {
                    if canSubmitEmail && !isAuthenticating {
                        performEmailAction()
                    }
                }
                .accountInputStyle()

            Button {
                performEmailAction()
            } label: {
                HStack(spacing: 10) {
                    if isAuthenticating {
                        ProgressView().tint(.white)
                    }
                    Text(LocalizedStringKey(mode.rawValue))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmitEmail || isAuthenticating)
            .accessibilityIdentifier("account.submit")

            if mode == .signIn {
                Button("Forgot Password?") {
                    sendPasswordReset()
                }
                .font(RecipeTheme.text(14, weight: .medium, relativeTo: .subheadline))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(!isValidEmail || isAuthenticating)
            }
        }
    }

    private func signedInView(email: String?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header("Signed in", symbol: "checkmark.seal.fill")

                if let email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(RecipeTheme.text(15, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(
                            RecipeTheme.card,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .textSelection(.enabled)
                }

                Button(role: .destructive) {
                    Task {
                        do {
                            try await auth.signOut()
                            dismiss()
                        } catch {
                            localMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticating)

                if let feedback {
                    feedbackView(feedback)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private var passwordRecoveryView: some View {
        ScrollView {
            VStack(spacing: 18) {
                header("Choose a new password", symbol: "key.fill")

                VStack(spacing: 12) {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                        .accountInputStyle()

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .accountInputStyle()

                    Button("Update Password") {
                        guard !isUpdatingPassword else { return }
                        guard newPassword == confirmPassword else {
                            localMessage = String(localized: LocalizedStringResource("The passwords do not match.", locale: RecipeLanguage.active))
                            return
                        }
                        isUpdatingPassword = true
                        dismissAfterAuthentication = true

                        Task {
                            defer { isUpdatingPassword = false }
                            do {
                                try await auth.setRecoveredPassword(newPassword)
                            } catch {
                                dismissAfterAuthentication = false
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

                    Text("Use at least 8 characters.")
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))

                if let feedback {
                    feedbackView(feedback)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(
        _ title: LocalizedStringKey,
        symbol: String,
        subtitle: LocalizedStringKey? = nil
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 60, height: 60)
                .background(RecipeTheme.accent.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(RecipeTheme.title(28))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)

            if let subtitle {
                Text(subtitle)
                    .font(RecipeTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func feedbackView(_ feedback: (message: String, isError: Bool)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedback.isError ? "exclamationmark.circle" : "info.circle")
                .accessibilityHidden(true)
            Text(feedback.message)
                .font(RecipeTheme.text(14, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(feedback.isError ? Color.red : RecipeTheme.accentForeground)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RecipeTheme.accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .accessibilityIdentifier("account.feedback")
    }

    private var feedback: (message: String, isError: Bool)? {
        if let localMessage {
            return (localMessage, true)
        }

        switch auth.state {
        case .needsEmailVerification(let address):
            return (
                String(localized: LocalizedStringResource("Check \(address) to verify your account, then return to RecipePouch.", locale: RecipeLanguage.active)),
                false
            )
        case .passwordResetSent:
            return (String(localized: LocalizedStringResource("Check your inbox for the reset link.", locale: RecipeLanguage.active)), false)
        case .error(let message):
            return (message, true)
        default:
            if let nonblockingMessage {
                return (nonblockingMessage, false)
            }
            return nil
        }
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

    private func performEmailAction() {
        guard canSubmitEmail, !isAuthenticating else { return }
        localMessage = nil
        dismissAfterAuthentication = true
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                switch mode {
                case .signIn:
                    try await auth.signIn(email: address, password: password)
                case .signUp:
                    try await auth.signUp(email: address, password: password)
                }
            } catch {
                dismissAfterAuthentication = false
                localMessage = error.localizedDescription
            }
        }
    }

    private func sendPasswordReset() {
        guard isValidEmail, !isAuthenticating else { return }
        localMessage = nil
        dismissAfterAuthentication = false
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await auth.sendPasswordReset(to: address)
            } catch {
                localMessage = error.localizedDescription
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        // Each nonce is valid for only one Apple authorization attempt.
        let pendingNonce = appleNonce
        appleNonce = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = pendingNonce else {
                localMessage = String(localized: LocalizedStringResource("Apple sign-in did not return a usable identity token.", locale: RecipeLanguage.active))
                return
            }

            let fullName = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return formatted.isEmpty ? nil : formatted
            }

            localMessage = nil
            dismissAfterAuthentication = true
            Task {
                do {
                    try await auth.signInWithApple(
                        identityToken: identityToken,
                        rawNonce: rawNonce,
                        fullName: fullName
                    )
                } catch {
                    dismissAfterAuthentication = false
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

private extension View {
    func accountInputStyle() -> some View {
        self
            .font(RecipeTheme.body())
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
                RecipeTheme.canvas,
                in: RoundedRectangle(cornerRadius: 14)
            )
    }
}
