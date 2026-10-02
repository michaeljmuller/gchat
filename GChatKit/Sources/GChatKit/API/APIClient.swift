import Foundation

public struct APIError: Error, LocalizedError, Equatable {
    public var status: Int
    public var message: String
    /// Google's canonical status, for example "PERMISSION_DENIED".
    public var code: String?

    public var errorDescription: String? { message }
}

/// Sends authorized JSON requests to Google APIs.
public struct APIClient: Sendable {
    private let session: URLSession
    private let tokens: any AccessTokenProviding
    private let decoder = RFC3339.makeDecoder()

    public init(tokens: any AccessTokenProviding, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            var message: String?
            var status: String?
        }
        var error: Body
    }

    public func send<Response: Decodable>(
        _ method: String = "GET", _ url: URL, body: Data? = nil
    ) async throws -> Response {
        try decoder.decode(Response.self, from: await data(method, url, body: body))
    }

    /// The undecoded response body.
    public func data(_ method: String = "GET", _ url: URL, body: Data? = nil) async throws -> Data {
        var (data, status) = try await perform(method, url, body: body, forceRefresh: false)
        if status == 401 {
            (data, status) = try await perform(method, url, body: body, forceRefresh: true)
        }
        guard (200..<300).contains(status) else {
            let body = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error
            throw APIError(status: status, message: body?.message ?? "HTTP \(status)", code: body?.status)
        }
        return data
    }

    private func perform(
        _ method: String, _ url: URL, body: Data?, forceRefresh: Bool
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        let token = try await tokens.accessToken(forceRefresh: forceRefresh)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
