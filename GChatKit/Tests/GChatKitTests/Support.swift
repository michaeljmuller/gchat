import Foundation
@testable import GChatKit

/// Answers every request of a URLSession from a closure.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLProtocol receives the body as a stream.
    var bodyString: String {
        if let httpBody { return String(decoding: httpBody, as: UTF8.self) }
        guard let stream = httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }

    var values: [Value] {
        lock.withLock { storage }
    }
}

struct FixedToken: AccessTokenProviding {
    func accessToken(forceRefresh: Bool) async throws -> String {
        forceRefresh ? "fresh" : "stale"
    }
}

final class FakeChat: ChatService, @unchecked Sendable {
    struct State {
        var spaces: [Space] = []
        var messages: [String: [Message]] = [:]
        var readTimes: [String: Date] = [:]
        var members: [String: [Membership]] = [:]
        var sendFails = false
        /// Every conversation list request answers 429 while this is set.
        var throttled = false
        var listCalls = 0
        var markedRead: [String] = []
        /// Direct messages that exist on the server but have no messages, keyed by user.
        var existingDMs: [String: Space] = [:]
        var created: [String] = []
    }

    private let lock = NSLock()
    private var state = State()

    func update<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock { try body(&state) }
    }

    var markedRead: [String] { update { $0.markedRead } }

    func listSpaces() async throws -> [Space] {
        try update { state in
            state.listCalls += 1
            if state.throttled { throw APIError(status: 429, message: "Too many requests", code: "RESOURCE_EXHAUSTED") }
            return state.spaces
        }
    }

    func listMessages(in space: String, pageSize: Int, pageToken: String?, after: Date?) async throws -> MessagePage {
        let all = update { $0.messages[space] ?? [] }
        let matching = all
            .filter { after == nil || $0.createTime! > after! }
            .sorted { $0.createTime! > $1.createTime! }
        return MessagePage(messages: matching)
    }

    func sendMessage(_ text: String, to space: String) async throws -> Message {
        try update { state in
            if state.sendFails { throw APIError(status: 500, message: "Server error") }
            let message = Message(
                name: "\(space)/messages/sent\(state.messages[space, default: []].count)",
                sender: User(name: "users/me-id"), createTime: Date(), text: text)
            state.messages[space, default: []].append(message)
            return message
        }
    }

    func getMessage(_ name: String) async throws -> Message {
        let found = update { state in state.messages.values.joined().first { $0.name == name } }
        guard let found else { throw APIError(status: 404, message: "Not found") }
        return found
    }

    func listMembers(of space: String) async throws -> [Membership] {
        update { $0.members[space] ?? [] }
    }

    func readState(for space: String) async throws -> SpaceReadState {
        SpaceReadState(lastReadTime: update { $0.readTimes[space] })
    }

    func markRead(space: String, at time: Date) async throws {
        update {
            $0.readTimes[space] = time
            $0.markedRead.append(space)
        }
    }

    func findDirectMessage(with user: String) async throws -> Space? {
        update { $0.existingDMs[user] }
    }

    func createDirectMessage(with user: String) async throws -> Space {
        update { state in
            state.created.append(user)
            return Space(name: "spaces/new-\(state.created.count)", spaceType: "DIRECT_MESSAGE")
        }
    }

    func downloadAttachment(_ resourceName: String) async throws -> Data {
        Data(resourceName.utf8)
    }

    func createGroupChat(with users: [String]) async throws -> Space {
        update { state in
            state.created.append(users.joined(separator: "+"))
            return Space(name: "spaces/new-\(state.created.count)", spaceType: "GROUP_CHAT")
        }
    }
}

struct FakePeople: ProfileService {
    var annName = "Ann Example"
    /// Simulates an organization where the People API returns no names for other users.
    var hidesNames = false

    func me() async throws -> Profile {
        Profile(user: "users/me-id", displayName: "Me")
    }

    func profile(for user: String) async throws -> Profile {
        if user == "users/gone" { throw APIError(status: 404, message: "Not found", code: "NOT_FOUND") }
        if hidesNames { return Profile(user: user) }
        return Profile(user: user, displayName: user == "users/ann" ? annName : "Someone Else")
    }

    func listDirectory() async throws -> [Profile] {
        if hidesNames { throw APIError(status: 403, message: "Directory sharing disabled", code: "PERMISSION_DENIED") }
        return [
            Profile(user: "users/zed", displayName: "Zed Example"),
            Profile(user: "users/me-id", displayName: "Me"),
            Profile(user: "users/bob", displayName: "Bob Example"),
            Profile(user: "users/ann", displayName: annName),
        ]
    }
}

/// Waits for work the store started in the background.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}


struct FixedIdentity: IdentityTokenProviding {
    func idToken(minimumValidity: TimeInterval) async throws -> String { "id-token" }
}

/// Workspace Events subscriptions kept in memory.
final class FakeEvents: EventSubscriptionService, @unchecked Sendable {
    struct State {
        var subscriptions: [String: EventSubscription] = [:]
        /// When set, create answers 409 as Google does for a second subscription.
        var createConflicts = false
        var calls: [String] = []
    }

    private let lock = NSLock()
    private var state = State()

    func update<T>(_ body: (inout State) throws -> T) rethrows -> T {
        try lock.withLock { try body(&state) }
    }

    var calls: [String] { update { $0.calls } }

    func create(topic: String) async throws -> EventSubscription {
        try update { state in
            state.calls.append("create")
            if state.createConflicts {
                throw APIError(status: 409, message: "Subscription already exists", code: "ALREADY_EXISTS")
            }
            let subscription = EventSubscription(
                name: "subscriptions/new-\(state.subscriptions.count + 1)", state: "ACTIVE",
                expireTime: Date().addingTimeInterval(7 * 86400), pubsubTopic: topic)
            state.subscriptions[subscription.name] = subscription
            return subscription
        }
    }

    func get(_ name: String) async throws -> EventSubscription {
        try update { state in
            state.calls.append("get")
            guard let subscription = state.subscriptions[name] else {
                throw APIError(status: 404, message: "Not found")
            }
            return subscription
        }
    }

    func findExisting() async throws -> EventSubscription? {
        update { state in
            state.calls.append("find")
            return state.subscriptions.values.first
        }
    }

    func renew(_ name: String) async throws {
        update { $0.calls.append("renew") }
    }

    func reactivate(_ name: String) async throws {
        update { $0.calls.append("reactivate") }
    }

    func delete(_ name: String) async throws {
        update { state in
            state.calls.append("delete")
            state.subscriptions[name] = nil
            state.createConflicts = false
        }
    }
}
