import Foundation
import Security

public struct TokenSet: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiry: Date

    public init(accessToken: String, refreshToken: String, expiry: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiry = expiry
    }
}

public protocol TokenStore: Sendable {
    func load() -> TokenSet?
    func save(_ tokens: TokenSet)
    func clear()
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "default"

    public static let label = "GChat Google sign-in"
    public static let comment = """
        Keeps GChat signed in to Google Chat. Holds the sign-in tokens Google issued to GChat, \
        not your Google password. Deleting this item signs GChat out.
        """

    public init(service: String = "org.themullers.gchat.oauth") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> TokenSet? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    public func save(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        // The label is the name macOS shows in its permission prompt and in Keychain Access.
        let details: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: Self.label,
            kSecAttrComment as String: Self.comment,
        ]
        let status = SecItemUpdate(query as CFDictionary, details as CFDictionary)
        guard status != errSecSuccess else { return }
        // Not found, or an item left by a differently signed build that this one
        // may not modify: replace it.
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query.merging(details) { $1 } as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: TokenSet?

    public init(_ tokens: TokenSet? = nil) {
        self.tokens = tokens
    }

    public func load() -> TokenSet? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: TokenSet) {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() {
        lock.withLock { tokens = nil }
    }
}
