import AppKit
import GChatKit
import Network
import Observation

/// Owns the signed-in session and connects the store to the system:
/// sign-in, notifications, the dock badge, app activity and network state.
@MainActor
@Observable
final class AppModel {
    private(set) var store: ChatStore?
    private(set) var isSigningIn = false
    var signInError: String?
    var isQuickSwitcherShown = false
    var isNewConversationShown = false
    /// False when macOS has notifications turned off for GChat.
    private(set) var notificationsAllowed = true
    var drafts: [String: String] = [:]
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Self.clientIDKey) }
    }

    @ObservationIgnored private var auth: AuthSession?
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let webAuth = WebAuth()
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let clientIDKey = "oauthClientID"

    init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        notifier.onOpen = { [weak self] space in self?.show(space) }
        observeSystem()

        // Resume the previous session when its tokens are still in the Keychain.
        let tokens = KeychainTokenStore()
        if let config = try? OAuthConfig(clientID: clientID), tokens.load() != nil {
            startSession(AuthSession(config: config, store: tokens))
        }
    }

    // MARK: - Session

    func signIn() async {
        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let config = try OAuthConfig(clientID: clientID)
            let pkce = PKCE()
            let state = UUID().uuidString
            let callback = try await webAuth.authenticate(
                url: config.authorizationURL(state: state, challenge: pkce.challenge),
                scheme: config.redirectScheme)
            let session = AuthSession(config: config, store: KeychainTokenStore())
            try await session.completeSignIn(
                callbackURL: callback, expectedState: state, verifier: pkce.verifier)
            startSession(session)
        } catch WebAuth.Cancelled.cancelled {
            // The user closed the sign-in sheet.
        } catch {
            signInError = error.localizedDescription
        }
    }

    func signOut() {
        let auth = auth
        Task { await auth?.signOut() }
        endSession()
    }

    private func startSession(_ auth: AuthSession) {
        let client = APIClient(tokens: auth)
        let store = ChatStore(chat: ChatAPI(client: client), people: PeopleAPI(client: client))
        store.isAppActive = NSApp?.isActive ?? true
        store.onIncoming = { [weak self] space, messages in
            self?.notify(space: space, messages: messages)
        }
        store.onUnreadCountChanged = { [weak self] count in
            self?.notifier.setBadge(count)
        }
        store.onAuthFailure = { [weak self] in
            self?.endSession()
            self?.signInError = AuthError.reauthRequired.localizedDescription
        }
        self.auth = auth
        self.store = store
        notifier.requestAuthorization { [weak self] allowed in self?.notificationsAllowed = allowed }
        store.start()
    }

    private func endSession() {
        store?.stop()
        store = nil
        auth = nil
        drafts = [:]
        notifier.setBadge(0)
        AttachmentFiles.removeAll()
    }

    // MARK: - System integration

    private func show(_ space: String) {
        store?.selection = space
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    private func notify(space: Space, messages: [Message]) {
        guard let store, AppSettings.notificationsEnabled, let latest = messages.last else { return }
        let sender = store.name(for: latest.sender)
        let conversation = space.kind == .directMessage ? nil : store.title(for: space)
        var body = latest.text ?? ""
        if body.isEmpty { body = latest.attachment?.isEmpty == false ? "Sent an attachment" : "New message" }
        if !AppSettings.notificationPreviews { body = "New message" }
        if messages.count > 1 { body += " (and \(messages.count - 1) more)" }
        notifier.post(space: space.name, title: sender, subtitle: conversation, body: body)
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(true) }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(false) }
        })

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.store?.isOnline = isOnline }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    private func setActive(_ isActive: Bool) {
        if isActive {
            notifier.checkAuthorization { [weak self] allowed in self?.notificationsAllowed = allowed }
        }
        guard let store else { return }
        store.isAppActive = isActive
        // Coming back to the app with a conversation open counts as reading it.
        if isActive, let selection = store.selection {
            Task { await store.open(selection) }
        }
    }
}

enum SidebarSort: String, CaseIterable, Identifiable {
    case recent
    case alphabetical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: "Most recent first"
        case .alphabetical: "Alphabetically"
        }
    }
}

enum AppSettings {
    static let notificationsKey = "notificationsEnabled"
    static let previewsKey = "notificationPreviews"
    static let hideDeletedKey = "hideDeletedUserConversations"
    static let showDatesKey = "showSidebarDates"
    static let sidebarSortKey = "sidebarSort"

    static let hideUnnamedAppsKey = "hideUnnamedAppConversations"
    static let hideAppsKey = "hideAppConversations"
    static let quitOnCloseKey = "quitWhenWindowCloses"

    /// Whether the sidebar settings hide this conversation. Reads the stored
    /// settings directly; views that must update live also observe the keys.
    @MainActor
    static func isHidden(_ space: Space, in store: ChatStore) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hideDeletedKey) as? Bool ?? true, store.isWithDeletedUser(space) {
            return true
        }
        if defaults.bool(forKey: hideAppsKey), store.isWithApp(space) {
            return true
        }
        if defaults.object(forKey: hideUnnamedAppsKey) as? Bool ?? true, store.isWithUnnamedApp(space) {
            return true
        }
        return false
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? true
    }

    static var notificationPreviews: Bool {
        UserDefaults.standard.object(forKey: previewsKey) as? Bool ?? true
    }
}
