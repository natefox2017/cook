// Developer: gengyun
// Purpose: Presents one native authentication flow with email, Apple, and Google sign-in.

import AuthenticationServices
import Foundation
import SwiftUI

@MainActor
struct AccountView: View {
    private enum Step: Equatable {
        case email
        case signInMethod
        case emailCode
        case password

        var title: LocalizedStringKey {
            switch self {
            case .email, .signInMethod:
                return "Sign In"
            case .emailCode:
                return "Enter verification code"
            case .password:
                return "Sign in with password"
            }
        }
    }

    private enum Field: Hashable {
        case email
        case code
        case password
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var auth = RecipeAuthService.shared
    @State private var step: Step = .email
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isUpdatingPassword = false
    @State private var appleNonce: String?
    @State private var localMessage: LocalizedStringKey?

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
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
        .font(.system(size: 17))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("RecipePouch")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .onChange(of: auth.state) { _, state in
            switch state {
            case .signedIn:
                clearCredentials()
                focusedField = nil
            case .signedOut:
                clearCredentials()
                step = .email
            case .error(let message):
                localMessage = friendlyAuthMessage(message)
            default:
                break
            }
        }
        .onChange(of: step) { _, step in
            focusedField = step == .emailCode ? .code : nil
            if step != .password {
                password = ""
            }
        }
        .onChange(of: auth.nonblockingNotice) { _, notice in
            if notice != nil {
                localMessage = "Signed in. Your profile could not be updated."
                auth.dismissNotice()
            }
        }
        .alert(
            "Sign In",
            isPresented: Binding(
                get: {
                    localMessage != nil
                },
                set: { presented in
                    if !presented {
                        localMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                localMessage = nil
            }
        } message: {
            Text(localMessage ?? "")
        }
    }

    private var signedOutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(step.title)
                    .font(.system(size: 32, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 16) {
                    if step != .email {
                        emailSummary
                    }
                    emailControls
                }

                providerButtons
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var emailSummary: some View {
        HStack(spacing: 12) {
            Text(normalizedEmail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button("Change email") {
                step = .email
            }
            .font(.system(size: 14, weight: .medium))
            .frame(minHeight: 44)
            .disabled(isAuthenticating)
        }
    }

    @ViewBuilder
    private var emailControls: some View {
        switch step {
        case .email:
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .modifier(AccountInputStyle())
                .accessibilityIdentifier("account.email")
                .onSubmit {
                    advanceFromEmail()
                }

            Button("Next") {
                advanceFromEmail()
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(!isValidEmail || isAuthenticating)
            .accessibilityIdentifier("account.next")

        case .signInMethod:
            Button("Sign In") {
                sendEmailCode()
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(!isValidEmail || isAuthenticating)
            .accessibilityIdentifier("account.sendCode")

            Button("Use Password Instead") {
                step = .password
            }
            .frame(minHeight: 44)
            .disabled(isAuthenticating)

        case .emailCode:
            TextField("Email Verification Code", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .modifier(AccountInputStyle())
                .accessibilityIdentifier("account.verificationCode")

            Button("Sign In") {
                verifyEmailCode()
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(
                verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isAuthenticating
            )
            .accessibilityIdentifier("account.submit")

            HStack {
                Button("Resend Code") {
                    sendEmailCode()
                }
                Spacer(minLength: 12)
                Button("Use Password Instead") {
                    step = .password
                }
            }
            .font(.system(size: 14, weight: .medium))
            .frame(minHeight: 44)
            .disabled(isAuthenticating)

        case .password:
            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .modifier(AccountInputStyle())
                .onSubmit {
                    if isValidEmail && !password.isEmpty && !isAuthenticating {
                        performPasswordSignIn()
                    }
                }

            Button("Sign In") {
                performPasswordSignIn()
            }
            .buttonStyle(AccountPrimaryButtonStyle())
            .disabled(!isValidEmail || password.isEmpty || isAuthenticating)
            .accessibilityIdentifier("account.submit")

            HStack {
                Button("Use Email Code") {
                    step = .signInMethod
                }
                Spacer(minLength: 12)
                Button("Forgot Password?") {
                    sendPasswordReset()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .frame(minHeight: 44)
            .disabled(isAuthenticating)
        }
    }

    private var providerButtons: some View {
        VStack(spacing: 12) {
            Button {
                startGoogleSignIn()
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleSignInLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text("Sign in with Google")
                        .font(.custom("GoogleSans-Regular_Medium", size: 17))
                }
                .foregroundStyle(Color(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color(red: 116.0 / 255, green: 119.0 / 255, blue: 117.0 / 255),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isAuthenticating)
            .accessibilityIdentifier("account.google")

            SignInWithAppleButton(.signIn) { request in
                let nonce = RecipeAuthService.makeAppleNonce()
                appleNonce = nonce.raw
                request.nonce = nonce.hashed
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isAuthenticating)
            .accessibilityIdentifier("account.apple")
        }
    }

    private func signedInView(email: String?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Signed in", systemImage: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(RecipeTheme.accentForeground)
            if let email, !email.isEmpty {
                Text(email)
                    .textSelection(.enabled)
            }
            Button("Sign Out", role: .destructive) {
                Task {
                    do {
                        try await auth.signOut()
                    } catch {
                        localMessage = friendlyAuthMessage(error.localizedDescription)
                    }
                }
            }
            .frame(minHeight: 44)
            .disabled(isAuthenticating)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(28)
    }

    private var passwordRecoveryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a new password")
                    .font(.system(size: 28, weight: .bold))
                VStack(spacing: 16) {
                    SecureField("New password (8+ characters)", text: $newPassword)
                        .textContentType(.newPassword)
                        .modifier(AccountInputStyle())
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .modifier(AccountInputStyle())
                    Button("Update Password") {
                        updateRecoveredPassword()
                    }
                    .buttonStyle(AccountPrimaryButtonStyle())
                    .disabled(
                        newPassword.count < 8
                            || confirmPassword.isEmpty
                            || isAuthenticating
                            || isUpdatingPassword
                    )
                }
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidEmail: Bool {
        normalizedEmail.contains("@") && normalizedEmail.contains(".")
    }

    private var isAuthenticating: Bool {
        if case .authenticating = auth.state {
            return true
        }
        return false
    }

    private func advanceFromEmail() {
        guard isValidEmail, !isAuthenticating else {
            return
        }
        focusedField = nil
        step = .signInMethod
    }

    private func clearCredentials() {
        password = ""
        newPassword = ""
        confirmPassword = ""
        verificationCode = ""
    }

    private func friendlyAuthMessage(_ message: String) -> LocalizedStringKey {
        // Server diagnostics are not product copy. Translate known failures and
        // keep unfamiliar backend messages out of the login screen.
        let normalized = message.lowercased()
        if normalized.contains("rate") && normalized.contains("email") {
            return "Too many emails. Please try again later."
        }
        if normalized.contains("invalid login credentials") {
            return "The email or password is incorrect."
        }
        if normalized.contains("otp") || normalized.contains("expired") {
            return "The code is invalid or expired. Request a new code."
        }
        if normalized.contains("provider") && normalized.contains("not enabled") {
            return "This sign-in method is unavailable. Use email instead."
        }
        return "Unable to sign in. Please try again."
    }

    private func sendEmailCode() {
        let address = normalizedEmail
        Task {
            do {
                try await auth.sendEmailCode(to: address)
                verificationCode = ""
                step = .emailCode
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func verifyEmailCode() {
        let address = normalizedEmail
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await auth.verifyEmailCode(code, for: address)
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func performPasswordSignIn() {
        let address = normalizedEmail
        Task {
            do {
                try await auth.signIn(email: address, password: password)
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func startGoogleSignIn() {
        Task {
            do {
                try await auth.signInWithGoogle()
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func sendPasswordReset() {
        let address = normalizedEmail
        Task {
            do {
                try await auth.sendPasswordReset(to: address)
                localMessage = "If this email is registered, a reset link will arrive in its inbox."
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func updateRecoveredPassword() {
        guard !isUpdatingPassword else {
            return
        }
        guard newPassword == confirmPassword else {
            localMessage = "The passwords do not match."
            return
        }
        isUpdatingPassword = true
        Task {
            defer {
                isUpdatingPassword = false
            }
            do {
                try await auth.setRecoveredPassword(newPassword)
                newPassword = ""
                confirmPassword = ""
            } catch {
                localMessage = friendlyAuthMessage(error.localizedDescription)
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        // The nonce belongs only to this authorization result, including cancellation.
        let pendingNonce = appleNonce
        appleNonce = nil

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let rawNonce = pendingNonce
            else {
                localMessage = "Unable to sign in. Please try again."
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
                    localMessage = friendlyAuthMessage(error.localizedDescription)
                }
            }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
                authorizationError.code == .canceled
            {
                return
            }
            localMessage = friendlyAuthMessage(error.localizedDescription)
        }
    }
}

private struct AccountInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
    }
}

private struct AccountPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(RecipeTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
