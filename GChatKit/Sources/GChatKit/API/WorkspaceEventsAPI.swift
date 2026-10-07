import Foundation

/// A Google Workspace Events subscription: Google's promise to publish events
/// about a resource to a Pub/Sub topic until the subscription expires.
public struct EventSubscription: Codable, Hashable, Sendable {
    /// Resource name, for example "subscriptions/chat-spaces-abc". Only the
    /// person who made it, Google and the relay know it.
    public var name: String
    public var state: String?
    public var expireTime: Date?
    public var targetResource: String?
    public var notificationEndpoint: Endpoint?

    public struct Endpoint: Codable, Hashable, Sendable {
        public var pubsubTopic: String?
    }

    public var pubsubTopic: String? { notificationEndpoint?.pubsubTopic }
    public var isActive: Bool { state == "ACTIVE" }
    public var isSuspended: Bool { state == "SUSPENDED" }

    public init(
        name: String, state: String? = nil, expireTime: Date? = nil, targetResource: String? = nil,
        pubsubTopic: String? = nil
    ) {
        self.name = name
        self.state = state
        self.expireTime = expireTime
        self.targetResource = targetResource
        self.notificationEndpoint = pubsubTopic.map { Endpoint(pubsubTopic: $0) }
    }
}

/// The Workspace Events operations the app needs. `WorkspaceEventsAPI` is the
/// real implementation.
public protocol EventSubscriptionService: Sendable {
    /// Makes the subscription for all Chat spaces of the signed-in person.
    func create(topic: String) async throws -> EventSubscription
    func get(_ name: String) async throws -> EventSubscription
    /// The person's existing subscription for all Chat spaces, if there is one.
    func findExisting() async throws -> EventSubscription?
    /// Extends the subscription to the longest lifetime Google allows.
    func renew(_ name: String) async throws
    func reactivate(_ name: String) async throws
    func delete(_ name: String) async throws
}

public struct WorkspaceEventsAPI: EventSubscriptionService {
    /// All spaces that the signed-in person is a member of.
    public static let allSpaces = "//chat.googleapis.com/spaces/-"
    public static let messageCreated = "google.workspace.chat.message.v1.created"
    public static let messageUpdated = "google.workspace.chat.message.v1.updated"
    public static let messageDeleted = "google.workspace.chat.message.v1.deleted"
    static let eventTypes = [messageCreated, messageUpdated, messageDeleted]

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "workspaceevents.googleapis.com"
        components.path = "/v1/\(path)"
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    /// Most calls answer with a long-running operation.
    private struct Operation: Decodable {
        var name: String?
        var done: Bool?
        var response: EventSubscription?
        var error: Status?

        struct Status: Decodable {
            var code: Int?
            var message: String?
        }
    }

    /// Waits for an operation to finish and returns the subscription in its answer.
    private func finish(_ operation: Operation) async throws -> EventSubscription? {
        var operation = operation
        var attempts = 0
        while operation.done != true, let name = operation.name, attempts < 10 {
            try await Task.sleep(for: .seconds(1))
            operation = try await client.send("GET", url(name))
            attempts += 1
        }
        if let error = operation.error {
            throw APIError(status: 500, message: error.message ?? "The operation failed", code: nil)
        }
        return operation.response
    }

    public func create(topic: String) async throws -> EventSubscription {
        struct Body: Encodable {
            struct Endpoint: Encodable { var pubsubTopic: String }
            struct Payload: Encodable { var includeResource: Bool }
            var targetResource: String
            var eventTypes: [String]
            var notificationEndpoint: Endpoint
            var payloadOptions: Payload
        }
        // includeResource is false on purpose: events must carry identifiers
        // only, never message content. See docs/design.md.
        let body = try JSONEncoder().encode(Body(
            targetResource: Self.allSpaces,
            eventTypes: Self.eventTypes,
            notificationEndpoint: .init(pubsubTopic: topic),
            payloadOptions: .init(includeResource: false)))
        let operation: Operation = try await client.send("POST", url("subscriptions"), body: body)
        guard let subscription = try await finish(operation) else {
            throw APIError(status: 500, message: "Google returned no subscription", code: nil)
        }
        return subscription
    }

    public func get(_ name: String) async throws -> EventSubscription {
        try await client.send("GET", url(name))
    }

    public func findExisting() async throws -> EventSubscription? {
        struct Page: Decodable { var subscriptions: [EventSubscription]? }
        let filter = "event_types:\"\(Self.messageCreated)\" AND target_resource=\"\(Self.allSpaces)\""
        let page: Page = try await client.send(
            "GET", url("subscriptions", [URLQueryItem(name: "filter", value: filter)]))
        return page.subscriptions?.first
    }

    public func renew(_ name: String) async throws {
        // A ttl of 0 asks for the longest lifetime: 7 days without resource data.
        let body = try JSONEncoder().encode(["ttl": "0s"])
        let operation: Operation = try await client.send(
            "PATCH", url(name, [URLQueryItem(name: "updateMask", value: "ttl")]), body: body)
        _ = try await finish(operation)
    }

    public func reactivate(_ name: String) async throws {
        let operation: Operation = try await client.send("POST", url("\(name):reactivate"), body: Data("{}".utf8))
        _ = try await finish(operation)
    }

    public func delete(_ name: String) async throws {
        let operation: Operation = try await client.send("DELETE", url(name))
        _ = try await finish(operation)
    }
}
