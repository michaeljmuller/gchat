import Foundation

/// One item from the relay's event stream. See docs/api-contract.md.
public struct RelayEvent: Equatable, Sendable {
    public var event: String
    public var data: String
}

/// A notice that something changed in Google Chat. It holds identifiers only.
public struct RelayNotice: Codable, Equatable, Sendable {
    /// For example "google.workspace.chat.message.v1.created".
    public var type: String
    /// For example "//chat.googleapis.com/spaces/AAAA".
    public var subject: String
    /// For example "spaces/AAAA/messages/BBBB".
    public var resource: String?
    public var time: String?
}

/// Reads the relay's stream line by line.
///
/// The stream is in the server-sent events format, where an empty line ends
/// each event. URLSession's line reader drops empty lines, so this parser does
/// not wait for one. The relay sends every event as one "event:" line followed
/// by one "data:" line, and the parser emits the event at the data line.
public struct RelayStreamParser: Sendable {
    private var event: String?

    public init() {}

    public mutating func feed(_ line: String) -> RelayEvent? {
        // Lines that start with a colon are keepalive comments.
        guard !line.isEmpty, !line.hasPrefix(":"), let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let field = line[..<colon]
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "event":
            event = String(value)
            return nil
        case "data":
            defer { event = nil }
            return RelayEvent(event: event ?? "message", data: String(value))
        default:
            return nil
        }
    }
}
