import GChatKit
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ChatStore

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if let name = store.selection, let space = store.space(named: name) {
                ConversationView(store: store, space: space)
                    .id(space.name)
            } else {
                placeholder
            }
        }
        .sheet(isPresented: $model.isQuickSwitcherShown) {
            QuickSwitcher(store: store)
        }
        .sheet(isPresented: $model.isNewConversationShown) {
            NewConversationSheet(store: store)
        }
        .alert(
            "GChat",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } })
        ) {
            Button("OK") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch store.phase {
        case .loading:
            ProgressView("Loading conversations…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load conversations", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        case .ready:
            ContentUnavailableView(
                "No Conversation Selected", systemImage: "bubble.left.and.bubble.right",
                description: Text("Choose a conversation from the sidebar, press ⌘K to jump to one, or ⌘N to start a new one."))
        }
    }
}

struct SidebarView: View {
    @Bindable var store: ChatStore
    @State private var search = ""

    var body: some View {
        List(selection: $store.selection) {
            section("Direct Messages", filtered(store.directMessages))
            section("Group Chats", filtered(store.groupChats))
            section("Spaces", filtered(store.namedSpaces))
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = store.connectionError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.bar)
                    .help(error)
            }
        }
    }

    private func filtered(_ spaces: [Space]) -> [Space] {
        guard !search.isEmpty else { return spaces }
        return spaces.filter { store.title(for: $0).localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder
    private func section(_ title: String, _ spaces: [Space]) -> some View {
        if !spaces.isEmpty {
            Section(title) {
                ForEach(spaces) { space in
                    SpaceRow(store: store, space: space)
                        .tag(space.name)
                }
            }
        }
    }
}

struct SpaceRow: View {
    let store: ChatStore
    let space: Space

    var body: some View {
        let title = store.title(for: space)
        let isUnread = store.isUnread(space)
        HStack(spacing: 8) {
            icon(title: title)
            Text(title)
                .fontWeight(isUnread ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isUnread {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func icon(title: String) -> some View {
        switch space.kind {
        case .directMessage:
            AvatarView(url: store.partner(of: space)?.photoURL, name: title, size: 22)
        case .groupChat:
            Image(systemName: "person.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
        default:
            Image(systemName: "number")
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }
}

struct AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    private static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown]

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            initials
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        // A stable colour per name; String.hashValue changes on every launch.
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return Circle()
            .fill(Self.colors[seed % Self.colors.count].gradient)
            .overlay {
                Text(letters.isEmpty ? "?" : letters.uppercased())
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
