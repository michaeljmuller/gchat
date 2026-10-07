import Foundation
import Observation
import os

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
    /// Why the directory could not be loaded, when it could not.
    public private(set) var directoryError: String?
    /// True when Google refused the directory request as not permitted, as opposed
    /// to a network or other temporary failure.
    public private(set) var isDirectoryBlocked = false
    /// A failure the user should see once, such as not being able to start a conversation.
    public var alertMessage: String?
    /// The open conversation. Not remembered between launches.
    public var selection: String?
    public var isAppActive = true
    public var isOnline = true
    /// True while the stream to the relay is open. Polling then slows to a
    /// safety net. Set by PushController.
    public var isPushConnected = false
    /// True when the relay has been out of reach for a while, so the app is
    /// back to polling at its normal rate. Set by PushController. Shown in the
    /// sidebar.
    public var isPushDown = false
    /// How often the conversation list is polled at the moment, in seconds.
    /// It follows chat activity. Shown in the sidebar when the relay is down.
    public private(set) var listPollSeconds = 15

    /// Called when a message was sent or a new one arrived. PushController
    /// uses it to try the relay again early.
    @ObservationIgnored public var onActivity: (() -> Void)?

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
    private var groupMembers: [String: Set<String>]
    private var profiles: [String: Profile]
    /// Users the People API reports as not found, which is how deleted accounts appear.
    private var missingUsers: Set<String>

    /// Direct messages created here that have no messages yet. The server leaves
    /// those out of the conversation list.
    @ObservationIgnored private var localSpaces: [String: Space] = [:]
    @ObservationIgnored private var profileRequests: Set<String> = []
    @ObservationIgnored private var titleAttempts: Set<String> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastSafetyPoll = Date.distantPast
    /// When a message was last sent or received. Starts in the past, so a
    /// launch with no activity polls at the normal rate.
    @ObservationIgnored private var lastActivity = Date().addingTimeInterval(-120)
    /// Names of messages that were already added, notified or marked read.
    @ObservationIgnored private var handledMessages: Set<String> = []
    @ObservationIgnored private var reportedUnread = -1
    @ObservationIgnored private var refreshCount = 0

    private let chat: any ChatService
    private let people: any ProfileService
    private let defaults: UserDefaults

    private enum Keys {
        static let titles = "spaceTitles"
        static let partners = "spacePartners"
        static let groupMembers = "groupMembers"
        static let profiles = "profiles"
        static let missingUsers = "missingUsers"
        static let cacheOwner = "cacheOwner"
    }

    private static let deletedName = "Deleted User"
    private static let log = Logger(subsystem: "org.themullers.gchat", category: "names")

    private static let safetyInterval: TimeInterval = 60

    /// How often to poll, in seconds, for a given time since the last message
    /// was sent or received. Whether the app is in front does not matter: the
    /// person can be switching between GChat and other work.
    static func pollIntervals(sinceActivity: TimeInterval) -> (open: TimeInterval, list: TimeInterval) {
        switch sinceActivity {
        case ..<120: (2, 10)     // a conversation is going on
        case ..<600: (5, 15)
        default: (15, 30)        // nothing for ten minutes
        }
    }
    private static let pageSize = 50

    public init(chat: any ChatService, people: any ProfileService, defaults: UserDefaults = .standard) {
        self.chat = chat
        self.people = people
        self.defaults = defaults
        self.titles = defaults.dictionary(forKey: Keys.titles) as? [String: String] ?? [:]
        self.partners = defaults.dictionary(forKey: Keys.partners) as? [String: String] ?? [:]
        self.groupMembers = (defaults.dictionary(forKey: Keys.groupMembers) as? [String: [String]] ?? [:])
            .mapValues(Set.init)
        self.missingUsers = Set(defaults.stringArray(forKey: Keys.missingUsers) ?? [])
        self.profiles = defaults.data(forKey: Keys.profiles)
            .flatMap { try? JSONDecoder().decode([String: Profile].self, from: $0) } ?? [:]
    }

    /// The cached names, titles and members belong to one account. When another
    /// account signs in, they are discarded so that nothing from the previous
    /// account shows up.
    private func claimCache(for user: String) {
        guard defaults.string(forKey: Keys.cacheOwner) != user else { return }
        titles = [:]
        partners = [:]
        groupMembers = [:]
        profiles = [:]
        missingUsers = []
        selection = nil
        for key in [Keys.titles, Keys.partners, Keys.groupMembers, Keys.profiles, Keys.missingUsers] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(user, forKey: Keys.cacheOwner)
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

    /// Spaces that people created, as opposed to meeting chats.
    public var namedSpaces: [Space] {
        spaces.filter { $0.kind != .directMessage && $0.kind != .groupChat && !$0.isMeetingChat }
    }

    public var meetingChats: [Space] {
        spaces.filter(\.isMeetingChat)
    }

    public func title(for space: Space) -> String {
        if let name = space.displayName, !name.isEmpty { return name }
        if let title = currentTitle(for: space) ?? titles[space.name] { return title }
        if space.singleUserBotDm == true { return "App" }
        switch space.kind {
        case .directMessage: return "Direct Message"
        case .groupChat: return "Group Chat"
        default: return "Space"
        }
    }

    /// A title built from the members' current names. The stored title is only
    /// a fallback, because people can be renamed.
    private func currentTitle(for space: Space) -> String? {
        switch space.kind {
        case .directMessage:
            return partners[space.name].flatMap(knownName(of:))
        case .groupChat:
            guard let members = groupMembers[space.name], !members.isEmpty else { return nil }
            let names = members.compactMap(knownName(of:))
            guard names.count == members.count else { return nil }
            return Self.groupTitle(names)
        default:
            return nil
        }
    }

    private func knownName(of user: String) -> String? {
        profiles[user]?.displayName ?? (missingUsers.contains(user) ? Self.deletedName : nil)
    }

    /// True for a direct message whose other member's account no longer exists.
    public func isWithDeletedUser(_ space: Space) -> Bool {
        guard space.kind == .directMessage, space.singleUserBotDm != true else { return false }
        if let partner = partners[space.name] { return missingUsers.contains(partner) }
        return titles[space.name] == Self.deletedName
    }

    /// True for a direct message between the user and a Chat app.
    public func isWithApp(_ space: Space) -> Bool {
        space.singleUserBotDm == true
    }

    /// True for a direct message with a Chat app that Google gives no name for.
    public func isWithUnnamedApp(_ space: Space) -> Bool {
        isWithApp(space) && (space.displayName ?? "").isEmpty && titles[space.name] == nil
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
        if let name = profiles[user.name]?.displayName ?? user.displayName,
           !name.isEmpty {
            return name
        }
        if missingUsers.contains(user.name) { return Self.deletedName }
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
        var lastOpenPoll = Date()
        var lastListPoll = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            guard isOnline, !isPaused else { continue }
            if phase != .ready {
                if Date().timeIntervalSince(lastListPoll) >= 3 {
                    await refreshSpaces()
                    lastListPoll = Date()
                }
                continue
            }
            if isPushConnected {
                // Notices arrive through the relay. Poll now and then anyway,
                // in case one was lost.
                if Date().timeIntervalSince(lastSafetyPoll) >= Self.safetyInterval {
                    await catchUp()
                }
                continue
            }
            let intervals = Self.pollIntervals(sinceActivity: Date().timeIntervalSince(lastActivity))
            if listPollSeconds != Int(intervals.list) { listPollSeconds = Int(intervals.list) }
            if Date().timeIntervalSince(lastOpenPoll) >= intervals.open {
                await pollSelection()
                lastOpenPoll = Date()
            }
            if Date().timeIntervalSince(lastListPoll) >= intervals.list {
                await refreshSpaces()
                lastListPoll = Date()
            }
        }
    }

    private func noteActivity() {
        lastActivity = Date()
        onActivity?()
    }

    /// Brings the conversation list and the open conversation up to date.
    public func catchUp() async {
        lastSafetyPoll = Date()
        await refreshSpaces()
        await pollSelection()
    }

    /// Acts on a notice from the relay. A notice holds identifiers only, so
    /// the content comes from the Chat API with the person's own sign-in.
    public func handlePush(type: String, subject: String, resource: String?) async {
        let prefix = "//chat.googleapis.com/"
        guard subject.hasPrefix(prefix) else { return }
        let name = String(subject.dropFirst(prefix.count))
        switch type {
        case WorkspaceEventsAPI.messageCreated:
            guard let space = space(named: name) else {
                // A conversation that is not in the list yet.
                await refreshSpaces()
                return
            }
            // Fetch the message that the notice names. The message list can
            // lag behind the notice by a moment.
            if let resource, let message = try? await chat.getMessage(resource) {
                await process([message], in: space, changed: true)
            } else {
                await ingest(in: space, since: space.lastActiveTime, changed: true)
            }
        case WorkspaceEventsAPI.messageUpdated:
            guard let resource, transcripts[name]?.isLoaded == true,
                  let message = try? await chat.getMessage(resource),
                  let index = transcripts[name]?.messages.firstIndex(where: { $0.name == resource })
            else { return }
            transcripts[name]?.messages[index] = message
        case WorkspaceEventsAPI.messageDeleted:
            guard let resource else { return }
            transcripts[name]?.messages.removeAll { $0.name == resource }
        default:
            break
        }
    }

    /// Reloads the conversation list and whatever is open. Used by the Refresh command.
    public func refresh() async {
        await refreshSpaces()
        await loadDirectory()
        if let selection { await open(selection) }
    }

    /// People to offer for a new conversation: the organization's directory, or,
    /// when that is unavailable, everyone already known from existing conversations.
    public var contacts: [Profile] {
        guard directoryError != nil else { return directory }
        var users: Set<String> = []
        for space in spaces {
            if let partner = partners[space.name] { users.insert(partner) }
            users.formUnion(groupMembers[space.name] ?? [])
        }
        return users.compactMap { profiles[$0] }
            .filter { $0.displayName != nil && $0.user != me?.user && !missingUsers.contains($0.user) }
            .sorted {
                ($0.displayName ?? "").localizedCaseInsensitiveCompare($1.displayName ?? "") == .orderedAscending
            }
    }


    // MARK: - Conversation list

    func refreshSpaces() async {
        do {
            if me == nil {
                let me = try await people.me()
                claimCache(for: me.user)
                self.me = me
            }
            var list = try await chat.listSpaces()
            connectionError = nil
            backoffLevel = 0
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
                + "in the Google Cloud console (see docs/google-cloud-setup.md), then sign out and sign in again."
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

    /// First names in alphabetical order, with deleted users last.
    private static func groupTitle(_ names: [String]) -> String {
        let people = names.filter { $0 != deletedName }
            .map { $0.split(separator: " ").first.map(String.init) ?? $0 }
            .sorted()
        let deleted = names.filter { $0 == deletedName }
        return (Array(people.prefix(8)) + deleted.prefix(1)).joined(separator: ", ")
    }

    private func loadDirectory() async {
        let people: [Profile]
        do {
            people = try await self.people.listDirectory()
            directoryError = nil
            isDirectoryBlocked = false
            Self.log.info("Directory: \(people.count) people")
        } catch {
            directoryError = error.localizedDescription
            isDirectoryBlocked = (error as? APIError)?.status == 403
            Self.log.error("Directory failed: \(String(describing: error), privacy: .public)")
            await refreshTitleProfiles()
            return
        }
        // The directory is current, so it also refreshes cached names and photos.
        for person in people { profileRequests.insert(person.user) }
        store(people)
        await refreshTitleProfiles()
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

    /// Downloads a file that was uploaded to Chat. Returns nil for attachments
    /// that live elsewhere, such as Google Drive files.
    public func download(_ attachment: Attachment) async throws -> Data? {
        guard let resource = attachment.attachmentDataRef?.resourceName else { return nil }
        return try await chat.downloadAttachment(resource)
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
            noteActivity()
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

        // The filter is sent to Google cut to microseconds, so the message at
        // `after` itself can come back. It is not new.
        await process(incoming.filter { ($0.createTime ?? .distantFuture) > after }, in: space, changed: changed)
    }

    /// Takes messages that may be new: adds them to a loaded transcript, and
    /// notifies or marks read. Each message is handled once, however often it
    /// arrives, so a notice that Pub/Sub delivers twice does nothing twice.
    private func process(_ incoming: [Message], in space: Space, changed: Bool) async {
        let name = space.name
        let isLoaded = transcripts[name]?.isLoaded == true
        let known = Set(transcripts[name]?.messages.map(\.name) ?? [])
        let fresh = incoming
            .filter { !known.contains($0.name) && !handledMessages.contains($0.name) }
            .sorted { ($0.createTime ?? .distantPast) < ($1.createTime ?? .distantPast) }
        for message in fresh {
            handledMessages.insert(message.name)
            Self.log.info("""
                New message in \(name, privacy: .public): sender \(message.sender?.name ?? "none", privacy: .public), \
                me \(self.me?.user ?? "unknown", privacy: .public), mine \(self.isMine(message))
                """)
        }
        if handledMessages.count > 2000 { handledMessages.removeAll() }
        if !fresh.isEmpty { noteActivity() }
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
        guard !isPaused else { return }
        let state: SpaceReadState
        do {
            state = try await chat.readState(for: name)
        } catch {
            if (error as? APIError)?.status == 429 { report(error) }
            return
        }
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
            if let name = sender.displayName { noteName(name, for: sender.name) }
            requestProfile(sender.name)
        }
    }

    private func requestProfile(_ user: String) {
        // Once per launch, even when cached, so that renames are picked up.
        guard !profileRequests.contains(user) else { return }
        profileRequests.insert(user)
        Task { await lookUp(user) }
    }

    /// Fetches a person from the People API and records the result, including "not found".
    @discardableResult
    private func lookUp(_ user: String) async -> Profile? {
        profileRequests.insert(user)
        do {
            let profile = try await people.profile(for: user)
            store([profile])
            setMissing(user, false)
            return profile
        } catch let error as APIError where error.status == 404 {
            Self.log.info("People lookup for \(user, privacy: .public): not found")
            setMissing(user, true)
        } catch {
            Self.log.info("People lookup for \(user, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        return nil
    }

    private func setMissing(_ user: String, _ isMissing: Bool) {
        guard missingUsers.contains(user) != isMissing else { return }
        if isMissing { missingUsers.insert(user) } else { missingUsers.remove(user) }
        defaults.set(missingUsers.sorted(), forKey: Keys.missingUsers)
    }

    /// Records a name that came with a Chat response. Some organizations do not
    /// let the People API return names for other users, so this is then the
    /// only source.
    private func noteName(_ name: String, for user: String) {
        guard !name.isEmpty, profiles[user]?.displayName != name else { return }
        var profile = profiles[user] ?? Profile(user: user)
        profile.displayName = name
        store([profile])
    }

    private func store(_ updates: [Profile]) {
        for var profile in updates {
            // A lookup that returns less than is already known does not erase it.
            let known = profiles[profile.user]
            profile.displayName = profile.displayName ?? known?.displayName
            profile.photoURL = profile.photoURL ?? known?.photoURL
            profile.email = profile.email ?? known?.email
            profiles[profile.user] = profile
        }
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Keys.profiles)
        }
    }

    /// Looks up the people that conversation titles are built from, most
    /// recent conversations first, skipping anyone already looked up.
    private func refreshTitleProfiles() async {
        var users: [String] = []
        for space in spaces.prefix(100) {
            if let partner = partners[space.name] { users.append(partner) }
            users += (groupMembers[space.name] ?? []).sorted()
        }
        let pending = users.filter { profileRequests.insert($0).inserted }
        await forEachLimited(pending) { await self.lookUp($0) }
    }

    /// Direct messages and group chats have no name of their own; build one from the members.
    private func resolveTitles() async {
        let untitled = spaces.filter {
            ($0.displayName ?? "").isEmpty && !titleAttempts.contains($0.name)
                && (titles[$0.name] == nil || needsMemberNames($0))
        }
        guard !untitled.isEmpty else { return }
        for space in untitled { titleAttempts.insert(space.name) }
        await forEachLimited(untitled) { await self.resolveTitle($0) }
    }

    /// True when a titled conversation still lacks its members or their names,
    /// which the New Conversation list and live titles are built from.
    private func needsMemberNames(_ space: Space) -> Bool {
        guard space.kind == .directMessage || space.kind == .groupChat, space.singleUserBotDm != true,
              titles[space.name] != Self.deletedName
        else { return false }
        return currentTitle(for: space) == nil
    }

    private func resolveTitle(_ space: Space) async {
        // Skipped items are picked up by the next refresh of the conversation list.
        guard !isPaused else {
            titleAttempts.remove(space.name)
            return
        }
        let members: [Membership]
        do {
            members = try await chat.listMembers(of: space.name)
        } catch {
            if (error as? APIError)?.status == 429 { report(error) }
            titleAttempts.remove(space.name)
            return
        }
        if space.singleUserBotDm == true {
            let app = members.compactMap(\.member).first { $0.isBot }
            if let name = app?.displayName, !name.isEmpty {
                setTitle(name, for: space.name)
                return
            }
            // The member list rarely names the app; its messages do.
            let recent = (try? await chat.listMessages(
                in: space.name, pageSize: 10, pageToken: nil, after: nil))?.messages ?? []
            let senders = recent.compactMap(\.sender).filter(\.isBot)
            Self.log.info("""
                App conversation \(space.name, privacy: .public): member name \
                \(app?.displayName ?? "none", privacy: .public), \(recent.count) recent messages, \
                app senders: \(senders.map { $0.displayName ?? "unnamed" }.joined(separator: ", "), privacy: .public)
                """)
            if let name = senders.compactMap(\.displayName).first(where: { !$0.isEmpty }) {
                setTitle(name, for: space.name)
            }
            return
        }
        let others = members.compactMap(\.member).filter { $0.name != me?.user && !$0.isBot }
        Self.log.info("""
            Members of \(space.name, privacy: .public) (\(space.spaceType ?? "?", privacy: .public)): \
            \(members.count) listed, others: \(others.map(\.name).joined(separator: " "), privacy: .public)
            """)
        if space.kind == .directMessage, others.isEmpty {
            // Only the signed-in user is left in the conversation.
            setTitle(Self.deletedName, for: space.name)
            return
        }
        for user in others {
            if let name = user.displayName { noteName(name, for: user.name) }
        }
        var names: [String] = []
        for user in others.prefix(8) {
            if let name = user.displayName, !name.isEmpty {
                noteName(name, for: user.name)
                names.append(name)
                requestProfile(user.name)
            } else if let name = profiles[user.name]?.displayName {
                names.append(name)
            } else if let name = await lookUp(user.name)?.displayName {
                names.append(name)
            } else if missingUsers.contains(user.name) {
                names.append(Self.deletedName)
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

    // MARK: - Backing off

    /// Set when Google answers 429 (too many requests). Polling and background
    /// lookups stop until then.
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private var backoffLevel = 0

    private var isPaused: Bool {
        if let pausedUntil, pausedUntil > Date() { return true }
        return false
    }

    /// Doubles the pause on each consecutive 429, from 2 seconds up to about a
    /// minute, with some randomness so many copies do not retry in step.
    private func backOff() {
        backoffLevel = min(backoffLevel + 1, 6)
        let delay = pow(2, Double(backoffLevel)) + Double.random(in: 0...1)
        pausedUntil = Date().addingTimeInterval(delay)
        connectionError = "Google asked GChat to slow down. Retrying in \(Int(delay.rounded())) seconds."
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? APIError, error.status == 429 {
            backOff()
            return
        }
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

    /// Pause between background requests from one worker. With four workers
    /// this keeps startup lookups to about ten requests a second.
    nonisolated static let requestSpacing = Duration.milliseconds(400)

    /// Runs `body` for each item with at most four requests in flight, paced
    /// by `requestSpacing`. Used for the lookups at startup.
    private func forEachLimited<Item: Sendable>(
        _ items: [Item], _ body: @escaping @MainActor @Sendable (Item) async -> Void
    ) async {
        let spacing = Self.requestSpacing
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<4 {
                guard let item = iterator.next() else { break }
                group.addTask {
                    await body(item)
                    try? await Task.sleep(for: spacing)
                }
            }
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask {
                        await body(item)
                        try? await Task.sleep(for: spacing)
                    }
                }
            }
        }
    }
}
