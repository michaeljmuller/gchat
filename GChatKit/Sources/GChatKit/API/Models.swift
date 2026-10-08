import Foundation

public struct Space: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case space = "SPACE"
        case groupChat = "GROUP_CHAT"
        case directMessage = "DIRECT_MESSAGE"
        case unknown
    }

    /// Resource name, for example "spaces/AAAA1234".
    public var name: String
    public var spaceType: String?
    public var displayName: String?
    public var lastActiveTime: Date?
    public var singleUserBotDm: Bool?
    public var spaceThreadingState: String?

    public var id: String { name }
    public var kind: Kind { spaceType.flatMap(Kind.init(rawValue:)) ?? .unknown }

    /// The chat that Google Meet creates for a calendar event. The API has no
    /// flag for these. In practice they are the named spaces without threading;
    /// spaces that people create are threaded.
    public var isMeetingChat: Bool {
        kind == .space && spaceThreadingState == "UNTHREADED_MESSAGES"
    }

    public init(
        name: String, spaceType: String? = nil, displayName: String? = nil,
        lastActiveTime: Date? = nil, singleUserBotDm: Bool? = nil, spaceThreadingState: String? = nil
    ) {
        self.name = name
        self.spaceType = spaceType
        self.displayName = displayName
        self.lastActiveTime = lastActiveTime
        self.singleUserBotDm = singleUserBotDm
        self.spaceThreadingState = spaceThreadingState
    }
}

public struct User: Codable, Hashable, Sendable {
    /// Resource name, for example "users/1234567890".
    public var name: String
    public var displayName: String?
    public var type: String?

    public var isBot: Bool { type == "BOT" }

    public init(name: String, displayName: String? = nil, type: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.type = type
    }
}

public struct Attachment: Codable, Hashable, Sendable {
    public struct DriveDataRef: Codable, Hashable, Sendable {
        public var driveFileId: String?
    }

    public struct DataRef: Codable, Hashable, Sendable {
        public var resourceName: String?
    }

    public var name: String?
    public var contentName: String?
    public var contentType: String?
    public var downloadUri: String?
    public var driveDataRef: DriveDataRef?
    /// Set for files uploaded to Chat. The file can then be downloaded through the API.
    public var attachmentDataRef: DataRef?

    /// An image uploaded to Chat, which can be downloaded and shown inline.
    public var isDownloadableImage: Bool {
        attachmentDataRef?.resourceName != nil && (contentType ?? "").hasPrefix("image/")
    }

    /// A link that opens the attachment in the browser.
    public var url: URL? {
        if let id = driveDataRef?.driveFileId {
            return URL(string: "https://drive.google.com/open?id=\(id)")
        }
        return downloadUri.flatMap(URL.init(string:))
    }
}

public struct Annotation: Codable, Hashable, Sendable {
    public struct UserMention: Codable, Hashable, Sendable {
        public var user: User?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            user = container.lenient(User.self, forKey: .user)
        }
    }

    public var type: String?
    public var startIndex: Int?
    public var length: Int?
    public var userMention: UserMention?
}

public struct Message: Codable, Identifiable, Hashable, Sendable {
    public struct ThreadRef: Codable, Hashable, Sendable {
        public var name: String?
    }

    /// Resource name, for example "spaces/AAAA1234/messages/BBBB.BBBB".
    public var name: String
    public var sender: User?
    public var createTime: Date?
    public var text: String?
    public var formattedText: String?
    public var thread: ThreadRef?
    public var threadReply: Bool?
    public var attachment: [Attachment]?
    public var annotations: [Annotation]?

    public var id: String { name }

    /// The API sometimes returns a sender without a resource name. Such a
    /// sender is dropped, so that the message still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sender = container.lenient(User.self, forKey: .sender)
        createTime = try container.decodeIfPresent(Date.self, forKey: .createTime)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        formattedText = try container.decodeIfPresent(String.self, forKey: .formattedText)
        thread = try container.decodeIfPresent(ThreadRef.self, forKey: .thread)
        threadReply = try container.decodeIfPresent(Bool.self, forKey: .threadReply)
        attachment = try container.decodeIfPresent([Attachment].self, forKey: .attachment)
        annotations = try container.decodeIfPresent([Annotation].self, forKey: .annotations)
    }

    public init(
        name: String, sender: User? = nil, createTime: Date? = nil, text: String? = nil,
        formattedText: String? = nil, attachment: [Attachment]? = nil,
        annotations: [Annotation]? = nil
    ) {
        self.name = name
        self.sender = sender
        self.createTime = createTime
        self.text = text
        self.formattedText = formattedText
        self.attachment = attachment
        self.annotations = annotations
    }

    /// The text with Chat markup when the server provided it.
    public var markup: String { formattedText ?? text ?? "" }

    /// Maps each mentioned user's resource name to the "@Name" shown in the plain text.
    public var mentionNames: [String: String] {
        guard let text, let annotations else { return [:] }
        let units = Array(text.utf16)
        var names: [String: String] = [:]
        for annotation in annotations where annotation.type == "USER_MENTION" {
            guard let user = annotation.userMention?.user?.name,
                  let start = annotation.startIndex, let length = annotation.length,
                  start >= 0, length > 0, start + length <= units.count
            else { continue }
            names[user] = String(decoding: units[start..<start + length], as: UTF16.self)
        }
        return names
    }
}

extension KeyedDecodingContainer {
    /// A value that is nil when it is absent or cannot be decoded.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// An array element that is nil when it cannot be decoded, so that one bad
/// element does not fail the whole array.
struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    var error: Error?

    init(from decoder: Decoder) throws {
        do {
            value = try Value(from: decoder)
        } catch {
            self.error = error
        }
    }
}

public struct Membership: Codable, Hashable, Sendable {
    public var name: String?
    public var member: User?
}

public struct SpaceReadState: Codable, Hashable, Sendable {
    public var name: String?
    public var lastReadTime: Date?

    public init(name: String? = nil, lastReadTime: Date? = nil) {
        self.name = name
        self.lastReadTime = lastReadTime
    }
}

public struct MessagePage: Sendable {
    /// Newest first, as the API returns them.
    public var messages: [Message]
    public var nextPageToken: String?

    public init(messages: [Message], nextPageToken: String? = nil) {
        self.messages = messages
        self.nextPageToken = nextPageToken
    }
}

public struct Profile: Codable, Hashable, Sendable {
    /// Chat user resource name, for example "users/1234567890".
    public var user: String
    public var displayName: String?
    public var photoURL: URL?
    public var email: String?

    public init(user: String, displayName: String? = nil, photoURL: URL? = nil, email: String? = nil) {
        self.user = user
        self.displayName = displayName
        self.photoURL = photoURL
        self.email = email
    }
}
