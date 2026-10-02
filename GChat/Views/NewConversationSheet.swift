import GChatKit
import SwiftUI

/// ⌘N: pick one person for a direct message or several for a group chat.
/// Double-clicking a person starts a direct message right away.
struct NewConversationSheet: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<String> = []
    @State private var isWarningShown = false
    @FocusState private var isSearchFocused: Bool

    private var people: [Profile] {
        guard !query.isEmpty else { return store.contacts }
        return store.contacts.filter {
            ($0.displayName ?? "").localizedCaseInsensitiveContains(query)
                || ($0.email ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    /// In directory order, including people the search currently hides.
    private var selected: [Profile] {
        store.contacts.filter { selection.contains($0.user) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("New Conversation").font(.headline)
                    Spacer()
                    if store.directoryError != nil {
                        Button {
                            withAnimation { isWarningShown.toggle() }
                        } label: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Not everyone in your organization is listed")
                        .accessibilityLabel("Directory warning")
                    }
                }
                if isWarningShown, let error = store.directoryError {
                    warningPanel(error)
                }
                TextField("Search people", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }
            .padding(16)

            Divider()

            List(people, id: \.user, selection: $selection) { person in
                PersonRow(person: person)
            }
            .environment(\.defaultMinListRowHeight, 22)
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { users in
                // Double-click or Return on a row.
                start(store.contacts.filter { users.contains($0.user) })
            }
            .overlay {
                if store.contacts.isEmpty {
                    ContentUnavailableView {
                        Label("No People Found", systemImage: "person.2.slash")
                    } description: {
                        Text(store.directoryError == nil
                            ? "Google returned an empty directory for your organization."
                            : "The directory is unavailable and there are no existing conversations to take people from.")
                    }
                } else if people.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            Divider()

            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Chat") { start(selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420, height: 480)
        .onAppear { isSearchFocused = true }
    }

    /// Explains why the list is incomplete. Closed with its own button or by
    /// clicking the warning icon again.
    private func warningPanel(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.isDirectoryBlocked
                    ? """
                      You can only start chats with people you've already chatted with. To list \
                      everyone, ask your Google Workspace admin to set External Directory sharing \
                      to "Organization data".
                      """
                    : "The organization's directory could not be loaded, so only people from your existing conversations are listed.")
                Text(error)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { isWarningShown = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.yellow.opacity(0.4)) }
    }

    private var summary: String {
        let names = selected.map { $0.displayName ?? $0.email ?? "Unknown" }
        switch names.count {
        case 0: return "Select one or more people"
        case 1: return "Direct message with \(names[0])"
        default: return "Group chat with \(names.formatted(.list(type: .and)))"
        }
    }

    private func start(_ people: [Profile]) {
        guard !people.isEmpty else { return }
        dismiss()
        Task { await store.startConversation(with: people) }
    }
}

private struct PersonRow: View {
    let person: Profile

    var body: some View {
        let name = person.displayName ?? person.email ?? "Unknown"
        HStack(spacing: 8) {
            AvatarView(url: person.photoURL, name: name, size: 18)
            Text(name).lineLimit(1)
            if let email = person.email, person.displayName != nil {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }
}
