import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.notificationsKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.previewsKey) private var notificationPreviews = true

    var body: some View {
        Form {
            Section("Account") {
                if let me = model.store?.me {
                    LabeledContent("Signed in as") {
                        VStack(alignment: .trailing) {
                            Text(me.displayName ?? "Unknown")
                            if let email = me.email {
                                Text(email).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    LabeledContent("Signed in as", value: model.store == nil ? "Not signed in" : "Loading…")
                }
                LabeledContent("OAuth client ID") {
                    Text(model.clientID.isEmpty ? "Not set" : model.clientID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Sign Out") { model.signOut() }
                    .disabled(model.store == nil)
            }

            Section("Notifications") {
                Toggle("Notify me about new messages", isOn: $notificationsEnabled)
                Toggle("Show message text in notifications", isOn: $notificationPreviews)
                    .disabled(!notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
