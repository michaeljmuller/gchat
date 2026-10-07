import Foundation
import Testing
@testable import GChatKit

@Suite struct RelayStreamParserTests {
    @Test func emitsEventsAtTheirDataLine() {
        var parser = RelayStreamParser()
        // URLSession drops the empty lines between events, so none are fed here.
        let lines = [
            ": ping",
            "event: notice",
            #"data: {"type": "t", "subject": "s", "resource": null, "time": "now"}"#,
            ": ping",
            "event: reauth",
            "data: {}",
            "data: bare",
        ]
        let events = lines.compactMap { parser.feed($0) }
        #expect(events.map(\.event) == ["notice", "reauth", "message"])
        #expect(events[2].data == "bare")
        let notice = try? JSONDecoder().decode(RelayNotice.self, from: Data(events[0].data.utf8))
        #expect(notice == RelayNotice(type: "t", subject: "s", resource: nil, time: "now"))
    }
}

@MainActor
@Suite struct PushControllerTests {
    private let events = FakeEvents()
    private let defaults: UserDefaults
    private let topic = "projects/p/topics/gchat-events"

    init() {
        let suite = "GChatKitTests.push.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func controller() -> PushController {
        let store = ChatStore(chat: FakeChat(), people: FakePeople(), defaults: defaults)
        return PushController(
            configuration: PushConfiguration(relayURL: URL(string: "https://relay.example.com")!, topic: topic),
            identity: FixedIdentity(), subscriptions: events, store: store, defaults: defaults)
    }

    @Test func makesASubscriptionOnceAndReusesIt() async throws {
        let push = controller()
        let name = try await push.ensureSubscription()
        #expect(name == "subscriptions/new-1")
        #expect(events.calls == ["create"])

        // The next launch finds the saved name still active at Google.
        #expect(try await controller().ensureSubscription() == name)
        #expect(events.calls == ["create", "get"])
    }

    @Test func renewsWhenLittleTimeIsLeftAndRevivesWhenSuspended() async throws {
        defaults.set("subscriptions/old", forKey: "pushSubscription")
        events.update {
            $0.subscriptions["subscriptions/old"] = EventSubscription(
                name: "subscriptions/old", state: "ACTIVE", expireTime: Date().addingTimeInterval(3600))
        }
        #expect(try await controller().ensureSubscription() == "subscriptions/old")
        #expect(events.calls == ["get", "renew"])

        events.update { $0.subscriptions["subscriptions/old"]?.state = "SUSPENDED" }
        #expect(try await controller().ensureSubscription() == "subscriptions/old")
        #expect(events.calls == ["get", "renew", "get", "reactivate"])
    }

    @Test func replacesASavedSubscriptionThatIsGone() async throws {
        defaults.set("subscriptions/gone", forKey: "pushSubscription")
        #expect(try await controller().ensureSubscription() == "subscriptions/new-1")
        #expect(events.calls == ["get", "create"])
        #expect(defaults.string(forKey: "pushSubscription") == "subscriptions/new-1")
    }

    @Test func adoptsThePersonsExistingSubscription() async throws {
        // Made on another Mac: Google refuses a second one for the same target.
        events.update {
            $0.createConflicts = true
            $0.subscriptions["subscriptions/elsewhere"] = EventSubscription(
                name: "subscriptions/elsewhere", state: "ACTIVE",
                expireTime: Date().addingTimeInterval(6 * 86400), pubsubTopic: "projects/p/topics/gchat-events")
        }
        #expect(try await controller().ensureSubscription() == "subscriptions/elsewhere")
        #expect(events.calls == ["create", "find"])
    }

    @Test func replacesAnExistingSubscriptionForAnotherTopic() async throws {
        events.update {
            $0.createConflicts = true
            $0.subscriptions["subscriptions/other"] = EventSubscription(
                name: "subscriptions/other", state: "ACTIVE", pubsubTopic: "projects/x/topics/y")
        }
        #expect(try await controller().ensureSubscription() == "subscriptions/new-1")
        #expect(events.calls == ["create", "find", "delete", "create"])
    }

    @Test func signOutDeletesTheSubscription() async throws {
        let push = controller()
        let name = try await push.ensureSubscription()
        await push.signOut()
        #expect(events.update { $0.subscriptions[name] } == nil)
        #expect(defaults.string(forKey: "pushSubscription") == nil)
    }
}
