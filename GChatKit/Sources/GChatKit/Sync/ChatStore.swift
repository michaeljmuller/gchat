import Foundation
import Observation

public struct PendingMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    /// Set when sending failed.
    public var error: String?
}

public struct Transcript: Sendable {
    /// Oldest first.
    public var messages: [Message] = []
    public var pending: [PendingMessage] = []
    public var olderPageToken: String?
    public var isLoaded = false
    public var isLoadingOlder = false
    public var loadError: String?

    public init() {}
}

public enum UnreadRule {
    /// A conversation is unread when its last message is newer than the read marker.
    public static func isUnread(lastActive: Date?, lastRead: Date?) -> Bool {
        guard let lastActive, let lastRead else { return false }
        return lastActive.timeIntervalSince(lastRead) > 0.001
    }
}

/// The app's state: conversations, transcripts, read markers, and the polling
/// that keeps them current.
@MainActor
@Observable
public final class ChatStore {
    public enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    /// Most recently active first.
    public private(set) var spaces: [Space] = []
    public private(set) var me: Profile?
    public private(set) var connectionError: String?
    /// The organization's directory without the signed-in user, sorted by name.
    public private(set) var directory: [Profile] = []
    /// A failure the user should see once, such as not being able to start a conversation.
    public var alertMessage: String?
    public var selection: String? {
        didSet {
            if selection != oldValue { defaults.set(selection, forKey: Keys.selection) }
        }
    }
    public var isAppActive = true
    public var isOnline = true

    /// Called with new messages from other people in a conversation that is not in front.
    @ObservationIgnored public var onIncoming: ((Space, [Message]) -> Void)?
    @ObservationIgnored public var onUnreadCountChanged: ((Int) -> Void)?
    @ObservationIgnored public var onAuthFailure: (() -> Void)?

    private var transcripts: [String: Transcript] = [:]
    private var readTimes: [String: Date] = [:]
    private var titles: [String: String]
    /// Direct message space -> the other person's user resource name.
    private var partners: [String: String]
    /// Group chat space -> the other members' user resource names.
    @ObservationIgnored private var groupMembers: [String: Set<String>]
    private var profiles: [String: Profile]
    /// Names taken from Chat responses, used until the People API answers.
    private var seedNames: [String: String] = [:]

    /// Direct messages created here that have no messages yet. The server leaves
    /// those out of the conversation list.
    @ObservationIgnored private var localSpaces: [String: Space] = [:]
    @ObservationIgnored private var profileRequests: Set<String> = []
    @ObservationIgnored private var titleAttempts: Set<String> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var reportedUnread = -1
    @ObservationIgnored private var refreshCount = 0

    private let chat: any ChatService
    private let people: any ProfileService
    private let defaults: UserDefaults

    private enum Keys {
        static let selection = "selectedSpace"
        static let titles = "spaceTitles"
        static let partners = "spacePartners"
        static let groupMembers = "groupMembers"
        static let profiles = "profiles"
    }

    private static let activeInterval = Duration.seconds(3)
    private static let inactiveInterval = Duration.seconds(10)
    private static let pageSize = 50

    public init(chat: any ChatService, people: any ProfileService, defaults: UserDefaults = .standard) {
        self.chat = chat
        self.people = people
        self.defaults = defaults
        self.titles = defaults.dictionary(forKey: Keys.titles) as? [String: String] ?? [:]
        self.partners = defaults.dictionary(forKey: Keys.partners) as? [String: String] ?? [:]
        self.groupMembers = (defaults.dictionary(forKey: Keys.groupMembers) as? [String: [String]] ?? [:])
            .mapValues(Set.init)
        self.profiles = defaults.data(forKey: Keys.profiles)
            .flatMap { try? JSONDecoder().decode([String: Profile].self, from: $0) } ?? [:]
        self.selection = defaults.string(forKey: Keys.selection)
    }

    // MARK: - Reading state

    public func space(named name: String) -> Space? {
        spaces.first { $0.name == name }
    }

    public var directMessages: [Space] {
        spaces.filter { $0.kind == .directMessage }
    }

    /// Unnamed conversations between three or more people.
    public var groupChats: [Space] {
        spaces.filter { $0.kind == .groupChat }
    }

    public var namedSpaces: [Space] {
        spaces.filter { $0.kind != .directMessage && $0.kind != .groupChat }
    }

    public func title(for space: Space) -> String {
        if let name = space.displayName, !name.isEmpty { return name }
        if let title = titles[space.name] { return title }
        if space.singleUserBotDm == true { return "App" }
        switch space.kind {
        case .directMessage: return "Direct Message"
        case .groupChat: return "Group Chat"
        default: return "Space"
        }
    }

    /// The other person in a direct message, when known.
    public func partner(of space: Space) -> Profile? {
        partners[space.name].flatMap { profiles[$0] }
    }

    public func transcript(for name: String) -> Transcript {
        transcripts[name] ?? Transcript()
    }

    public func isUnread(_ space: Space) -> Bool {
        UnreadRule.isUnread(lastActive: space.lastActiveTime, lastRead: readTimes[space.name])
    }

    public var unreadCount: Int {
        spaces.count { isUnread($0) }
    }

    public func profile(for user: String) -> Profile? {
        profiles[user]
    }

    public func name(for user: User?) -> String {
        guard let user else { return "Unknown" }
        if let name = profiles[user.name]?.displayName ?? seedNames[user.name] ?? user.displayName,
           !name.isEmpty {
            return name
        }
        return user.isBot ? "App" : "Unknown"
    }

    public func isMine(_ message: Message) -> Bool {
        message.sender?.name != nil && message.sender?.name == me?.user
    }

    // MARK: - Lifecycle

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { await self.run() }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func run() async {
        await refreshSpaces()
        var tick = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: isAppActive ? Self.activeInterval : Self.inactiveInterval)
            if Task.isCancelled { break }
            guard isOnline else { continue }
            tick += 1
            if phase != .ready {
                await refreshSpaces()
                continue
            }
            await pollSelection()
            if tick % (isAppActive ? 5 : 3) == 0 {
                await refreshSpaces()
            }
        }
    }

    /// Reloads the conversation list and whatever is open. Used by the Refresh command.
    public func refresh() async {
        await refreshSpaces()
        await loadDirectory()
        if let selection { await open(selection) }
    }

    // MARK: - Conversation list

    func refreshSpaces() async {
        do {
            if me == nil { me = try await people.me() }
            var list = try await chat.listSpaces()
            connectionError = nil
            let listed = Set(list.map(\.name))
            localSpaces = localSpaces.filter { !listed.contains($0.key) }
            list += localSpaces.values

            let isFirstLoad = phase != .ready
            let previous = spaces.reduce(into: [String: Date?]()) { $0[$1.name] = $1.lastActiveTime }
            // Keep local activity bumps that the server has not caught up with yet.
            spaces = Self.sorted(list.map { space in
                var space = space
                if let known = previous[space.name] ?? nil, known > space.lastActiveTime ?? .distantPast {
                    space.lastActiveTime = known
                }
                return space
            })
            phase = .ready

            if isFirstLoad {
                Task { await self.loadReadStates() }
                Task { await self.loadDirectory() }
            } else {
                for space in spaces {
                    guard let active = space.lastActiveTime else { continue }
                    if let known = previous[space.name] {
                        if let known, active <= known { continue }
                        await ingest(in: space, since: known, changed: true)
                    } else {
                        // Just added to this space.
                        await ingest(in: space, since: active.addingTimeInterval(-1), changed: true)
                    }
                }
                refreshCount += 1
                if refreshCount % 4 == 0 { await recheckUnread() }
            }
            Task { await self.resolveTitles() }
            reportUnread()
        } catch {
            report(error)
            if phase != .ready {
                phase = .failed(connectionError ?? error.localizedDescription)
            }
        }
    }

    private static func sorted(_ spaces: [Space]) -> [Space] {
        spaces.sorted {
            let a = $0.lastActiveTime ?? .distantPast
            let b = $1.lastActiveTime ?? .distantPast
            return a == b ? $0.name < $1.name : a > b
        }
    }

    private func bumpActivity(of name: String, to time: Date?) {
        guard let time, let index = spaces.firstIndex(where: { $0.name == name }),
              time > spaces[index].lastActiveTime ?? .distantPast
        else { return }
        spaces[index].lastActiveTime = time
        spaces = Self.sorted(spaces)
    }

    // MARK: - People

    /// Opens the conversation with the given people: a direct message for one
    /// person, a group chat for several. An existing one is reused, otherwise
    /// it is created.
    public func startConversation(with people: [Profile]) async {
        guard let first = people.first else { return }
        do {
            if people.count == 1 {
                try await startDirectMessage(with: first)
            } else {
                try await startGroupChat(with: people)
            }
        } catch let error as APIError where error.status == 403 {
            alertMessage = "Could not start the conversation: \(error.message)\n\n"
                + "If this mentions scopes or permissions, add the chat.spaces.create scope "
                + "in the Google Cloud console (see the README), then sign out and sign in again."
        } catch {
            report(error)
            alertMessage = "Could not start the conversation: \(error.localizedDescription)"
        }
    }

    private func startDirectMessage(with person: Profile) async throws {
        if let existing = partners.first(where: { $0.value == person.user })?.key,
           space(named: existing) != nil {
            selection = existing
            return
        }
        let space: Space
        if let found = try await chat.findDirectMessage(with: person.user) {
            space = found
        } else {
            space = try await chat.createDirectMessage(with: person.user)
        }
        profiles[person.user] = profiles[person.user] ?? person
        partners[space.name] = person.user
        defaults.set(partners, forKey: Keys.partners)
        if let name = person.displayName ?? person.email { setTitle(name, for: space.name) }
        adopt(space)
    }

    private func startGroupChat(with people: [Profile]) async throws {
        let users = Set(people.map(\.user))
        if let existing = spaces.first(where: { $0.kind == .groupChat && groupMembers[$0.name] == users }) {
            selection = existing.name
            return
        }
        let space = try await chat.createGroupChat(with: users.sorted())
        for person in people { profiles[person.user] = profiles[person.user] ?? person }
        setGroupMembers(users, for: space.name)
        setTitle(Self.groupTitle(people.compactMap { $0.displayName ?? $0.email }), for: space.name)
        adopt(space)
    }

    /// Selects a conversation that was just found or created, adding it to the list if needed.
    private func adopt(_ space: Space) {
        if self.space(named: space.name) == nil {
            var space = space
            // Listed first until it has real activity.
            space.lastActiveTime = space.lastActiveTime ?? Date()
            localSpaces[space.name] = space
            spaces = Self.sorted(spaces + [space])
        }
        selection = space.name
    }

    private func setGroupMembers(_ users: Set<String>, for name: String) {
        groupMembers[name] = users
        defaults.set(groupMembers.mapValues { $0.sorted() }, forKey: Keys.groupMembers)
    }

    private static func groupTitle(_ names: [String]) -> String {
        names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }.joined(separator: ", ")
    }

    private func loadDirectory() async {
        guard let people = try? await people.listDirectory() else { return }
        directory = people
            .filter { $0.user != me?.user }
            .sorted {
                ($0.displayName ?? $0.email ?? "").localizedCaseInsensitiveCompare($1.displayName ?? $1.email ?? "")
                    == .orderedAscending
            }
    }

    // MARK: - Messages

    /// Loads the latest messages of a conversation and marks it read.
    public func open(_ name: String) async {
        if transcripts[name]?.isLoaded == true {
            if let space = space(named: name) { await ingest(in: space, since: nil, changed: false) }
        } else {
            do {
                let page = try await chat.listMessages(
                    in: name, pageSize: Self.pageSize, pageToken: nil, after: nil)
                var transcript = transcripts[name] ?? Transcript()
                transcript.isLoaded = true
                transcript.loadError = nil
                transcript.olderPageToken = page.nextPageToken
                transcripts[name] = transcript
                merge(page.messages, into: name)
                connectionError = nil
            } catch {
                report(error)
                transcripts[name, default: Transcript()].loadError = error.localizedDescription
                return
            }
        }
        if isViewing(name) { await markRead(name) }
    }

    public func loadOlder(in name: String) async {
        guard let transcript = transcripts[name], transcript.isLoaded, !transcript.isLoadingOlder,
              let token = transcript.olderPageToken
        else { return }
        transcripts[name]?.isLoadingOlder = true
        defer { transcripts[name]?.isLoadingOlder = false }
        do {
            let page = try await chat.listMessages(
                in: name, pageSize: Self.pageSize, pageToken: token, after: nil)
            transcripts[name]?.olderPageToken = page.nextPageToken
            merge(page.messages, into: name)
        } catch {
            report(error)
        }
    }

    public func send(_ text: String, to name: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pending = PendingMessage(id: UUID(), text: trimmed)
        transcripts[name, default: Transcript()].pending.append(pending)
        await deliver(pending, to: name)
    }

    public func retry(_ pending: PendingMessage, in name: String) async {
        guard let index = transcripts[name]?.pending.firstIndex(where: { $0.id == pending.id }) else { return }
        transcripts[name]?.pending[index].error = nil
        await deliver(pending, to: name)
    }

    public func discard(_ pending: PendingMessage, in name: String) {
        transcripts[name]?.pending.removeAll { $0.id == pending.id }
    }

    private func deliver(_ pending: PendingMessage, to name: String) async {
        do {
            let message = try await chat.sendMessage(pending.text, to: name)
            transcripts[name]?.pending.removeAll { $0.id == pending.id }
            merge([message], into: name)
            readTimes[name] = max(Date(), message.createTime ?? .distantPast)
        } catch {
            report(error)
            if let index = transcripts[name]?.pending.firstIndex(where: { $0.id == pending.id }) {
                transcripts[name]?.pending[index].error = error.localizedDescription
            }
        }
    }

    private func pollSelection() async {
        guard let name = selection, let space = space(named: name),
              transcripts[name]?.isLoaded == true
        else { return }
        await ingest(in: space, since: nil, changed: false)
    }

    /// Fetches messages newer than what is known, then notifies or marks read.
    /// `changed` means the conversation list already showed new activity.
    private func ingest(in space: Space, since: Date?, changed: Bool) async {
        let name = space.name
        let isLoaded = transcripts[name]?.isLoaded == true
        let newest = isLoaded ? transcripts[name]?.messages.last?.createTime : nil
        let after = newest ?? since ?? Date().addingTimeInterval(-120)

        var incoming: [Message] = []
        do {
            var token: String?
            var pages = 0
            repeat {
                let page = try await chat.listMessages(in: name, pageSize: 100, pageToken: token, after: after)
                incoming += page.messages
                token = page.nextPageToken
                pages += 1
            } while token != nil && pages < 5
            connectionError = nil
        } catch {
            report(error)
            return
        }

        let known = Set(transcripts[name]?.messages.map(\.name) ?? [])
        let fresh = incoming
            .filter { !known.contains($0.name) }
            .sorted { ($0.createTime ?? .distantPast) < ($1.createTime ?? .distantPast) }
        if isLoaded {
            merge(fresh, into: name)
        } else {
            resolveProfiles(in: fresh)
            bumpActivity(of: name, to: fresh.last?.createTime)
        }
        guard changed || !fresh.isEmpty else { return }

        if isViewing(name) {
            await markRead(name)
        } else {
            let fromOthers = fresh.filter { !isMine($0) }
            if !fromOthers.isEmpty { onIncoming?(space, fromOthers) }
            await refreshReadState(name)
        }
    }

    private func merge(_ messages: [Message], into name: String) {
        guard !messages.isEmpty else { return }
        var transcript = transcripts[name] ?? Transcript()
        let known = Set(transcript.messages.map(\.name))
        transcript.messages += messages.filter { !known.contains($0.name) }
        transcript.messages.sort {
            let a = $0.createTime ?? .distantPast
            let b = $1.createTime ?? .distantPast
            return a == b ? $0.name < $1.name : a < b
        }
        transcripts[name] = transcript
        resolveProfiles(in: messages)
        adoptAppTitle(from: messages, for: name)
        bumpActivity(of: name, to: transcript.messages.last?.createTime)
    }

    // MARK: - Read markers

    private func isViewing(_ name: String) -> Bool {
        selection == name && isAppActive
    }

    /// Marks the conversation read here and on the server.
    public func markRead(_ name: String) async {
        guard let space = space(named: name) else { return }
        let needsUpdate = isUnread(space) || readTimes[name] == nil
        let time = max(Date(), space.lastActiveTime ?? .distantPast)
        readTimes[name] = time
        reportUnread()
        guard needsUpdate else { return }
        do {
            try await chat.markRead(space: name, at: time)
        } catch {
            report(error)
        }
    }

    private func refreshReadState(_ name: String) async {
        guard let state = try? await chat.readState(for: name) else { return }
        // The local marker may be ahead of the server right after marking read.
        readTimes[name] = max(readTimes[name] ?? .distantPast, state.lastReadTime ?? .distantPast)
        reportUnread()
    }

    private func loadReadStates() async {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let recent = spaces.filter { ($0.lastActiveTime ?? .distantPast) > cutoff }
        await forEachLimited(recent.map(\.name)) { await self.refreshReadState($0) }
    }

    /// Picks up conversations that were read on another device.
    private func recheckUnread() async {
        let unread = spaces.filter { isUnread($0) && !isViewing($0.name) }.prefix(20)
        await forEachLimited(unread.map(\.name)) { await self.refreshReadState($0) }
    }

    private func reportUnread() {
        let count = unreadCount
        guard count != reportedUnread else { return }
        reportedUnread = count
        onUnreadCountChanged?(count)
    }

    // MARK: - Names

    private func resolveProfiles(in messages: [Message]) {
        for sender in Set(messages.compactMap(\.sender)) where !sender.isBot {
            if let name = sender.displayName, !name.isEmpty, seedNames[sender.name] == nil {
                seedNames[sender.name] = name
            }
            requestProfile(sender.name)
        }
    }

    private func requestProfile(_ user: String) {
        guard profiles[user] == nil, !profileRequests.contains(user) else { return }
        profileRequests.insert(user)
        Task {
            if let profile = try? await people.profile(for: user) { store(profile) }
        }
    }

    private func store(_ profile: Profile) {
        profiles[profile.user] = profile
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Keys.profiles)
        }
    }

    /// Direct messages and group chats have no name of their own; build one from the members.
    private func resolveTitles() async {
        let untitled = spaces.filter {
            ($0.displayName ?? "").isEmpty && titles[$0.name] == nil && !titleAttempts.contains($0.name)
        }
        guard !untitled.isEmpty else { return }
        for space in untitled { titleAttempts.insert(space.name) }
        await forEachLimited(untitled) { await self.resolveTitle($0) }
    }

    private func resolveTitle(_ space: Space) async {
        guard let members = try? await chat.listMembers(of: space.name) else {
            titleAttempts.remove(space.name)
            return
        }
        if space.singleUserBotDm == true {
            let app = members.compactMap(\.member).first { $0.isBot }
            if let name = app?.displayName, !name.isEmpty { setTitle(name, for: space.name) }
            return
        }
        let others = members.compactMap(\.member).filter { $0.name != me?.user && !$0.isBot }
        var names: [String] = []
        for user in others.prefix(8) {
            if let name = user.displayName, !name.isEmpty {
                seedNames[user.name] = name
                names.append(name)
                requestProfile(user.name)
            } else if let name = profiles[user.name]?.displayName {
                names.append(name)
            } else if let profile = try? await people.profile(for: user.name) {
                store(profile)
                if let name = profile.displayName { names.append(name) }
            }
        }
        if space.kind == .directMessage, let partner = others.first {
            partners[space.name] = partner.name
            defaults.set(partners, forKey: Keys.partners)
        }
        // Remembered so that starting a chat with the same people reuses this one.
        // A full page may be missing members, so those are not recorded.
        if space.kind == .groupChat, members.count < 100 {
            setGroupMembers(Set(others.map(\.name)), for: space.name)
        }
        guard !names.isEmpty else { return }
        setTitle(space.kind == .directMessage ? names[0] : Self.groupTitle(names), for: space.name)
    }

    private func setTitle(_ title: String, for name: String) {
        titles[name] = title
        defaults.set(titles, forKey: Keys.titles)
    }

    /// A direct message with a Chat app takes the app's name from its messages
    /// when the member list did not provide one.
    private func adoptAppTitle(from messages: [Message], for name: String) {
        guard titles[name] == nil, space(named: name)?.singleUserBotDm == true,
              let appName = messages.lazy.compactMap(\.sender).first(where: { $0.isBot })?.displayName,
              !appName.isEmpty
        else { return }
        setTitle(appName, for: name)
    }

    // MARK: - Helpers

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? AuthError, error == .reauthRequired {
            stop()
            onAuthFailure?()
            return
        }
        if let error = error as? URLError {
            if error.code == .cancelled { return }
            connectionError = error.code == .notConnectedToInternet ? "Offline" : error.localizedDescription
        } else {
            connectionError = error.localizedDescription
        }
    }

    /// Runs `body` for each item with at most four requests in flight.
    private func forEachLimited<Item: Sendable>(
        _ items: [Item], _ body: @escaping @MainActor @Sendable (Item) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<4 {
                guard let item = iterator.next() else { break }
                group.addTask { await body(item) }
            }
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask { await body(item) }
                }
            }
        }
    }
}
