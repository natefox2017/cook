import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @State private var mode = 0
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("Account action", selection: $mode) {
                    Text("Sign In").tag(0)
                    Text("Create Account").tag(1)
                }.pickerStyle(.segmented)
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                SecureField("Password", text: $password).textContentType(mode == 0 ? .password : .newPassword)
                Button(mode == 0 ? "Sign In" : "Create Account") {
                    message = "Supabase project configuration is required before this account action can be sent."
                }.buttonStyle(PrimaryButtonStyle())
                Button("Forgot Password?") {
                    message = "Password reset will be sent through Supabase Auth after the project is restored."
                }
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { _ in
                    message = "Sign in with Apple is wired to the native credential UI; Supabase Apple provider configuration is required to exchange the token."
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .allowsHitTesting(false)
                .opacity(0.5)
            } footer: {
                Text("Cook never treats your App Store subscription account as your Cook recipe account.")
            }
            Section("Sync") {
                LabeledContent("Status", value: "Not connected")
                Text("Your current library stays on this iPhone until a Cook account is connected. It will not be overwritten silently.")
            }
        }
        .navigationTitle("Cook Account")
        .alert("Account", isPresented: Binding(get:{message != nil},set:{if !$0{message=nil}})) {
            Button("OK",role:.cancel){message=nil}
        } message: { Text(message ?? "") }
    }
}
