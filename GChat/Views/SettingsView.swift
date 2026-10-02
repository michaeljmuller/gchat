import GChatKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.notificationsKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.previewsKey) private var notificationPreviews = true
    @AppStorage(AppSettings.hideDeletedKey) private var hideDeletedUsers = true
    @AppStorage(AppSettings.showDatesKey) private var showDates = true
    @AppStorage(AppSettings.sidebarSortKey) private var sidebarSort = SidebarSort.recent

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text("Account")
            } footer: {
                Text("""
                    Your sign-in is saved in your Keychain as "\(KeychainTokenStore.label)". It holds the \
                    token Google issued to GChat, not your password. Sign Out deletes it.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Sidebar") {
                Picker("Sort conversations", selection: $sidebarSort) {
                    ForEach(SidebarSort.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show date of last activity", isOn: $showDates)
                Toggle("Hide direct messages with deleted users", isOn: $hideDeletedUsers)
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
