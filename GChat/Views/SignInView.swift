import GChatKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Sign in to Google Chat")
                .font(.title2.weight(.semibold))
            Text("Paste the OAuth client ID from your Google Cloud project. The README explains how to create one.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("1234-abcd.apps.googleusercontent.com", text: $model.clientID)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit(signIn)

            Button(action: signIn) {
                Text(model.isSigningIn ? "Waiting for Google…" : "Sign In with Google")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isSigningIn || model.clientID.trimmingCharacters(in: .whitespaces).isEmpty)

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
    }

    private func signIn() {
        Task { await model.signIn() }
    }
}
