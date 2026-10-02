import GChatKit
import SwiftUI

/// ⌘N: pick one person for a direct message or several for a group chat.
/// Double-clicking a person starts a direct message right away.
struct NewConversationSheet: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Set<String> = []
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
                Text("New Conversation").font(.headline)
                TextField("Search people", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
            }
            .padding(16)

            Divider()

            List(people, id: \.user, selection: $selection) { person in
                PersonRow(person: person)
            }
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

            if let error = store.directoryError {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Showing people from your existing conversations. The organization's directory could not be loaded:")
                    Text(error).textSelection(.enabled)
                    Button("Try Again") { Task { await store.reloadDirectory() } }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
        HStack(spacing: 10) {
            AvatarView(url: person.photoURL, name: name, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if let email = person.email, person.displayName != nil {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
