#if os(iOS)
    public import Domain
    import CoreLocation
    import KinCore
    import os

    /// CoreLocation adapter built on the iOS 17 async APIs.
    ///
    /// | Profile    | Mechanism                                                   | Typical radio cost |
    /// |------------|-------------------------------------------------------------|--------------------|
    /// | `.live`    | `CLLocationUpdate.liveUpdates(.fitness)` (GPS)              | high, minutes only |
    /// | `.balanced`| `CLLocationUpdate.liveUpdates(.otherNavigation)`; the OS     | low when stationary|
    /// |            | auto-pauses while `isStationary`                            |                    |
    /// | `.lowPower`| significant-location-change (cell/Wi-Fi, ~500 m)            | near zero          |
    ///
    /// Safe places use `CLMonitor` (iOS 17), which keeps evaluating geofences while the app is suspended or terminated
    /// and relaunches it on a transition. A `CLBackgroundActivitySession` keeps live updates flowing in the background.
    public final class LiveLocationTracker: LocationTracking, Sendable {
        private let bridge: ManagerBridge
        private let profileHub = Broadcaster<TrackingProfile>(replaysLatest: true)
        private let geofences = GeofenceMonitor()

        @MainActor
        public init(initialProfile: TrackingProfile = .balanced) {
            bridge = ManagerBridge()
            profileHub.yield(initialProfile)
        }

        public func authorization() async -> LocationAuthorization {
            await bridge.authorization
        }

        public func requestWhenInUse() async -> LocationAuthorization {
            await bridge.request(always: false)
        }

        /// Must be a separate, later step: iOS only shows the "Always" upgrade prompt after When-In-Use was granted,
        /// and App Review expects the user to understand why before seeing it.
        public func requestAlways() async -> LocationAuthorization {
            await bridge.request(always: true)
        }

        public func setProfile(_ profile: TrackingProfile) async {
            guard profileHub.latest != profile else { return }
            Log.location.info("Tracking profile → \(profile.rawValue, privacy: .public)")
            profileHub.yield(profile)
        }

        public func samples() -> AsyncStream<LocationSample> {
            let profiles = profileHub.stream()
            let bridge = bridge
            return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
                let task = Task {
                    var current: Task<Void, Never>?
                    // Restart the underlying mechanism whenever the profile changes.
                    for await profile in profiles {
                        current?.cancel()
                        current = Task { await Self.track(profile, bridge: bridge, into: continuation) }
                    }
                    current?.cancel()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        private static func track(
            _ profile: TrackingProfile,
            bridge: ManagerBridge,
            into continuation: AsyncStream<LocationSample>.Continuation
        ) async {
            if profile == .lowPower {
                let stream = await bridge.significantChanges()
                for await sample in stream {
                    continuation.yield(sample)
                }
                return
            }
            // Keeps the app eligible for background location delivery and shows the system indicator when needed.
            let session = CLBackgroundActivitySession()
            defer { session.invalidate() }
            let configuration: CLLocationUpdate.LiveConfiguration = profile == .live ? .fitness : .otherNavigation
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let location = update.location else { continue }
                    continuation.yield(LocationSample(location, isStationary: Self.isStationary(update, location)))
                }
            } catch {
                Log.location.error("Live updates ended: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// `CLLocationUpdate.stationary` is iOS 18+; on 17 fall back to a speed heuristic (`isStationary` is
        /// deprecated in the iOS 26 SDK, and the build treats warnings as errors).
        private static func isStationary(_ update: CLLocationUpdate, _ location: CLLocation) -> Bool {
            if #available(iOS 18, *) {
                return update.stationary
            }
            return location.speed >= 0 && location.speed < 0.3
        }

        public func monitor(places: [Place]) async {
            await geofences.monitor(places)
        }

        public func geofenceTransitions() -> AsyncStream<GeofenceTransition> {
            let geofences = geofences
            return AsyncStream { continuation in
                let task = Task {
                    for await transition in await geofences.transitions() {
                        continuation.yield(transition)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    extension LocationSample {
        init(_ location: CLLocation, isStationary: Bool) {
            self.init(
                coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                speed: location.speed >= 0 ? location.speed : nil,
                isStationary: isStationary
            )
        }
    }

    // MARK: - CLLocationManager bridge

    /// Owns the one `CLLocationManager` (authorization + significant-change), confined to the main actor because
    /// CLLocationManager delivers delegate callbacks on the run loop of the thread that created it.
    @MainActor
    final class ManagerBridge: NSObject, @preconcurrency CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
        private let significantHub = Broadcaster<LocationSample>()

        override init() {
            super.init()
            manager.delegate = self
            manager.pausesLocationUpdatesAutomatically = true
            manager.activityType = .otherNavigation
        }

        var authorization: LocationAuthorization {
            switch manager.authorizationStatus {
            case .authorizedAlways: .always
            case .authorizedWhenInUse: .whenInUse
            case .denied: .denied
            case .restricted: .restricted
            case .notDetermined: .notDetermined
            @unknown default: .denied
            }
        }

        func request(always: Bool) async -> LocationAuthorization {
            let before = authorization
            if always ? before == .always : before != .notDetermined {
                return before
            }
            return await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                if always {
                    manager.requestAlwaysAuthorization()
                } else {
                    manager.requestWhenInUseAuthorization()
                }
            }
        }

        func significantChanges() -> AsyncStream<LocationSample> {
            manager.startMonitoringSignificantLocationChanges()
            let stream = significantHub.stream()
            return AsyncStream { continuation in
                let task = Task {
                    for await sample in stream {
                        continuation.yield(sample)
                    }
                }
                continuation.onTermination = { [weak self] _ in
                    task.cancel()
                    Task { @MainActor in self?.manager.stopMonitoringSignificantLocationChanges() }
                }
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // The callback also fires once right after the delegate is set; only resume when the user actually answered.
            guard manager.authorizationStatus != .notDetermined || authorizationWaiters.isEmpty else { return }
            let value = authorization
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: value) }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            for location in locations {
                significantHub.yield(LocationSample(location, isStationary: false))
            }
        }
    }

    // MARK: - Geofences

    /// Wraps a single named `CLMonitor`. iOS allows 20 monitored conditions per app; we monitor at most
    /// `maxConditions` and keep the rest for future features.
    actor GeofenceMonitor {
        static let maxConditions = 16
        private var monitor: CLMonitor?
        private let hub = Broadcaster<GeofenceTransition>()
        private var listening: Task<Void, Never>?

        private func resolvedMonitor() async -> CLMonitor {
            if let monitor {
                return monitor
            }
            let created = await CLMonitor("kinbeacon.places")
            monitor = created
            listening = Task { [hub] in
                do {
                    for try await event in await created.events {
                        let id = PlaceID(rawValue: event.identifier)
                        switch event.state {
                        case .satisfied: hub.yield(.entered(id))
                        case .unsatisfied: hub.yield(.exited(id))
                        default: break
                        }
                    }
                } catch {
                    Log.location.error("Geofence events ended: \(error.localizedDescription, privacy: .public)")
                }
            }
            return created
        }

        func monitor(_ places: [Place]) async {
            let monitor = await resolvedMonitor()
            let wanted = Set(places.prefix(Self.maxConditions).map(\.id.rawValue))
            for identifier in await monitor.identifiers where !wanted.contains(identifier) {
                await monitor.remove(identifier)
            }
            for place in places.prefix(Self.maxConditions) {
                let condition = CLMonitor.CircularGeographicCondition(
                    center: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
                    radius: place.radius
                )
                await monitor.add(condition, identifier: place.id.rawValue, assuming: .unsatisfied)
            }
        }

        func transitions() async -> AsyncStream<GeofenceTransition> {
            _ = await resolvedMonitor()
            return hub.stream()
        }
    }
#endif
