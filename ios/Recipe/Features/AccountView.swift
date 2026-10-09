// Developer: gengyun
// Purpose: Presents Recipe Pals account sign-in, recovery, and session controls in a compact sheet.

import AuthenticationServices
import Foundation
import RecipeCore
import SwiftUI

@MainActor
struct AccountView: View {
    let onExpand: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var providerButtonHeight: CGFloat = 50
    @State private var auth = RecipeAuthService.shared
    @State private var isEmailExpanded = false
    @State private var usesPasswordSignIn = false
    @State private var email = ""
    @State private var emailCode = ""
    @State private var codeEmail: String?
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
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
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
            VStack(spacing: RecipeSpacing.large) {
                VStack(spacing: RecipeSpacing.medium) {
                    Image("RecipeBrand")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)

                    Text(verbatim: "Recipe Pals")
                        .font(RecipeTheme.heading(.title))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("account.brand")
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: RecipeSpacing.small) {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = RecipeAuthService.makeAppleNonce()
                        appleNonce = nonce.raw
                        request.nonce = nonce.hashed
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    // Apple's native artwork and authorization stay intact; only the geometry changes.
                    .signInWithAppleButtonStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: providerButtonHeight)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(accountButtonBorderColor, lineWidth: 1)
                    }
                    .disabled(isAuthenticating)
                    .accessibilityIdentifier("account.apple")

                    googleSignInButton

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
                            .padding(RecipeSpacing.medium)
                            .background(
                                RecipeTheme.card,
                                in: RoundedRectangle(cornerRadius: 22)
                            )
                    } else {
                        Button {
                            localMessage = nil
                            isEmailExpanded = true
                            onExpand()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20, weight: .regular))
                                    .accessibilityHidden(true)

                                Text("Continue with email")
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, RecipeSpacing.medium)
                            .padding(.vertical, RecipeSpacing.xSmall)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isAuthenticating)
                        .accessibilityIdentifier("account.email")
                    }
                }

                if let feedback {
                    feedbackView(feedback)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.top, RecipeSpacing.large)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("account.close")
    }

    /// Reuses Google's four-color G while sharing the other sign-in buttons' geometry.
    private var googleSignInButton: some View {
        return Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                Image("GoogleSignInG")
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)

                Text(LocalizedStringKey("Sign in with Google"))
                    .font(.system(.body, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RecipeSpacing.medium)
            .padding(.vertical, RecipeSpacing.xSmall)
            .frame(maxWidth: .infinity, minHeight: providerButtonHeight)
            .foregroundStyle(Color(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255))
            .background(.white, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(accountButtonBorderColor, lineWidth: 1)
            }
            .opacity(isAuthenticating ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
        .accessibilityIdentifier("account.google")
    }

    private var accountButtonBorderColor: Color {
        Color(red: 116.0 / 255, green: 119.0 / 255, blue: 117.0 / 255)
    }

    private var emailForm: some View {
        VStack(spacing: RecipeSpacing.small) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .accountInputStyle()

            if let codeEmail {
                TextField("6-digit code", text: $emailCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .accountInputStyle()
                    .accessibilityIdentifier("account.emailCode")

                Button {
                    verifyEmailCode(for: codeEmail)
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        }
                        Text("Verify Code")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    emailCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isAuthenticating
                )
                .accessibilityIdentifier("account.submit")

                HStack {
                    Button("Resend Code") {
                        sendEmailCode(to: codeEmail)
                    }
                    .disabled(isAuthenticating)

                    Spacer()

                    Button("Change Email") {
                        emailCode = ""
                        self.codeEmail = nil
                        localMessage = nil
                    }
                    .disabled(isAuthenticating)
                }
            } else if usesPasswordSignIn {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit {
                        if canSubmitPassword && !isAuthenticating {
                            signInWithPassword()
                        }
                    }
                    .accountInputStyle()

                Button("Forgot Password?") {
                    sendPasswordReset()
                }
                .font(RecipeTheme.text(14, weight: .medium, relativeTo: .subheadline))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(!isValidEmail || isAuthenticating)

                Button {
                    signInWithPassword()
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        }
                        Text("Sign In")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmitPassword || isAuthenticating)
                .accessibilityIdentifier("account.submit")

                Button("Use an email code instead") {
                    usesPasswordSignIn = false
                    password = ""
                    localMessage = nil
                }
                .disabled(isAuthenticating)
                .accessibilityIdentifier("account.passwordAlternative")
            } else {
                Button {
                    sendEmailCode(to: email)
                } label: {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        }
                        Text("Continue with Email")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValidEmail || isAuthenticating)
                .accessibilityIdentifier("account.submit")

                Button("Use a password instead") {
                    usesPasswordSignIn = true
                    localMessage = nil
                    onExpand()
                }
                .disabled(isAuthenticating)
                .accessibilityIdentifier("account.passwordAlternative")
            }
        }
    }

    private func signedInView(email: String?) -> some View {
        ScrollView {
            VStack(spacing: RecipeSpacing.large) {
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
            VStack(spacing: RecipeSpacing.medium) {
                header("Choose a new password", symbol: "key.fill")

                VStack(spacing: RecipeSpacing.small) {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                        .accountInputStyle()

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .accountInputStyle()

                    Button("Update Password") {
                        guard !isUpdatingPassword else { return }
                        guard newPassword == confirmPassword else {
                            localMessage = String(
                                localized: LocalizedStringResource(
                                    "The passwords do not match.", locale: RecipeLanguage.active))
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
        subtitle: LocalizedStringKey? = nil,
        level: RecipeHeadingLevel = .title
    ) -> some View {
        VStack(spacing: RecipeSpacing.xSmall) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 52, height: 52)
                .background(RecipeTheme.accent.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(RecipeTheme.heading(level))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(RecipeTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
        case .emailCodeSent(let address):
            return (
                String(
                    localized: LocalizedStringResource(
                        "Enter the code sent to \(address).",
                        locale: RecipeLanguage.active
                    )
                ),
                false
            )
        case .needsEmailVerification(let address):
            return (
                String(
                    localized: LocalizedStringResource(
                        "Check \(address) to verify your account, then return to RecipePouch.",
                        locale: RecipeLanguage.active)),
                false
            )
        case .passwordResetSent:
            return (
                String(
                    localized: LocalizedStringResource(
                        "Check your inbox for the reset link.", locale: RecipeLanguage.active)),
                false
            )
        case .error(let message):
            return (message, true)
        default:
            if let nonblockingMessage {
                return (nonblockingMessage, false)
            }
            return nil
        }
    }

    private var canSubmitPassword: Bool { isValidEmail && !password.isEmpty }

    private var isValidEmail: Bool { Self.isValidEmail(email) }

    private static func isValidEmail(_ rawAddress: String) -> Bool {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var isAuthenticating: Bool {
        if case .authenticating = auth.state { return true }
        return false
    }

    private func sendEmailCode(to rawAddress: String) {
        guard Self.isValidEmail(rawAddress), !isAuthenticating else { return }
        localMessage = nil
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await auth.sendEmailCode(to: address)
                codeEmail = address
                emailCode = ""
            } catch {
                localMessage = error.localizedDescription
            }
        }
    }

    private func verifyEmailCode(for address: String) {
        guard !emailCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !isAuthenticating
        else {
            return
        }
        localMessage = nil
        dismissAfterAuthentication = true
        let code = emailCode.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await auth.verifyEmailCode(email: address, code: code)
            } catch {
                dismissAfterAuthentication = false
                localMessage = error.localizedDescription
            }
        }
    }

    private func signInWithPassword() {
        guard canSubmitPassword, !isAuthenticating else { return }
        localMessage = nil
        dismissAfterAuthentication = true
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await auth.signIn(email: address, password: password)
            } catch {
                dismissAfterAuthentication = false
                localMessage = error.localizedDescription
            }
        }
    }

    private func signInWithGoogle() {
        guard !isAuthenticating else { return }
        localMessage = nil
        dismissAfterAuthentication = true

        Task {
            do {
                let didSignIn = try await auth.signInWithGoogle()
                if !didSignIn {
                    // Canceling Google's system sheet is not a failed login.
                    dismissAfterAuthentication = false
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
                let rawNonce = pendingNonce
            else {
                localMessage = String(
                    localized: LocalizedStringResource(
                        "Apple sign-in did not return a usable identity token.",
                        locale: RecipeLanguage.active))
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
                authorizationError.code == .canceled
            {
                return
            }
            localMessage = error.localizedDescription
        }
    }
}

extension View {
    fileprivate func accountInputStyle() -> some View {
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
