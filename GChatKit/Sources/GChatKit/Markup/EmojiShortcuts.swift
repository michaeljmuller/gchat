import Foundation

/// Text that the composer changes to emoji as the person types: emoticons
/// such as ":)" and short codes such as ":thumbsup:", as Google Chat does.
public enum EmojiShortcuts {
    /// Emoticons that are changed when a space, a line break or the end of
    /// the message follows. Left out: ones that are also ordinary text, such
    /// as "B)" at the end of "(see B)".
    public static let emoticons: [String: String] = [
        ":)": "🙂", ":-)": "🙂", "(:": "🙂",
        ":(": "🙁", ":-(": "🙁",
        ":D": "😀", ":-D": "😀",
        ";)": "😉", ";-)": "😉",
        ":P": "😛", ":-P": "😛", ":p": "😛", ":-p": "😛",
        ":O": "😮", ":-O": "😮", ":o": "😮",
        ":'(": "😢",
        ":|": "😐", ":-|": "😐",
        ":/": "😕", ":-/": "😕",
        ":*": "😘", ":-*": "😘",
        "^_^": "😊",
        "<3": "❤️", "</3": "💔",
    ]

    /// Short codes, without the colons. Changed when the closing colon is typed.
    public static let shortCodes: [String: String] = [
        "+1": "👍", "thumbsup": "👍", "thumbs_up": "👍", "-1": "👎", "thumbsdown": "👎", "thumbs_down": "👎",
        "ok_hand": "👌", "clap": "👏", "pray": "🙏", "wave": "👋", "muscle": "💪", "raised_hands": "🙌",
        "point_up": "☝️", "point_right": "👉", "point_left": "👈", "v": "✌️", "crossed_fingers": "🤞",
        "smile": "😄", "smiley": "😃", "grin": "😁", "grinning": "😀", "slightly_smiling_face": "🙂",
        "blush": "😊", "wink": "😉", "joy": "😂", "rofl": "🤣", "laughing": "😆", "sweat_smile": "😅",
        "heart_eyes": "😍", "kissing_heart": "😘", "yum": "😋", "stuck_out_tongue": "😛", "sunglasses": "😎",
        "thinking": "🤔", "neutral_face": "😐", "expressionless": "😑", "unamused": "😒", "roll_eyes": "🙄",
        "confused": "😕", "worried": "😟", "frowning": "🙁", "cry": "😢", "sob": "😭", "scream": "😱",
        "open_mouth": "😮", "astonished": "😲", "flushed": "😳", "angry": "😠", "rage": "😡",
        "sleeping": "😴", "sleepy": "😪", "mask": "😷", "nerd_face": "🤓", "partying_face": "🥳",
        "upside_down_face": "🙃", "zipper_mouth_face": "🤐", "shushing_face": "🤫", "hugs": "🤗",
        "skull": "💀", "poop": "💩", "see_no_evil": "🙈", "shrug": "🤷", "facepalm": "🤦",
        "heart": "❤️", "broken_heart": "💔", "sparkling_heart": "💖", "fire": "🔥", "sparkles": "✨",
        "star": "⭐", "tada": "🎉", "confetti_ball": "🎊", "balloon": "🎈", "gift": "🎁", "trophy": "🏆",
        "100": "💯", "rocket": "🚀", "eyes": "👀", "zap": "⚡", "boom": "💥", "bulb": "💡",
        "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "warning": "⚠️", "question": "❓",
        "exclamation": "❗", "coffee": "☕", "beer": "🍺", "beers": "🍻", "wine_glass": "🍷", "pizza": "🍕",
        "cake": "🍰", "birthday": "🎂", "sun": "☀️", "rainbow": "🌈", "snowflake": "❄️", "dog": "🐶",
        "cat": "🐱", "unicorn": "🦄", "memo": "📝", "calendar": "📅", "phone": "📱", "computer": "💻",
    ]

    /// The emoji for a word that the person just finished, or nil. `word` is
    /// the text from the last space or line break up to the cursor.
    /// `trigger` is the character being typed: a space, a line break, or
    /// nil at the end of the message. A colon finishes a short code.
    public static func replacement(for word: String, trigger: Character?) -> String? {
        if trigger == ":" {
            guard word.hasPrefix(":"), word.count > 1 else { return nil }
            return shortCodes[String(word.dropFirst())]
        }
        if let emoji = emoticons[word] { return emoji }
        guard word.count > 2, word.hasPrefix(":"), word.hasSuffix(":") else { return nil }
        return shortCodes[String(word.dropFirst().dropLast())]
    }

    /// The first emoji in a string, for a reaction picked from the system
    /// emoji picker or typed.
    public static func firstEmoji(in text: String) -> String? {
        text.first(where: isEmoji).map(String.init)
    }

    /// True for a character that shows as an emoji. Digits and "#" are
    /// emoji only with a following presentation selector or keycap.
    public static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return scalars.count > 1 && first.properties.isEmoji
    }
}
