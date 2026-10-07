import Foundation

public protocol AccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

public protocol IdentityTokenProviding: Sendable {
    /// A Google ID token that stays valid for at least `minimumValidity` seconds.
    func idToken(minimumValidity: TimeInterval) async throws -> String
}

/// Holds the OAuth tokens for the signed-in account and refreshes them as needed.
public actor AuthSession: AccessTokenProviding, IdentityTokenProviding {
    public nonisolated let config: OAuthConfig
    private let store: any TokenStore
    private let urlSession: URLSession
    private var tokens: TokenSet?
    private var refreshTask: Task<TokenSet, Error>?

    public init(config: OAuthConfig, store: any TokenStore, urlSession: URLSession = .shared) {
        self.config = config
        self.store = store
        self.urlSession = urlSession
        self.tokens = store.load()
    }

    public var isSignedIn: Bool { tokens != nil }

    /// Finishes sign-in from the URL Google redirected to.
    public func completeSignIn(callbackURL: URL, expectedState: String, verifier: String) async throws {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw AuthError.denied(error) }
        guard value("state") == expectedState else { throw AuthError.stateMismatch }
        guard let code = value("code") else { throw AuthError.denied("no authorization code returned") }

        let response = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
        ])
        guard let refreshToken = response.refreshToken else {
            throw AuthError.tokenExchangeFailed("no refresh token returned")
        }
        let granted = Set((response.scope ?? "").split(separator: " ").map(String.init))
        let missing = OAuthConfig.chatScopes.filter { !granted.contains($0) }
        guard missing.isEmpty else { throw AuthError.missingScopes(missing) }

        let tokens = TokenSet(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiry: Date().addingTimeInterval(response.expiresIn),
            idToken: response.idToken
        )
        self.tokens = tokens
        store.save(tokens)
    }

    public func idToken(minimumValidity: TimeInterval = 600) async throws -> String {
        guard let tokens else { throw AuthError.reauthRequired }
        if let idToken = tokens.idToken, tokens.expiry.timeIntervalSinceNow > minimumValidity {
            return idToken
        }
        // Google issues a new ID token with each refreshed access token.
        guard let idToken = try await refresh(using: tokens.refreshToken).idToken else {
            throw AuthError.tokenExchangeFailed("Google returned no ID token")
        }
        return idToken
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens else { throw AuthError.reauthRequired }
        if !forceRefresh, tokens.expiry.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        return try await refresh(using: tokens.refreshToken).accessToken
    }

    public func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        store.clear()
    }

    /// Concurrent callers share one refresh request.
    private func refresh(using refreshToken: String) async throws -> TokenSet {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [config] in
            let response = try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": config.clientID,
            ])
            return TokenSet(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? refreshToken,
                expiry: Date().addingTimeInterval(response.expiresIn),
                idToken: response.idToken
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            tokens = refreshed
            store.save(refreshed)
            return refreshed
        } catch AuthError.reauthRequired {
            tokens = nil
            store.clear()
            throw AuthError.reauthRequired
        }
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var expiresIn: TimeInterval
        var refreshToken: String?
        var scope: String?
        var idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
            case idToken = "id_token"
        }
    }

    private struct TokenErrorResponse: Decodable {
        var error: String
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func requestToken(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: OAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(parameters).utf8)

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        }
        let failure = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
        if failure?.error == "invalid_grant" { throw AuthError.reauthRequired }
        throw AuthError.tokenExchangeFailed(
            failure.map { $0.errorDescription ?? $0.error } ?? "HTTP \(status)"
        )
    }

    static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }
}
