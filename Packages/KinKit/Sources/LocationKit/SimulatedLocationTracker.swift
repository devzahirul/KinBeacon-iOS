public import Domain
import Foundation
import KinCore

/// Deterministic tracker for the simulator, previews and tests: emits a slow random walk around a start point at
/// the cadence of the current profile, and honours the same profile switches as the live tracker.
public final class SimulatedLocationTracker: LocationTracking, Sendable {
    private let start: Coordinate
    private let interval: Duration
    private let state: Broadcaster<TrackingProfile> = Broadcaster(replaysLatest: true)
    private let authorizationState: Broadcaster<LocationAuthorization> = Broadcaster(replaysLatest: true)
    private let transitions = Broadcaster<GeofenceTransition>()

    public init(start: Coordinate, interval: Duration = .seconds(5), authorization: LocationAuthorization = .always) {
        self.start = start
        self.interval = interval
        state.yield(.balanced)
        authorizationState.yield(authorization)
    }

    public func authorization() async -> LocationAuthorization {
        authorizationState.latest ?? .notDetermined
    }

    public func requestWhenInUse() async -> LocationAuthorization {
        if authorizationState.latest == .notDetermined {
            authorizationState.yield(.whenInUse)
        }
        return await authorization()
    }

    public func requestAlways() async -> LocationAuthorization {
        authorizationState.yield(.always)
        return .always
    }

    public func setProfile(_ profile: TrackingProfile) async {
        state.yield(profile)
    }

    public var currentProfile: TrackingProfile? {
        state.latest
    }

    public func samples() -> AsyncStream<LocationSample> {
        let start = start
        let interval = interval
        return AsyncStream { continuation in
            let task = Task {
                var step = 0
                while !Task.isCancelled {
                    let offset = Double(step % 7 - 3) * 0.00003
                    continuation.yield(LocationSample(
                        coordinate: Coordinate(latitude: start.latitude + offset, longitude: start.longitude + offset / 2),
                        horizontalAccuracy: 15,
                        timestamp: Date(),
                        speed: 0.4,
                        isStationary: step % 7 == 0
                    ))
                    step += 1
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func monitor(places: [Place]) async {}

    public func geofenceTransitions() -> AsyncStream<GeofenceTransition> {
        transitions.stream()
    }

    /// Test hook.
    public func simulate(_ transition: GeofenceTransition) {
        transitions.yield(transition)
    }
}
