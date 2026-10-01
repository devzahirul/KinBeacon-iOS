public import os

/// Signpost intervals that appear in Instruments (Points of Interest / os_signpost lanes) and in the
/// "App Launch" template, so every claim in the README about launch and frame time is measurable.
///
/// Usage:
///
///     let state = Perf.begin("snapshot.decode")
///     defer { Perf.end("snapshot.decode", state) }
///
///     try await Perf.measure("controls.save") { try await service.save(...) }
///
/// Signposts are compiled into Release on purpose: they cost a few nanoseconds when Instruments is not attached
/// and are the only way to profile a TestFlight build with real data.
public enum Perf {
    public static let signposter = OSSignposter(subsystem: Log.subsystem, category: .pointsOfInterest)

    public static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    public static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    public static func measure<T>(
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let state = begin(name)
        defer { end(name, state) }
        return try await work()
    }
}
