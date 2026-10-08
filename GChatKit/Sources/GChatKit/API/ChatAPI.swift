import Foundation
import os

/// The Chat operations the app needs. `ChatAPI` is the real implementation.
public protocol ChatService: Sendable {
    func listSpaces() async throws -> [Space]
    /// One conversation by its resource name, "spaces/A". Its type can differ
    /// from the type in the conversation list (see `ChatStore.checkListedTypes`).
    func getSpace(_ name: String) async throws -> Space
    /// Returns one page, newest first. `after` limits it to messages created later.
    func listMessages(in space: String, pageSize: Int, pageToken: String?, after: Date?) async throws -> MessagePage
    func sendMessage(_ text: String, to space: String) async throws -> Message
    /// One message by its resource name, "spaces/A/messages/B".
    func getMessage(_ name: String) async throws -> Message
    func listMembers(of space: String) async throws -> [Membership]
    func readState(for space: String) async throws -> SpaceReadState
    func markRead(space: String, at time: Date) async throws
    /// The existing direct message with a user ("users/123"), or nil when there is none.
    func findDirectMessage(with user: String) async throws -> Space?
    /// Creates a direct message with a user, or returns the existing one.
    func createDirectMessage(with user: String) async throws -> Space
    /// Creates an unnamed group chat with the given users and the signed-in user.
    func createGroupChat(with users: [String]) async throws -> Space
    /// The contents of a file uploaded to Chat, by its attachment data reference.
    func downloadAttachment(_ resourceName: String) async throws -> Data
}

public struct ChatAPI: ChatService {
    private static let log = Logger(subsystem: "org.themullers.gchat", category: "api")
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "chat.googleapis.com"
        components.path = "/v1/\(path)"
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    public func listSpaces() async throws -> [Space] {
        struct Page: Decodable {
            var spaces: [Space]?
            var nextPageToken: String?
        }
        var spaces: [Space] = []
        var token: String?
        repeat {
            var query = [URLQueryItem(name: "pageSize", value: "1000")]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let page: Page = try await client.send("GET", url("spaces", query))
            spaces += page.spaces ?? []
            token = page.nextPageToken
        } while token?.isEmpty == false
        return spaces
    }

    public func getSpace(_ name: String) async throws -> Space {
        try await client.send("GET", url(name))
    }

    public func listMessages(
        in space: String, pageSize: Int, pageToken: String?, after: Date?
    ) async throws -> MessagePage {
        struct Page: Decodable {
            var messages: [Lossy<Message>]?
            var nextPageToken: String?
        }
        var query = [
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "createTime desc"),
        ]
        if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        if let after {
            query.append(URLQueryItem(name: "filter", value: "createTime > \"\(RFC3339.string(from: after))\""))
        }
        let page: Page = try await client.send("GET", url("\(space)/messages", query))
        let token = page.nextPageToken?.isEmpty == false ? page.nextPageToken : nil
        // A message that cannot be decoded is left out, so that the rest still load.
        for error in (page.messages ?? []).compactMap(\.error) {
            Self.log.error("Skipped a message in \(space, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        return MessagePage(messages: (page.messages ?? []).compactMap(\.value), nextPageToken: token)
    }

    public func sendMessage(_ text: String, to space: String) async throws -> Message {
        let body = try JSONEncoder().encode(["text": text])
        return try await client.send("POST", url("\(space)/messages"), body: body)
    }

    public func getMessage(_ name: String) async throws -> Message {
        try await client.send("GET", url(name))
    }

    public func listMembers(of space: String) async throws -> [Membership] {
        struct Page: Decodable {
            var memberships: [Membership]?
            var nextPageToken: String?
        }
        // One page is enough: this is only used to title direct messages and group chats.
        let page: Page = try await client.send(
            "GET", url("\(space)/members", [URLQueryItem(name: "pageSize", value: "100")]))
        return page.memberships ?? []
    }

    public func findDirectMessage(with user: String) async throws -> Space? {
        do {
            return try await client.send(
                "GET", url("spaces:findDirectMessage", [URLQueryItem(name: "name", value: user)]))
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    public func createDirectMessage(with user: String) async throws -> Space {
        try await setUpSpace(type: "DIRECT_MESSAGE", users: [user])
    }

    public func createGroupChat(with users: [String]) async throws -> Space {
        try await setUpSpace(type: "GROUP_CHAT", users: users)
    }

    /// The signed-in user is added by the server and must not be listed.
    private func setUpSpace(type: String, users: [String]) async throws -> Space {
        struct Setup: Encodable {
            struct SpaceBody: Encodable { var spaceType: String }
            struct Member: Encodable {
                var name: String
                var type = "HUMAN"
            }
            struct MembershipBody: Encodable { var member: Member }
            var space: SpaceBody
            var memberships: [MembershipBody]
        }
        let body = try JSONEncoder().encode(Setup(
            space: .init(spaceType: type),
            memberships: users.map { .init(member: .init(name: $0)) }))
        return try await client.send("POST", url("spaces:setup"), body: body)
    }

    public func downloadAttachment(_ resourceName: String) async throws -> Data {
        try await client.data("GET", url("media/\(resourceName)", [URLQueryItem(name: "alt", value: "media")]))
    }

    public func readState(for space: String) async throws -> SpaceReadState {
        try await client.send("GET", url("users/me/\(space)/spaceReadState"))
    }

    public func markRead(space: String, at time: Date) async throws {
        let body = try JSONEncoder().encode(["lastReadTime": RFC3339.string(from: time)])
        let _: SpaceReadState = try await client.send(
            "PATCH",
            url("users/me/\(space)/spaceReadState", [URLQueryItem(name: "updateMask", value: "lastReadTime")]),
            body: body)
    }
}
