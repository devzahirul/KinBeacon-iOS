public import Domain
public import Foundation
import os

/// A settable clock for deterministic tests.
public final class TestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    public init(_ date: Date = Fixtures.monday(hour: 10)) {
        state = OSAllocatedUnfairLock(initialState: date)
    }

    public var now: Date {
        state.withLock { $0 }
    }

    public func advance(by seconds: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    public func set(_ date: Date) {
        state.withLock { $0 = date }
    }

    public var provider: @Sendable () -> Date {
        { [self] in now }
    }
}

public enum Fixtures {
    /// Gregorian, UTC, Monday-first — tests never depend on the machine's locale or time zone.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 2026-09-28 is a Monday.
    public static func date(day: Int = 28, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    public static func monday(hour: Int, minute: Int = 0) -> Date {
        date(day: 28, hour: hour, minute: minute)
    }

    public static func saturday(hour: Int, minute: Int = 0) -> Date {
        date(day: 26, hour: hour, minute: minute)
    }

    public static let child: MemberID = "child-1"
    public static let school = Place(
        id: "school",
        name: "School",
        kind: .school,
        coordinate: Coordinate(latitude: 37.7631, longitude: -122.4214),
        radius: 150,
        address: "1 School Rd"
    )

    public static func sample(
        _ coordinate: Coordinate = school.coordinate,
        accuracy: Double = 10,
        at date: Date = monday(hour: 10)
    ) -> LocationSample {
        LocationSample(coordinate: coordinate, horizontalAccuracy: accuracy, timestamp: date)
    }

    /// Moves a coordinate north by `meters`.
    public static func offset(_ coordinate: Coordinate, northMeters meters: Double) -> Coordinate {
        Coordinate(latitude: coordinate.latitude + meters / 111_320, longitude: coordinate.longitude)
    }

    public static func controls(enabled: Bool = true) -> ControlsConfiguration {
        var configuration = ControlsConfiguration.defaults(for: child)
        configuration.modes = configuration.modes.map { mode in
            var copy = mode
            copy.isEnabled = mode.kind == .school ? enabled : false
            return copy
        }
        return configuration
    }

    public static func activeSchoolMode(until: Date = monday(hour: 15, minute: 15)) -> ActiveMode {
        ActiveMode(kind: .school, startedAt: monday(hour: 8), until: until)
    }
}

/// In-memory `OutboxStore` + `CommandLedger` (the SwiftData one is covered by its own tests).
public actor InMemoryOutbox: OutboxStore, CommandLedger {
    public private(set) var entries: [OutboxEntry] = []
    private var seen: Set<UUID> = []

    public init() {}

    public func enqueue(_ operation: OutboxOperation, at date: Date) -> UUID {
        let id = UUID()
        entries.append(OutboxEntry(id: id, operation: operation, attempt: 0, createdAt: date, nextAttemptAt: date))
        return id
    }

    public func due(at date: Date, limit: Int) -> [OutboxEntry] {
        Array(entries
            .filter { $0.nextAttemptAt <= date }
            .sorted { ($0.operation.priority, $0.createdAt) < ($1.operation.priority, $1.createdAt) }
            .prefix(limit))
    }

    public func markDelivered(_ ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
    }

    public func reschedule(_ id: UUID, attempt: Int, nextAttemptAt: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].attempt = attempt
        entries[index].nextAttemptAt = nextAttemptAt
    }

    public func drop(_ id: UUID) {
        markDelivered([id])
    }

    public func count() -> Int {
        entries.count
    }

    public func hasSeen(_ id: UUID) -> Bool {
        seen.contains(id)
    }

    public func record(_ id: UUID, at date: Date) {
        seen.insert(id)
    }
}

/// Records everything a child device sends; failures can be scripted per call.
public actor FakeCompanionService: CompanionService {
    public private(set) var uploadedBatches: [[LocationSample]] = []
    public private(set) var checkIns: [CheckIn] = []
    public private(set) var requests: [TimeRequest] = []
    public private(set) var sosEvents: [SOSEvent] = []
    public private(set) var callOrder: [String] = []
    public var failures: [any Error] = []
    public var dashboardValue: ChildDashboard?
    public var delay: Duration = .zero

    public init() {}

    public func fail(with errors: [any Error]) {
        failures = errors
    }

    public func setDelay(_ delay: Duration) {
        self.delay = delay
    }

    private func record(_ name: String) async throws {
        callOrder.append(name)
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
    }

    public func dashboard() async throws -> ChildDashboard {
        guard let dashboardValue else { throw KinError.notFound }
        return dashboardValue
    }

    public nonisolated func dashboardUpdates() -> AsyncStream<ChildDashboard> {
        AsyncStream { $0.finish() }
    }

    public nonisolated func timeRequestUpdates() -> AsyncStream<TimeRequest> {
        AsyncStream { $0.finish() }
    }

    public func controls() async throws -> ControlsConfiguration {
        Fixtures.controls()
    }

    public func timeRequests() async throws -> [TimeRequest] {
        requests
    }

    public func pendingCommands() async throws -> [RemoteCommand] {
        []
    }

    public func upload(locations: [LocationSample]) async throws {
        try await record("locations")
        uploadedBatches.append(locations)
    }

    public func submit(_ checkIn: CheckIn) async throws {
        try await record("checkIn")
        checkIns.append(checkIn)
    }

    public func submit(_ request: TimeRequest) async throws {
        try await record("timeRequest")
        requests.append(request)
    }

    public func triggerSOS(_ event: SOSEvent) async throws {
        try await record("sos")
        sosEvents.append(event)
    }

    public func report(permissions: PermissionHealthReport) async throws {
        try await record("permissions")
    }

    public func report(battery: BatteryState) async throws {
        try await record("battery")
    }
}

/// Polls until `condition` holds — for observing values produced by background tasks without `sleep`-based flakiness.
public func waitUntil(timeout: Duration = .seconds(3), _ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@MainActor
public func waitUntilOnMain(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
