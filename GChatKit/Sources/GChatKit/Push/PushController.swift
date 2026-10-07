import Foundation
import os

/// Where an organization's build gets its push notices from.
public struct PushConfiguration: Sendable, Equatable {
    /// The relay, for example https://gchat-relay.themullers.org.
    public var relayURL: URL
    /// The Pub/Sub topic that Google publishes events to:
    /// projects/<project>/topics/<topic>.
    public var topic: String

    public init(relayURL: URL, topic: String) {
        self.relayURL = relayURL
        self.topic = topic
    }
}

/// Keeps push delivery going: makes and renews the Workspace Events
/// subscription, holds the stream to the relay open, and hands each notice to
/// the store. The store polls slowly while the stream is open, and at its
/// normal rate while it is not. See docs/design.md, "Push delivery".
@MainActor
public final class PushController {
    private let configuration: PushConfiguration
    private let identity: any IdentityTokenProviding
    private let subscriptions: any EventSubscriptionService
    private let store: ChatStore
    private let defaults: UserDefaults
    private let session: URLSession
    private var task: Task<Void, Never>?
    /// The wait before the next attempt, while one is in progress.
    private var retryWait: Task<Void, Never>?
    private var wasWokenEarly = false
    private var lastEarlyAttempt = Date.distantPast

    private static let log = Logger(subsystem: "org.themullers.gchat", category: "push")
    private static let subscriptionKey = "pushSubscription"
    private static let lifecyclePrefix = "google.workspace.events.subscription.v1."
    /// Renew when less than this is left of the 7 days that Google allows.
    private static let renewalMargin: TimeInterval = 2 * 24 * 3600
    /// The wait between attempts doubles from 1 second up to this.
    private static let longestRetryWait: TimeInterval = 15 * 60
    private static let earlyAttemptSpacing: TimeInterval = 60
    /// How long the relay must be out of reach before the app says so.
    private static let downAfter: TimeInterval = 30

    struct RelayRefused: Error {
        var status: Int
    }

    public init(
        configuration: PushConfiguration, identity: any IdentityTokenProviding,
        subscriptions: any EventSubscriptionService, store: ChatStore,
        defaults: UserDefaults = .standard, session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.identity = identity
        self.subscriptions = subscriptions
        self.store = store
        self.defaults = defaults
        self.session = session
    }

    public func start() {
        guard task == nil else { return }
        store.onActivity = { [weak self] in self?.noteActivity() }
        task = Task { await self.run() }
    }

    /// A message was sent or received. If the relay is out of reach and the
    /// controller is waiting to try again, try now: the person is chatting, so
    /// prompt delivery matters, and Google is reachable. At most once a minute,
    /// so a busy conversation during a real failure does not cause many attempts.
    func noteActivity() {
        guard let retryWait, Date().timeIntervalSince(lastEarlyAttempt) >= Self.earlyAttemptSpacing else {
            return
        }
        lastEarlyAttempt = Date()
        wasWokenEarly = true
        retryWait.cancel()
    }

    public func stop() {
        retryWait?.cancel()
        store.onActivity = nil
        task?.cancel()
        task = nil
        store.isPushConnected = false
        store.isPushDown = false
    }

    /// Stops, and deletes the subscription at Google so that no more events
    /// are published for this person. Called before Sign Out clears the tokens.
    public func signOut() async {
        stop()
        guard let name = defaults.string(forKey: Self.subscriptionKey) else { return }
        defaults.removeObject(forKey: Self.subscriptionKey)
        try? await subscriptions.delete(name)
    }

    private func run() async {
        var delay = 1.0
        // When the current run of failures began. The sidebar reports the relay
        // as down only after a while, so that a short interruption shows nothing.
        var failingSince: Date?
        while !Task.isCancelled {
            do {
                let subscription = try await ensureSubscription()
                try await listen(to: subscription)
                // The stream ended normally, for example for a new ID token.
                delay = 1
                failingSince = nil
            } catch is CancellationError {
                break
            } catch {
                Self.log.error("Push failed: \(String(describing: error), privacy: .public)")
                let since = failingSince ?? Date()
                failingSince = since
                if Date().timeIntervalSince(since) >= Self.downAfter { store.isPushDown = true }
            }
            store.isPushConnected = false
            if Task.isCancelled { break }
            // The wait is its own task, so that noteActivity can end it early.
            let wait = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(delay)) }
            retryWait = wait
            await wait.value
            retryWait = nil
            if wasWokenEarly {
                // Start the waits again from the beginning.
                wasWokenEarly = false
                delay = 1
            } else {
                delay = min(delay * 2, Self.longestRetryWait)
            }
        }
        store.isPushConnected = false
    }

    /// Returns the name of a working subscription: the saved one if Google
    /// still has it, the person's existing one, or a new one.
    func ensureSubscription() async throws -> String {
        if let name = defaults.string(forKey: Self.subscriptionKey) {
            do {
                let subscription = try await subscriptions.get(name)
                if try await makeUsable(subscription) { return name }
            } catch let error as APIError where error.status == 403 || error.status == 404 {
                // Gone, or made by another account on this Mac.
            }
            defaults.removeObject(forKey: Self.subscriptionKey)
        }
        do {
            let subscription = try await subscriptions.create(topic: configuration.topic)
            Self.log.info("Made subscription, expires \(String(describing: subscription.expireTime), privacy: .public)")
            return save(subscription.name)
        } catch let error as APIError where error.status == 409 {
            // Google allows one subscription per person for the same target.
            guard let existing = try await subscriptions.findExisting() else { throw error }
            if existing.pubsubTopic == configuration.topic, try await makeUsable(existing) {
                return save(existing.name)
            }
            // It points at another topic or cannot be revived: replace it.
            try await subscriptions.delete(existing.name)
            return save(try await subscriptions.create(topic: configuration.topic).name)
        }
    }

    /// Reactivates or renews a subscription as needed. False if it is deleted.
    private func makeUsable(_ subscription: EventSubscription) async throws -> Bool {
        if subscription.isSuspended {
            try await subscriptions.reactivate(subscription.name)
            return true
        }
        guard subscription.isActive else { return false }
        if let expires = subscription.expireTime, expires.timeIntervalSinceNow < Self.renewalMargin {
            try await subscriptions.renew(subscription.name)
        }
        return true
    }

    private func save(_ name: String) -> String {
        defaults.set(name, forKey: Self.subscriptionKey)
        return name
    }

    /// Reads the relay's stream until it ends.
    private func listen(to subscription: String) async throws {
        var components = URLComponents(
            url: configuration.relayURL.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "subscription", value: subscription)]
        var request = URLRequest(url: components.url!)
        // The relay sends a keepalive every 20 seconds. Silence for a minute
        // means that the connection is dead.
        request.timeoutInterval = 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Only the ID token goes to the relay. It cannot call Google APIs.
        let token = try await identity.idToken(minimumValidity: 600)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw RelayRefused(status: status) }

        Self.log.info("Connected to the relay")
        store.isPushConnected = true
        store.isPushDown = false
        defer { store.isPushConnected = false }
        // The relay keeps nothing for clients that were away.
        await store.catchUp()

        var parser = RelayStreamParser()
        for try await line in bytes.lines {
            guard let event = parser.feed(line) else { continue }
            switch event.event {
            case "notice":
                guard let notice = try? JSONDecoder().decode(RelayNotice.self, from: Data(event.data.utf8)) else {
                    continue
                }
                await handle(notice, subscription: subscription)
            case "resync":
                await store.catchUp()
            case "reauth":
                return
            default:
                break
            }
        }
    }

    private func handle(_ notice: RelayNotice, subscription: String) async {
        Self.log.info("Notice \(notice.type, privacy: .public)")
        guard notice.type.hasPrefix(Self.lifecyclePrefix) else {
            await store.handlePush(type: notice.type, subject: notice.subject, resource: notice.resource)
            return
        }
        // Google tells the subscription's owner when it is about to expire or
        // has stopped. Errors here are retried at the next connection.
        switch notice.type.dropFirst(Self.lifecyclePrefix.count) {
        case "expirationReminder":
            try? await subscriptions.renew(subscription)
        case "suspended":
            try? await subscriptions.reactivate(subscription)
        default:
            break
        }
    }
}
