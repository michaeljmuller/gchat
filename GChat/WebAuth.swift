import AppKit
import AuthenticationServices

/// Runs the Google sign-in page in the system authentication sheet.
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Cancelled: Error {
        case cancelled
    }

    private var session: ASWebAuthenticationSession?

    @MainActor
    func authenticate(url: URL, scheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = Self.makeSession(url: url, scheme: scheme, continuation: continuation)
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
            }
        }
    }

    /// Not main-actor isolated, because the completion handler runs on another thread.
    private nonisolated static func makeSession(
        url: URL, scheme: String, continuation: CheckedContinuation<URL, Error>
    ) -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
            if let callback {
                continuation.resume(returning: callback)
            } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                continuation.resume(throwing: Cancelled.cancelled)
            } else {
                continuation.resume(throwing: error ?? URLError(.unknown))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
