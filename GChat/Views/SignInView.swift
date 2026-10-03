import GChatKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    /// Whether the client ID field is shown. Hidden when this copy of the app
    /// has an organization's client ID built in and it is the one in use.
    @State private var showsClientID = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.weight(.semibold))

            if showsClientID {
                Text("Paste the OAuth client ID from your organization's Google Cloud project. github.com/michaeljmuller/gchat explains how to create one.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("1234-abcd.apps.googleusercontent.com", text: $model.clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(signIn)
            }

            Button(action: signIn) {
                Text(model.isSigningIn ? "Waiting for Google…" : "Sign In with Google")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isSigningIn || model.clientID.trimmingCharacters(in: .whitespaces).isEmpty)

            if let builtIn = model.builtInClientID {
                if showsClientID {
                    Button("Use \(model.builtInOrganization ?? "the built-in organization")") {
                        model.clientID = builtIn
                        showsClientID = false
                    }
                    .buttonStyle(.link)
                } else {
                    Button("Use a different organization…") { showsClientID = true }
                        .buttonStyle(.link)
                }
            }

            Text("""
                GChat keeps you signed in by saving the sign-in token from Google in your Keychain, \
                as "\(KeychainTokenStore.label)". macOS may ask you to allow GChat to use that item. \
                Your Google password is never seen or stored by GChat.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.signInError {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 400)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            showsClientID = model.builtInClientID == nil || model.clientID != model.builtInClientID
        }
    }

    private var title: String {
        if !showsClientID, let organization = model.builtInOrganization {
            return "Sign in to Google Chat at \(organization)"
        }
        return "Sign in to Google Chat"
    }

    private func signIn() {
        Task { await model.signIn() }
    }
}
