import CryptoKit
import Foundation

public enum AuthError: Error, LocalizedError, Equatable {
    case invalidClientID
    case stateMismatch
    case denied(String)
    case missingScopes([String])
    case tokenExchangeFailed(String)
    /// The refresh token is missing or no longer valid; the user has to sign in again.
    case reauthRequired

    public var errorDescription: String? {
        switch self {
        case .invalidClientID:
            "The client ID should look like 1234-abcd.apps.googleusercontent.com."
        case .stateMismatch:
            "The sign-in response did not match the request. Try again."
        case .denied(let reason):
            "Google refused the sign-in: \(reason)"
        case .missingScopes(let scopes):
            "These permissions were not granted: \(scopes.joined(separator: ", ")). Sign in again and allow all of them."
        case .tokenExchangeFailed(let message):
            "Could not get a token from Google: \(message)"
        case .reauthRequired:
            "Your sign-in has expired. Sign in again."
        }
    }
}

/// OAuth settings for an iOS-type Google OAuth client. That client type has no
/// secret and redirects to a custom URL scheme built from the reversed client ID.
public struct OAuthConfig: Sendable, Equatable {
    public static let chatScopes = [
        "https://www.googleapis.com/auth/chat.spaces.readonly",
        "https://www.googleapis.com/auth/chat.spaces.create",
        "https://www.googleapis.com/auth/chat.messages",
        "https://www.googleapis.com/auth/chat.memberships.readonly",
        "https://www.googleapis.com/auth/chat.users.readstate",
        "https://www.googleapis.com/auth/directory.readonly",
    ]
    public static let scopes = chatScopes + ["openid", "email", "profile"]

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let clientIDSuffix = ".apps.googleusercontent.com"

    public let clientID: String

    public init(clientID: String) throws {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(Self.clientIDSuffix),
              trimmed.count > Self.clientIDSuffix.count,
              !trimmed.contains(where: { $0.isWhitespace || $0 == "/" || $0 == ":" })
        else { throw AuthError.invalidClientID }
        self.clientID = trimmed
    }

    public var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public var redirectURI: String {
        "\(redirectScheme):/oauth2redirect"
    }

    public func authorizationURL(state: String, challenge: String) -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }
}

public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        self.init(verifier: Data(bytes).base64URLEncodedString())
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
