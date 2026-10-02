import Foundation
import Testing
@testable import GChatKit

@MainActor
@Suite struct ChatStoreTests {
    private let chat = FakeChat()
    private let now = Date()
    private let defaults: UserDefaults

    init() {
        let suite = "GChatKitTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func message(_ id: String, in space: String, from user: String, at time: Date) -> Message {
        Message(name: "\(space)/messages/\(id)", sender: User(name: user, type: "HUMAN"), createTime: time, text: id)
    }

    /// Two conversations: a team space with one unread message and a direct message that is read.
    private func makeStore() async -> ChatStore {
        let earlier = now.addingTimeInterval(-600)
        chat.update { state in
            state.spaces = [
                Space(name: "spaces/team", spaceType: "SPACE", displayName: "Team", lastActiveTime: earlier),
                Space(name: "spaces/dm", spaceType: "DIRECT_MESSAGE", lastActiveTime: earlier.addingTimeInterval(-60)),
            ]
            state.messages["spaces/team"] = [message("t1", in: "spaces/team", from: "users/ann", at: earlier)]
            state.readTimes["spaces/team"] = earlier.addingTimeInterval(-30)
            state.readTimes["spaces/dm"] = earlier
            state.members["spaces/dm"] = [
                Membership(member: User(name: "users/me-id", type: "HUMAN")),
                Membership(member: User(name: "users/ann", type: "HUMAN")),
            ]
        }
        let store = ChatStore(chat: chat, people: FakePeople(), defaults: defaults)
        store.selection = nil
        await store.refreshSpaces()
        return store
    }

    @Test func loadsSpacesTitlesAndUnreadState() async throws {
        let store = await makeStore()
        #expect(store.phase == .ready)
        #expect(store.spaces.map(\.name) == ["spaces/team", "spaces/dm"])
        #expect(await eventually { store.unreadCount == 1 })
        let dm = try #require(store.space(named: "spaces/dm"))
        #expect(await eventually { store.title(for: dm) == "Ann Example" })
        #expect(store.partner(of: dm)?.user == "users/ann")
        #expect(store.isUnread(try #require(store.space(named: "spaces/team"))))
    }

    @Test func openingMarksRead() async throws {
        let store = await makeStore()
        #expect(await eventually { store.unreadCount == 1 })
        store.selection = "spaces/team"
        await store.open("spaces/team")

        #expect(store.transcript(for: "spaces/team").messages.map(\.text) == ["t1"])
        #expect(store.unreadCount == 0)
        #expect(chat.markedRead == ["spaces/team"])
    }

    @Test func newMessagesFromOthersAreReported() async throws {
        let store = await makeStore()
        var reported: [(String, [String])] = []
        store.onIncoming = { space, messages in
            reported.append((space.name, messages.compactMap(\.text)))
        }
        chat.update { state in
            state.spaces[1].lastActiveTime = now
            state.messages["spaces/dm"] = [
                message("mine", in: "spaces/dm", from: "users/me-id", at: now.addingTimeInterval(-1)),
                message("hello", in: "spaces/dm", from: "users/ann", at: now),
            ]
        }
        await store.refreshSpaces()

        #expect(reported.count == 1)
        #expect(reported.first?.0 == "spaces/dm")
        #expect(reported.first?.1 == ["hello"])
        #expect(store.spaces.first?.name == "spaces/dm")
        #expect(store.isUnread(try #require(store.space(named: "spaces/dm"))))

        // Nothing changed, so nothing is reported again.
        await store.refreshSpaces()
        #expect(reported.count == 1)
    }

    @Test func newMessagesInTheOpenConversationAreMarkedRead() async throws {
        let store = await makeStore()
        store.selection = "spaces/team"
        await store.open("spaces/team")
        var reported = 0
        store.onIncoming = { _, _ in reported += 1 }

        // Later than the read marker that opening the conversation just set.
        let later = Date().addingTimeInterval(5)
        chat.update { state in
            state.spaces[0].lastActiveTime = later
            state.messages["spaces/team"]?.append(message("t2", in: "spaces/team", from: "users/ann", at: later))
        }
        await store.refreshSpaces()

        #expect(reported == 0)
        #expect(store.transcript(for: "spaces/team").messages.map(\.text) == ["t1", "t2"])
        #expect(store.unreadCount == 0)
        #expect(chat.markedRead == ["spaces/team", "spaces/team"])
    }

    @Test func directoryLeavesOutMeAndExistingConversationsAreReused() async throws {
        let store = await makeStore()
        #expect(await eventually { store.directory.map(\.user) == ["users/ann", "users/bob", "users/zed"] })
        let dm = try #require(store.space(named: "spaces/dm"))
        #expect(await eventually { store.partner(of: dm) != nil })

        // Ann already has a direct message in the list, so it is selected, not created.
        let ann = try #require(store.directory.first { $0.user == "users/ann" })
        await store.startConversation(with: [ann])
        #expect(store.selection == "spaces/dm")
        #expect(chat.update { $0.created }.isEmpty)
    }

    @Test func severalPeopleStartAGroupChatOnce() async throws {
        let store = await makeStore()
        #expect(await eventually { store.directory.count == 3 })
        let people = store.directory.filter { $0.user != "users/ann" }

        await store.startConversation(with: people)
        #expect(chat.update { $0.created } == ["users/bob+users/zed"])
        let space = try #require(store.space(named: "spaces/new-1"))
        #expect(store.groupChats == [space])
        #expect(store.title(for: space) == "Bob, Zed")
        #expect(store.selection == "spaces/new-1")

        // The same people again, in another order, reopen the same group chat.
        store.selection = nil
        await store.startConversation(with: people.reversed())
        #expect(store.selection == "spaces/new-1")
        #expect(chat.update { $0.created }.count == 1)
    }

    @Test func startingAConversationCreatesAndKeepsIt() async throws {
        let store = await makeStore()
        #expect(await eventually { store.directory.count == 3 })
        let bob = try #require(store.directory.first { $0.user == "users/bob" })

        await store.startConversation(with: [bob])
        #expect(chat.update { $0.created } == ["users/bob"])
        #expect(store.selection == "spaces/new-1")
        let space = try #require(store.space(named: "spaces/new-1"))
        #expect(store.title(for: space) == "Bob Example")

        // The server does not list a direct message without messages; it stays anyway.
        await store.refreshSpaces()
        #expect(store.space(named: "spaces/new-1") != nil)

        // An existing empty direct message is found, not created again.
        chat.update { $0.existingDMs["users/zed"] = Space(name: "spaces/zed-dm", spaceType: "DIRECT_MESSAGE") }
        let zed = try #require(store.directory.first { $0.user == "users/zed" })
        await store.startConversation(with: [zed])
        #expect(store.selection == "spaces/zed-dm")
        #expect(chat.update { $0.created } == ["users/bob"])
    }

    @Test func failedSendCanBeRetried() async throws {
        let store = await makeStore()
        store.selection = "spaces/team"
        await store.open("spaces/team")

        chat.update { $0.sendFails = true }
        await store.send("  hi there \n", to: "spaces/team")
        let pending = try #require(store.transcript(for: "spaces/team").pending.first)
        #expect(pending.text == "hi there")
        #expect(pending.error == "Server error")

        chat.update { $0.sendFails = false }
        await store.retry(pending, in: "spaces/team")
        let transcript = store.transcript(for: "spaces/team")
        #expect(transcript.pending.isEmpty)
        #expect(transcript.messages.last?.text == "hi there")
        #expect(store.isMine(try #require(transcript.messages.last)))
        #expect(store.unreadCount == 0)
    }
}
