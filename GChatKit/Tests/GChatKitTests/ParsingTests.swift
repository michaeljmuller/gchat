import Foundation
import Testing
@testable import GChatKit

@Suite struct RFC3339Tests {
    @Test func parsesAnyFractionLength() throws {
        let whole = try #require(RFC3339.date(from: "2026-10-02T12:00:00Z"))
        #expect(RFC3339.date(from: "2026-10-02T12:00:00.5Z") == whole.addingTimeInterval(0.5))
        let micros = try #require(RFC3339.date(from: "2026-10-02T12:00:00.250000Z"))
        #expect(abs(micros.timeIntervalSince(whole) - 0.25) < 1e-6)
        let nanos = try #require(RFC3339.date(from: "2026-10-02T12:00:00.125000000Z"))
        #expect(abs(nanos.timeIntervalSince(whole) - 0.125) < 1e-6)
        #expect(RFC3339.date(from: "yesterday") == nil)
    }

    @Test func formatsWithMicroseconds() throws {
        let date = try #require(RFC3339.date(from: "2026-10-02T12:00:00.250000Z"))
        #expect(RFC3339.string(from: date) == "2026-10-02T12:00:00.250000Z")
        let whole = try #require(RFC3339.date(from: "2026-10-02T12:00:00Z"))
        #expect(RFC3339.string(from: whole) == "2026-10-02T12:00:00.000000Z")
    }
}

@Suite struct ModelTests {
    @Test func decodesSpaces() throws {
        let json = """
        {"spaces": [
          {"name": "spaces/AAA", "spaceType": "SPACE", "displayName": "Team",
           "lastActiveTime": "2026-10-01T09:30:00.123456Z"},
          {"name": "spaces/BBB", "spaceType": "DIRECT_MESSAGE", "singleUserBotDm": false},
          {"name": "spaces/CCC", "spaceType": "SOMETHING_NEW"}
        ]}
        """
        struct Page: Decodable { var spaces: [Space] }
        let spaces = try RFC3339.makeDecoder().decode(Page.self, from: Data(json.utf8)).spaces
        #expect(spaces.map(\.kind) == [.space, .directMessage, .unknown])
        #expect(spaces[0].displayName == "Team")
        #expect(spaces[0].lastActiveTime != nil)
        #expect(spaces[1].lastActiveTime == nil)
    }

    @Test func decodesMessageWithMentionAndAttachment() throws {
        let json = """
        {"name": "spaces/AAA/messages/m1",
         "sender": {"name": "users/111", "type": "HUMAN"},
         "createTime": "2026-10-01T09:30:00.5Z",
         "text": "Hi @Ann Example, see this",
         "formattedText": "Hi <users/ann>, see this",
         "thread": {"name": "spaces/AAA/threads/t1"},
         "annotations": [{"type": "USER_MENTION", "startIndex": 3, "length": 12,
                          "userMention": {"user": {"name": "users/ann", "type": "HUMAN"}}}],
         "attachment": [{"name": "spaces/AAA/messages/m1/attachments/a1",
                         "contentName": "plan.pdf", "contentType": "application/pdf",
                         "driveDataRef": {"driveFileId": "FILE1"}}]}
        """
        let message = try RFC3339.makeDecoder().decode(Message.self, from: Data(json.utf8))
        #expect(message.sender?.name == "users/111")
        #expect(message.mentionNames == ["users/ann": "@Ann Example"])
        #expect(message.markup == "Hi <users/ann>, see this")
        #expect(message.attachment?.first?.url?.absoluteString == "https://drive.google.com/open?id=FILE1")
    }
}

@Suite struct MarkupTests {
    private func runs(_ text: AttributedString) -> [(String, InlinePresentationIntent?, URL?)] {
        text.runs.map { (String(text[$0.range].characters), $0.inlinePresentationIntent, $0.link) }
    }

    @Test func plainTextIsUnchanged() {
        let text = ChatMarkup.render("2 * 3 = 6, a_b_c, x < y > z")
        #expect(String(text.characters) == "2 * 3 = 6, a_b_c, x < y > z")
        #expect(text.runs.count == 1)
    }

    @Test func inlineStyles() {
        let parts = runs(ChatMarkup.render("a *bold* _it_ ~gone~ `x*y`"))
        #expect(parts.map(\.0) == ["a ", "bold", " ", "it", " ", "gone", " ", "x*y"])
        #expect(parts[1].1 == .stronglyEmphasized)
        #expect(parts[3].1 == .emphasized)
        #expect(parts[5].1 == .strikethrough)
        #expect(parts[7].1 == .code)
    }

    @Test func nestedStyles() {
        let parts = runs(ChatMarkup.render("*bold _both_*"))
        #expect(parts.map(\.0) == ["bold ", "both"])
        #expect(parts[1].1 == [.stronglyEmphasized, .emphasized])
    }

    @Test func linksAndMentions() {
        let text = ChatMarkup.render(
            "<https://example.com/a|the doc> and https://example.org/b. Hi <users/1>"
        ) { $0 == "users/1" ? "@Ann" : nil }
        let parts = runs(text)
        #expect(parts.map(\.0) == ["the doc", " and ", "https://example.org/b", ". Hi ", "@Ann"])
        #expect(parts[0].2 == URL(string: "https://example.com/a"))
        #expect(parts[2].2 == URL(string: "https://example.org/b"))
        #expect(parts[4].1 == .stronglyEmphasized)
    }

    @Test func codeBlocksAndBullets() {
        let text = ChatMarkup.render("* one\n* two\n```\nlet *x* = 1\n```")
        let parts = runs(text)
        #expect(parts.map(\.0) == ["• one\n• two\n", "let *x* = 1"])
        #expect(parts[1].1 == .code)
        #expect(String(ChatMarkup.render("open ``` fence").characters) == "open ``` fence")
    }
}

@Suite struct OAuthConfigTests {
    @Test func redirectUsesReversedClientID() throws {
        let config = try OAuthConfig(clientID: " 123-abc.apps.googleusercontent.com\n")
        #expect(config.clientID == "123-abc.apps.googleusercontent.com")
        #expect(config.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func rejectsOtherStrings() {
        #expect(throws: AuthError.invalidClientID) { try OAuthConfig(clientID: "hello") }
        #expect(throws: AuthError.invalidClientID) { try OAuthConfig(clientID: ".apps.googleusercontent.com") }
    }

    @Test func authorizationURLCarriesPKCEAndScopes() throws {
        let config = try OAuthConfig(clientID: "123-abc.apps.googleusercontent.com")
        let url = config.authorizationURL(state: "s1", challenge: "c1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.host == "accounts.google.com")
        #expect(value("code_challenge") == "c1")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == "s1")
        #expect(value("scope")?.contains("auth/chat.messages") == true)
    }

    @Test func pkceMatchesRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE().verifier.count == 43)
    }

    @Test func unreadRule() {
        let now = Date()
        #expect(UnreadRule.isUnread(lastActive: now, lastRead: now.addingTimeInterval(-5)))
        #expect(!UnreadRule.isUnread(lastActive: now, lastRead: now))
        #expect(!UnreadRule.isUnread(lastActive: now, lastRead: nil))
        #expect(!UnreadRule.isUnread(lastActive: nil, lastRead: now))
    }
}
