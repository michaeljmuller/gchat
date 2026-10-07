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
    @AppStorage(AppSettings.hideDeletedKey) private var hideDeletedUsers = true
    @AppStorage(AppSettings.hideUnnamedAppsKey) private var hideUnnamedApps = true
    @AppStorage(AppSettings.hideAppsKey) private var hideApps = false
    @AppStorage(AppSettings.showDatesKey) private var showDates = true
    @AppStorage(AppSettings.sidebarSortKey) private var sidebarSort = SidebarSort.recent
    @AppStorage("sidebarTab") private var selectedTab = "Direct Messages"

    private struct SidebarSection: Identifiable {
        let title: String
        let shortTitle: String
        let icon: String
        let spaces: [Space]

        var id: String { title }
    }

    private var sections: [SidebarSection] {
        [
            SidebarSection(
                title: "Direct Messages", shortTitle: "Direct", icon: "person",
                spaces: filtered(store.directMessages)),
            SidebarSection(
                title: "Group Chats", shortTitle: "Groups", icon: "person.2",
                spaces: filtered(store.groupChats)),
            SidebarSection(
                title: "Spaces", shortTitle: "Spaces", icon: "number",
                spaces: filtered(store.namedSpaces)),
            SidebarSection(
                title: "Meetings", shortTitle: "Meetings", icon: "video",
                spaces: filtered(store.meetingChats)),
        ].filter { !$0.spaces.isEmpty }
    }

    /// The section shown when not searching. Falls back to the first one that has conversations.
    private func current(_ sections: [SidebarSection]) -> SidebarSection? {
        sections.first { $0.title == selectedTab } ?? sections.first
    }

    var body: some View {
        let sections = sections
        // A search looks through every section; otherwise one tab is shown at a time.
        let visible = search.isEmpty ? Array([current(sections)].compactMap { $0 }) : sections
        List(selection: $store.selection) {
            ForEach(visible) { section in
                if search.isEmpty {
                    rows(section)
                } else {
                    Section(section.title) { rows(section) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if search.isEmpty, sections.count > 1 {
                tabBar(sections)
            }
        }
        .onChange(of: store.selection) {
            // Follow a conversation opened from elsewhere, such as ⌘K or a notification.
            if let tab = sections.first(where: { $0.spaces.contains { $0.name == store.selection } }) {
                selectedTab = tab.title
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = store.connectionError ?? relayDownMessage {
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

    /// Shown while the relay is out of reach and the app polls instead.
    private var relayDownMessage: String? {
        guard store.isPushDown else { return nil }
        return "New message notification server is down; polling for new messages every "
            + "\(store.listPollSeconds) seconds."
    }

    /// Applies the search field and the sidebar settings. The store's order is most recent first.
    private func filtered(_ spaces: [Space]) -> [Space] {
        var spaces = spaces
        if hideDeletedUsers {
            spaces.removeAll { store.isWithDeletedUser($0) }
        }
        if hideApps {
            spaces.removeAll { store.isWithApp($0) }
        } else if hideUnnamedApps {
            spaces.removeAll { store.isWithUnnamedApp($0) }
        }
        if !search.isEmpty {
            spaces = spaces.filter { store.title(for: $0).localizedCaseInsensitiveContains(search) }
        }
        if sidebarSort == .alphabetical {
            spaces.sort {
                store.title(for: $0).localizedStandardCompare(store.title(for: $1)) == .orderedAscending
            }
        }
        return spaces
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(section.spaces) { space in
            SpaceRow(store: store, space: space, showsDate: showDates)
                .tag(space.name)
        }
    }

    /// One tab per section. A dot marks a tab that has unread conversations.
    private func tabBar(_ sections: [SidebarSection]) -> some View {
        ViewThatFits(in: .horizontal) {
            tabButtons(sections, showsText: true)
            tabButtons(sections, showsText: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tabButtons(_ sections: [SidebarSection], showsText: Bool) -> some View {
        let selected = current(sections)?.id
        return HStack(spacing: 2) {
            ForEach(sections) { section in
                let isSelected = section.id == selected
                Button {
                    selectedTab = section.title
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: section.icon)
                        if showsText { Text(section.shortTitle).fixedSize() }
                        if section.spaces.contains(where: { store.isUnread($0) }) {
                            Circle().fill(.tint).frame(width: 6, height: 6)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .help(section.title)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct SpaceRow: View {
    let store: ChatStore
    let space: Space
    var showsDate = false

    var body: some View {
        let title = store.title(for: space)
        let isUnread = store.isUnread(space)
        HStack(spacing: 8) {
            icon(title: title)
            Text(title)
                .fontWeight(isUnread ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsDate, let date = space.lastActiveTime {
                Text(Self.shortDate(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
                    .help(date.formatted(date: .long, time: .shortened))
            }
            if isUnread {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
    }

    /// Time for today, weekday within the last week, otherwise the date.
    static func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(date: .numeric, time: .omitted)
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
            Image(systemName: space.isMeetingChat ? "video" : "number")
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
