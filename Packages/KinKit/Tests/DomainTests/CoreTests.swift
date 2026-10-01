import Foundation
@testable import KinCore
import Testing
import TestSupport

@Suite("KinCore")
struct CoreTests {
    @Test("Backoff grows exponentially and is capped")
    func backoff() {
        let backoff = ExponentialBackoff(base: .seconds(2), multiplier: 2, maximum: .seconds(30), jitter: false)
        #expect(backoff.delay(forAttempt: 0) == .seconds(2))
        #expect(backoff.delay(forAttempt: 3) == .seconds(16))
        #expect(backoff.delay(forAttempt: 10) == .seconds(30))
    }

    @Test("Full jitter stays within the cap")
    func jitter() {
        let backoff = ExponentialBackoff(base: .seconds(1), maximum: .seconds(8))
        let delay = backoff.delay(forAttempt: 5) { range in range.upperBound / 2 }
        #expect(delay == .seconds(4))
    }

    @Test("Broadcaster replays the latest value to late subscribers")
    func replay() async {
        let hub = Broadcaster<Int>(replaysLatest: true)
        hub.yield(1)
        hub.yield(2)
        var iterator = hub.stream().makeAsyncIterator()
        #expect(await iterator.next() == 2)
        hub.yield(3)
        #expect(await iterator.next() == 3)
    }

    @Test("Broadcaster multicasts and forgets cancelled subscribers")
    func multicast() async {
        let hub = Broadcaster<Int>()
        var first = hub.stream().makeAsyncIterator()
        var second = hub.stream().makeAsyncIterator()
        #expect(hub.subscriberCount == 2)
        hub.yield(7)
        #expect(await first.next() == 7)
        #expect(await second.next() == 7)
        let third = hub.stream()
        #expect(hub.subscriberCount == 3)
        let task = Task { for await _ in third {} }
        task.cancel()
        await task.value
        #expect(await waitUntil { hub.subscriberCount == 2 })
    }

    @Test("Launch options parse from user defaults")
    func launchOptions() throws {
        let defaults = try #require(UserDefaults(suiteName: "launch-options-test"))
        defaults.set("child", forKey: "KinRole")
        defaults.set(true, forKey: "KinFastSimulation")
        let options = LaunchOptions(defaults: defaults, environment: ["KIN_API_BASE_URL": "https://api.example.com"])
        #expect(options.role == .child)
        #expect(options.fastSimulation)
        #expect(options.apiBaseURL?.host() == "api.example.com")
        defaults.removePersistentDomain(forName: "launch-options-test")
    }

    @Test("Durations format compactly")
    func durations() {
        #expect(KinFormat.duration(.seconds(0)).contains("0"))
        #expect(KinFormat.duration(.seconds(86 * 60)).contains("26"))
    }
}
