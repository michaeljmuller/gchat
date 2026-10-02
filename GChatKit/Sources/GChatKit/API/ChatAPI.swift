import Foundation

/// The Chat operations the app needs. `ChatAPI` is the real implementation.
public protocol ChatService: Sendable {
    func listSpaces() async throws -> [Space]
    /// Returns one page, newest first. `after` limits it to messages created later.
    func listMessages(in space: String, pageSize: Int, pageToken: String?, after: Date?) async throws -> MessagePage
    func sendMessage(_ text: String, to space: String) async throws -> Message
    func listMembers(of space: String) async throws -> [Membership]
    func readState(for space: String) async throws -> SpaceReadState
    func markRead(space: String, at time: Date) async throws
}

public struct ChatAPI: ChatService {
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

    public func listMessages(
        in space: String, pageSize: Int, pageToken: String?, after: Date?
    ) async throws -> MessagePage {
        struct Page: Decodable {
            var messages: [Message]?
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
        return MessagePage(messages: page.messages ?? [], nextPageToken: token)
    }

    public func sendMessage(_ text: String, to space: String) async throws -> Message {
        let body = try JSONEncoder().encode(["text": text])
        return try await client.send("POST", url("\(space)/messages"), body: body)
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
