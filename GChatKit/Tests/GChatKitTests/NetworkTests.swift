import Foundation
import Testing
@testable import GChatKit

/// These share StubProtocol.handler, so they run one at a time.
@Suite(.serialized) struct NetworkTests {
    private let config = try! OAuthConfig(clientID: "123-abc.apps.googleusercontent.com")

    @Test func signInExchangesCodeAndStoresTokens() async throws {
        let bodies = Recorder<String>()
        StubProtocol.handler = { request in
            bodies.append(request.bodyString)
            let scope = OAuthConfig.scopes.joined(separator: " ")
            return (200, #"{"access_token":"a1","expires_in":3600,"refresh_token":"r1","scope":"\#(scope)"}"#)
        }
        let store = InMemoryTokenStore()
        let auth = AuthSession(config: config, store: store, urlSession: StubProtocol.session())
        let callback = URL(string: "\(config.redirectURI)?state=s1&code=the%2Fcode")!

        try await auth.completeSignIn(callbackURL: callback, expectedState: "s1", verifier: "v1")

        #expect(try await auth.accessToken() == "a1")
        #expect(store.load()?.refreshToken == "r1")
        let body = try #require(bodies.values.first)
        #expect(body.contains("code=the%2Fcode"))
        #expect(body.contains("code_verifier=v1"))
        #expect(body.contains("grant_type=authorization_code"))
    }

    @Test func signInRejectsWrongStateAndMissingScopes() async throws {
        StubProtocol.handler = { _ in
            (200, #"{"access_token":"a1","expires_in":3600,"refresh_token":"r1","scope":"openid"}"#)
        }
        let auth = AuthSession(config: config, store: InMemoryTokenStore(), urlSession: StubProtocol.session())
        let callback = URL(string: "\(config.redirectURI)?state=s1&code=c")!

        await #expect(throws: AuthError.stateMismatch) {
            try await auth.completeSignIn(callbackURL: callback, expectedState: "other", verifier: "v")
        }
        await #expect(throws: AuthError.missingScopes(OAuthConfig.chatScopes)) {
            try await auth.completeSignIn(callbackURL: callback, expectedState: "s1", verifier: "v")
        }
        #expect(await !auth.isSignedIn)
    }

    @Test func expiredTokenIsRefreshedOnce() async throws {
        let bodies = Recorder<String>()
        StubProtocol.handler = { request in
            bodies.append(request.bodyString)
            return (200, #"{"access_token":"a2","expires_in":3600}"#)
        }
        let store = InMemoryTokenStore(
            TokenSet(accessToken: "a1", refreshToken: "r1", expiry: Date().addingTimeInterval(-10)))
        let auth = AuthSession(config: config, store: store, urlSession: StubProtocol.session())

        async let first = auth.accessToken()
        async let second = auth.accessToken()
        #expect(try await [first, second] == ["a2", "a2"])
        #expect(try await auth.accessToken() == "a2")

        #expect(bodies.values.count == 1)
        #expect(bodies.values[0].contains("refresh_token=r1"))
        #expect(store.load() == TokenSet(accessToken: "a2", refreshToken: "r1", expiry: store.load()!.expiry))
    }

    @Test func revokedRefreshTokenSignsOut() async throws {
        StubProtocol.handler = { _ in (400, #"{"error":"invalid_grant"}"#) }
        let store = InMemoryTokenStore(
            TokenSet(accessToken: "a1", refreshToken: "r1", expiry: .distantPast))
        let auth = AuthSession(config: config, store: store, urlSession: StubProtocol.session())

        await #expect(throws: AuthError.reauthRequired) { try await auth.accessToken() }
        #expect(store.load() == nil)
    }

    @Test func clientRetriesOnceAfter401() async throws {
        let tokens = Recorder<String>()
        StubProtocol.handler = { request in
            let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
            tokens.append(header)
            return header == "Bearer fresh" ? (200, #"{"name":"spaces/A"}"#) : (401, "{}")
        }
        let client = APIClient(tokens: FixedToken(), session: StubProtocol.session())
        let space: Space = try await client.send("GET", URL(string: "https://chat.googleapis.com/v1/spaces/A")!)
        #expect(space.name == "spaces/A")
        #expect(tokens.values == ["Bearer stale", "Bearer fresh"])
    }

    @Test func clientSurfacesGoogleErrors() async throws {
        StubProtocol.handler = { _ in
            (403, #"{"error":{"code":403,"message":"Google Chat app not found.","status":"PERMISSION_DENIED"}}"#)
        }
        let client = APIClient(tokens: FixedToken(), session: StubProtocol.session())
        await #expect(throws: APIError(status: 403, message: "Google Chat app not found.", code: "PERMISSION_DENIED")) {
            let _: Space = try await client.send("GET", URL(string: "https://chat.googleapis.com/v1/spaces/A")!)
        }
    }

    @Test func listSpacesFollowsPages() async throws {
        let urls = Recorder<URL>()
        StubProtocol.handler = { request in
            urls.append(request.url!)
            if request.url!.query()!.contains("pageToken=p2") {
                return (200, #"{"spaces":[{"name":"spaces/B"}]}"#)
            }
            return (200, #"{"spaces":[{"name":"spaces/A"}],"nextPageToken":"p2"}"#)
        }
        let api = ChatAPI(client: APIClient(tokens: FixedToken(), session: StubProtocol.session()))
        #expect(try await api.listSpaces().map(\.name) == ["spaces/A", "spaces/B"])
        #expect(urls.values.count == 2)
    }

    @Test func listMessagesBuildsFilter() async throws {
        let urls = Recorder<URL>()
        StubProtocol.handler = { request in
            urls.append(request.url!)
            return (200, #"{"messages":[{"name":"spaces/A/messages/1","createTime":"2026-10-02T12:00:01Z"}],"nextPageToken":""}"#)
        }
        let api = ChatAPI(client: APIClient(tokens: FixedToken(), session: StubProtocol.session()))
        let after = try #require(RFC3339.date(from: "2026-10-02T12:00:00.5Z"))
        let page = try await api.listMessages(in: "spaces/A", pageSize: 50, pageToken: nil, after: after)

        #expect(page.messages.count == 1)
        #expect(page.nextPageToken == nil)
        let url = try #require(urls.values.first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.path == "/v1/spaces/A/messages")
        #expect(items.first { $0.name == "filter" }?.value == #"createTime > "2026-10-02T12:00:00.500000Z""#)
        #expect(items.first { $0.name == "orderBy" }?.value == "createTime desc")
    }

    @Test func attachmentsDownloadThroughTheMediaEndpoint() async throws {
        let urls = Recorder<URL>()
        StubProtocol.handler = { request in
            urls.append(request.url!)
            return (200, "file bytes")
        }
        let api = ChatAPI(client: APIClient(tokens: FixedToken(), session: StubProtocol.session()))
        let data = try await api.downloadAttachment("ABC123")
        #expect(String(decoding: data, as: UTF8.self) == "file bytes")
        #expect(urls.values.first?.absoluteString == "https://chat.googleapis.com/v1/media/ABC123?alt=media")
    }

    @Test func markReadPatchesReadState() async throws {
        let requests = Recorder<(String, String, String)>()
        StubProtocol.handler = { request in
            requests.append((request.httpMethod ?? "", request.url!.absoluteString, request.bodyString))
            return (200, "{}")
        }
        let api = ChatAPI(client: APIClient(tokens: FixedToken(), session: StubProtocol.session()))
        let time = try #require(RFC3339.date(from: "2026-10-02T12:00:00Z"))
        try await api.markRead(space: "spaces/A", at: time)

        let request = try #require(requests.values.first)
        #expect(request.0 == "PATCH")
        #expect(request.1 == "https://chat.googleapis.com/v1/users/me/spaces/A/spaceReadState?updateMask=lastReadTime")
        #expect(request.2 == #"{"lastReadTime":"2026-10-02T12:00:00.000000Z"}"#)
    }
}
