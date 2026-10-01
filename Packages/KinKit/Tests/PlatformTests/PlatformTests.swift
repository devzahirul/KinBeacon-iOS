@testable import Domain
import Foundation
@testable import LocationKit
@testable import Messaging
@testable import ScreenTimeShared
import Testing
import TestSupport
import UserNotifications

@Suite("RemoteCommandProcessor")
struct RemoteCommandProcessorTests {
    let key = CommandAuthenticator.generateKeyData()

    func command(expiresIn: TimeInterval = 300) -> RemoteCommand {
        CommandAuthenticator(keyData: key).sign(RemoteCommand(
            target: Fixtures.child,
            action: .locateNow,
            issuedAt: .now,
            expiresAt: Date().addingTimeInterval(expiresIn)
        ))
    }

    @Test("Executes a valid command exactly once")
    func exactlyOnce() async {
        let counter = Counter()
        let processor = RemoteCommandProcessor(
            device: Fixtures.child,
            authenticator: CommandAuthenticator(keyData: key),
            ledger: InMemoryOutbox()
        ) { _ in
            await counter.increment()
        }
        let command = command()
        #expect(await processor.process(command) == .executed)
        #expect(await processor.process(command) == .rejected(.replayed))
        #expect(await counter.value == 1)
    }

    @Test("Expired commands never run")
    func expired() async {
        let counter = Counter()
        let processor = RemoteCommandProcessor(
            device: Fixtures.child,
            authenticator: CommandAuthenticator(keyData: key),
            ledger: InMemoryOutbox()
        ) { _ in
            await counter.increment()
        }
        #expect(await processor.process(command(expiresIn: -5)) == .rejected(.expired))
        #expect(await counter.value == 0)
    }

    @Test("Handlers that overrun the background budget fail instead of hanging")
    func budget() async {
        let processor = RemoteCommandProcessor(
            device: Fixtures.child,
            authenticator: nil,
            ledger: InMemoryOutbox(),
            budget: .milliseconds(50)
        ) { _ in try await Task.sleep(for: .seconds(5)) }
        #expect(await processor.process(command()) == .failed)
    }

    @Test("Parses APNs payloads and device tokens")
    func payload() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "kin": ["command": [
                "id": "9F5C2E10-1C1B-4A43-9F43-55C6B7A5D8A1",
                "target": "child-1",
                "action": ["ping": [String: String]()],
                "issuedAt": 1_790_000_000,
                "expiresAt": 1_790_000_300,
                "signature": "",
            ]],
        ]
        let command = try #require(PushPayload.command(from: userInfo))
        #expect(command.target == Fixtures.child)
        #expect(command.action == .ping)
        #expect(PushPayload.command(from: ["aps": [:]]) == nil)
        #expect(PushPayload.hexToken(Data([0x0A, 0xFF, 0x00])) == "0aff00")
    }
}

actor Counter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

@Suite("Notification content")
struct NotificationContentTests {
    @Test("Time requests are actionable from the lock screen")
    func timeRequest() throws {
        let request = TimeRequest(childID: Fixtures.child, option: .thirtyMinutes, message: "Book report", createdAt: .now)
        let content = try #require(NotificationContentFactory.content(for: .timeRequest(request), memberName: "Emma"))
        #expect(content.categoryIdentifier == NotificationCategory.timeRequest.rawValue)
        #expect(content.title.contains("Emma"))
        #expect(content.body == "Book report")
        #expect(content.userInfo[NotificationUserInfoKey.requestID] as? String == request.id.uuidString)
        let category = try #require(NotificationContentFactory.categories
            .first { $0.identifier == NotificationCategory.timeRequest.rawValue })
        #expect(category.actions.map(\.identifier) == [NotificationAction.approve.rawValue, NotificationAction.deny.rawValue])
    }

    @Test("Answered requests don't notify")
    func answered() {
        let request = TimeRequest(childID: Fixtures.child, option: .thirtyMinutes, createdAt: .now, status: .denied)
        #expect(NotificationContentFactory.content(for: .timeRequest(request), memberName: "Emma") == nil)
    }

    @Test("'Need help' breaks through Focus, 'I'm OK' stays quiet")
    func interruptionLevels() throws {
        let urgent = try #require(NotificationContentFactory.content(
            for: .checkIn(CheckIn(memberID: Fixtures.child, kind: .needHelp, createdAt: .now)),
            memberName: "Emma"
        ))
        let calm = try #require(NotificationContentFactory.content(
            for: .checkIn(CheckIn(memberID: Fixtures.child, kind: .imOK, createdAt: .now)),
            memberName: "Emma"
        ))
        #expect(urgent.interruptionLevel == .timeSensitive)
        #expect(calm.interruptionLevel == .passive)
    }
}

@Suite("Screen Time shared policy")
struct ScreenTimeSharedTests {
    func policy() -> SharedPolicy {
        SharedPolicy(configuration: Fixtures.controls(), childName: "Emma", guardianName: "Mom", updatedAt: Fixtures.monday(hour: 9))
    }

    @Test("Shield copy during School Mode offers a request button")
    func shieldDuringMode() {
        let content = ShieldCopy.content(
            appName: "Instagram",
            policy: policy(),
            now: Fixtures.monday(hour: 10),
            calendar: Fixtures.calendar
        )
        #expect(content.title.contains("Instagram"))
        #expect(content.subtitle.contains("School Mode"))
        #expect(content.primaryButton != nil)
    }

    @Test("Outside any mode the shield only closes")
    func shieldOutsideMode() {
        let content = ShieldCopy.content(appName: nil, policy: policy(), now: Fixtures.saturday(hour: 10), calendar: Fixtures.calendar)
        #expect(content.primaryButton == nil)
    }

    @Test("Weekday schedules become one activity per day; daily schedules collapse to one")
    func activityPlan() {
        var configuration = Fixtures.controls()
        configuration.update(ModeSettings(
            kind: .bedtime,
            isEnabled: true,
            schedule: WeeklySchedule(start: TimeOfDay(hour: 21), end: TimeOfDay(hour: 7), days: Weekday.everyDay)
        ))
        let plan = ActivityPlan(configuration: configuration)
        #expect(plan.entries.filter { $0.mode == .school }.count == 5)
        #expect(plan.entries.filter { $0.mode == .bedtime }.count == 1)
        #expect(plan.fitsSystemLimit)
        #expect(plan.entries.allSatisfy { ActivityNames.modeKind(fromActivity: $0.name) == $0.mode })
    }

    @Test("Policy round-trips through the App Group store; shield requests drain once")
    func store() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SharedPolicyStore(directory: directory)
        #expect(store.loadPolicy() == nil)
        try store.save(policy())
        #expect(store.loadPolicy() == policy())

        try store.enqueue(ShieldRequest(appName: "B", createdAt: Fixtures.monday(hour: 11)))
        try store.enqueue(ShieldRequest(appName: "A", createdAt: Fixtures.monday(hour: 10)))
        #expect(store.drainRequests().map(\.appName) == ["A", "B"])
        #expect(store.drainRequests().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Scripted tracker for pipeline tests.
final class ScriptedTracker: LocationTracking, @unchecked Sendable {
    let sampleStream: AsyncStream<LocationSample>
    let sampleContinuation: AsyncStream<LocationSample>.Continuation
    let transitionStream: AsyncStream<GeofenceTransition>
    let transitionContinuation: AsyncStream<GeofenceTransition>.Continuation
    private(set) var profiles: [TrackingProfile] = []

    init() {
        (sampleStream, sampleContinuation) = AsyncStream.makeStream()
        (transitionStream, transitionContinuation) = AsyncStream.makeStream()
    }

    func authorization() async -> LocationAuthorization {
        .always
    }

    func requestWhenInUse() async -> LocationAuthorization {
        .always
    }

    func requestAlways() async -> LocationAuthorization {
        .always
    }

    func samples() -> AsyncStream<LocationSample> {
        sampleStream
    }

    func setProfile(_ profile: TrackingProfile) async {
        profiles.append(profile)
    }

    func monitor(places: [Place]) async {}
    func geofenceTransitions() -> AsyncStream<GeofenceTransition> {
        transitionStream
    }
}

actor Sink {
    var persisted = 0
    var enqueued: [[LocationSample]] = []
    var flushes = 0
    func persist(_ samples: [LocationSample]) {
        persisted += samples.count
    }

    func enqueue(_ samples: [LocationSample]) {
        enqueued.append(samples)
    }

    func flush() {
        flushes += 1
    }
}

@Suite("LocationPipeline")
struct LocationPipelineTests {
    func make() -> (LocationPipeline, ScriptedTracker, Sink) {
        let tracker = ScriptedTracker()
        let sink = Sink()
        let pipeline = LocationPipeline(tracker: tracker, sinks: .init(
            persist: { await sink.persist($0) },
            enqueue: { await sink.enqueue($0) },
            flush: { await sink.flush() }
        ))
        return (pipeline, tracker, sink)
    }

    @Test("Every fix is stored locally, only meaningful ones are uploaded")
    func filtering() async {
        let (pipeline, tracker, sink) = make()
        await pipeline.start()
        let start = Fixtures.monday(hour: 10)
        tracker.sampleContinuation.yield(Fixtures.sample(at: start))
        tracker.sampleContinuation.yield(Fixtures.sample(
            Fixtures.offset(Fixtures.school.coordinate, northMeters: 5),
            at: start.addingTimeInterval(30)
        ))
        tracker.sampleContinuation.yield(Fixtures.sample(
            Fixtures.offset(Fixtures.school.coordinate, northMeters: 400),
            at: start.addingTimeInterval(120)
        ))
        #expect(await waitUntil { await sink.persisted == 3 })
        #expect(await sink.enqueued.flatMap(\.self).count == 2)
        await pipeline.stop()
    }

    @Test("A geofence transition flushes immediately")
    func geofenceFlush() async {
        let (pipeline, tracker, sink) = make()
        await pipeline.start()
        tracker.transitionContinuation.yield(.entered("school"))
        #expect(await waitUntil { await sink.flushes >= 1 })
        await pipeline.stop()
    }

    @Test("Low battery switches the tracker to the low-power profile")
    func powerProfile() async {
        let (pipeline, tracker, _) = make()
        await pipeline.update(context: PowerContext(battery: BatteryState(level: 0.1)))
        await pipeline.update(context: PowerContext(battery: BatteryState(level: 0.1))) // no duplicate switch
        #expect(tracker.profiles == [.lowPower])
        #expect(await pipeline.currentProfile == .lowPower)
    }
}
