from relay.hub import QUEUE_LIMIT, RESYNC, Hub, Notice

NOTICE = Notice(type="t", subject="s", resource=None, time="now")


def test_first_user_owns_a_subscription():
    hub = Hub()
    assert hub.claim("subscriptions/a", "alice")
    assert hub.claim("subscriptions/a", "alice")
    assert not hub.claim("subscriptions/a", "mallory")
    assert hub.claim("subscriptions/b", "mallory")


async def test_publish_reaches_only_listeners_of_the_subscription():
    hub = Hub()
    first = hub.listen("subscriptions/a")
    second = hub.listen("subscriptions/a")
    other = hub.listen("subscriptions/b")
    assert hub.publish("subscriptions/a", NOTICE) == 2
    assert first.get_nowait() == NOTICE
    assert second.get_nowait() == NOTICE
    assert other.empty()
    hub.unlisten("subscriptions/a", first)
    assert hub.publish("subscriptions/a", NOTICE) == 1
    assert hub.publish("subscriptions/none", NOTICE) == 0


async def test_a_full_queue_is_replaced_by_resync():
    hub = Hub()
    queue = hub.listen("subscriptions/a")
    for _ in range(QUEUE_LIMIT):
        hub.publish("subscriptions/a", NOTICE)
    hub.publish("subscriptions/a", NOTICE)
    assert queue.get_nowait() is RESYNC
    assert queue.get_nowait() == NOTICE
    assert queue.empty()
