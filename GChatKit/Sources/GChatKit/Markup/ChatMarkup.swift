import Foundation

/// Converts Google Chat text markup into an AttributedString.
///
/// Handles *bold*, _italic_, ~strikethrough~, `code`, ``` code blocks ```,
/// <url|label> links, bare URLs, <users/123> mentions and "* " bullets.
public enum ChatMarkup {
    public static func render(
        _ source: String, mentionName: (String) -> String? = { _ in nil }
    ) -> AttributedString {
        var output = AttributedString()
        let parts = source.components(separatedBy: "```")
        for (index, part) in parts.enumerated() {
            // Odd parts sit between fences. A final odd part has no closing fence.
            let isCode = index % 2 == 1 && index < parts.count - 1
            if isCode {
                var block = AttributedString(part.trimmingCharacters(in: .newlines))
                block.inlinePresentationIntent = .code
                output += block
            } else {
                let text = (index % 2 == 1 ? "```" : "") + part
                output += inline(bulleted(text), intent: [], mentionName: mentionName)
            }
        }
        return output
    }

    private static let delimiters: [Character: InlinePresentationIntent] = [
        "*": .stronglyEmphasized,
        "_": .emphasized,
        "~": .strikethrough,
    ]

    private static func bulleted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("* ") ? "• " + $0.dropFirst(2) : String($0) }
            .joined(separator: "\n")
    }

    private static func inline(
        _ text: String, intent: InlinePresentationIntent, mentionName: (String) -> String?
    ) -> AttributedString {
        let chars = Array(text)
        var output = AttributedString()
        var plain = ""
        var index = 0

        func flush() {
            guard !plain.isEmpty else { return }
            output += linkified(plain, intent: intent)
            plain = ""
        }

        while index < chars.count {
            let char = chars[index]

            if char == "`", let end = chars[(index + 1)...].firstIndex(of: "`"), end > index + 1 {
                flush()
                var code = AttributedString(String(chars[index + 1..<end]))
                code.inlinePresentationIntent = intent.union(.code)
                output += code
                index = end + 1
                continue
            }

            if char == "<", let end = chars[(index + 1)...].firstIndex(of: ">"),
               let piece = angle(String(chars[index + 1..<end]), intent: intent, mentionName: mentionName) {
                flush()
                output += piece
                index = end + 1
                continue
            }

            if let style = delimiters[char], canOpen(chars, at: index),
               let end = closing(chars, delimiter: char, after: index) {
                flush()
                output += inline(
                    String(chars[index + 1..<end]), intent: intent.union(style), mentionName: mentionName)
                index = end + 1
                continue
            }

            plain.append(char)
            index += 1
        }
        flush()
        return output
    }

    private static func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber
    }

    private static func canOpen(_ chars: [Character], at index: Int) -> Bool {
        if index > 0, isWordCharacter(chars[index - 1]) { return false }
        guard index + 1 < chars.count else { return false }
        return !chars[index + 1].isWhitespace && chars[index + 1] != chars[index]
    }

    private static func closing(_ chars: [Character], delimiter: Character, after start: Int) -> Int? {
        var index = start + 2
        while index < chars.count {
            if chars[index].isNewline { return nil }
            if chars[index] == delimiter, !chars[index - 1].isWhitespace,
               index + 1 == chars.count || !isWordCharacter(chars[index + 1]) {
                return index
            }
            index += 1
        }
        return nil
    }

    /// The content of <...>: a mention or a link. Anything else is left as typed.
    private static func angle(
        _ token: String, intent: InlinePresentationIntent, mentionName: (String) -> String?
    ) -> AttributedString? {
        if token.hasPrefix("users/") {
            let name = token == "users/all" ? "@all" : (mentionName(token) ?? "@mention")
            var mention = AttributedString(name)
            mention.inlinePresentationIntent = intent.union(.stronglyEmphasized)
            return mention
        }
        guard token.contains("://") || token.hasPrefix("mailto:") else { return nil }
        let pieces = token.split(separator: "|", maxSplits: 1).map(String.init)
        guard let target = pieces.first, let url = URL(string: target) else { return nil }
        var link = AttributedString(pieces.count > 1 ? pieces[1] : target)
        link.link = url
        if !intent.isEmpty { link.inlinePresentationIntent = intent }
        return link
    }

    private static func linkified(_ text: String, intent: InlinePresentationIntent) -> AttributedString {
        func styled(_ string: some StringProtocol) -> AttributedString {
            var piece = AttributedString(String(string))
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            return piece
        }
        guard text.contains("://"), let pattern = try? Regex(#"https?://[^\s<>]+"#) else {
            return styled(text)
        }
        var output = AttributedString()
        var cursor = text.startIndex
        for match in text.matches(of: pattern) {
            var end = match.range.upperBound
            while end > match.range.lowerBound, ".,;:!?)".contains(text[text.index(before: end)]) {
                end = text.index(before: end)
            }
            let target = text[match.range.lowerBound..<end]
            guard let url = URL(string: String(target)) else { continue }
            output += styled(text[cursor..<match.range.lowerBound])
            var link = styled(target)
            link.link = url
            output += link
            cursor = end
        }
        output += styled(text[cursor...])
        return output
    }
}
