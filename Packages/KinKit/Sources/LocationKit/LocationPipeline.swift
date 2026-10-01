public import Domain
import Foundation
import KinCore

/// Turns the raw location stream into the few uploads that matter.
///
///     tracker.samples() ──► persist locally ──► LocationUploadPolicy.shouldUpload ──► batch ──► enqueue + flush
///                                     ▲                                            (≤ every N s / on geofence)
///                     PowerContext ───┘ (battery, Low Power Mode, live session) picks the TrackingProfile
///
/// All decisions are delegated to the pure `LocationUploadPolicy`, so this type is only wiring and is tested with
/// `SimulatedLocationTracker` + closures.
public actor LocationPipeline {
    public struct Sinks: Sendable {
        public var persist: @Sendable ([LocationSample]) async -> Void
        public var enqueue: @Sendable ([LocationSample]) async -> Void
        public var flush: @Sendable () async -> Void

        public init(
            persist: @escaping @Sendable ([LocationSample]) async -> Void,
            enqueue: @escaping @Sendable ([LocationSample]) async -> Void,
            flush: @escaping @Sendable () async -> Void
        ) {
            self.persist = persist
            self.enqueue = enqueue
            self.flush = flush
        }
    }

    private let tracker: any LocationTracking
    private let sinks: Sinks
    private var profile: TrackingProfile = .balanced
    private var lastUploaded: LocationSample?
    private var pending: [LocationSample] = []
    private var lastFlush: Date = .distantPast
    private var running: Task<Void, Never>?

    public init(tracker: any LocationTracking, sinks: Sinks) {
        self.tracker = tracker
        self.sinks = sinks
    }

    public func start() {
        guard running == nil else { return }
        let stream = tracker.samples()
        let transitions = tracker.geofenceTransitions()
        running = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await sample in stream {
                    await self.handle(sample)
                } }
                group.addTask { for await _ in transitions {
                    await self.flushNow()
                } }
            }
        }
    }

    public func stop() {
        running?.cancel()
        running = nil
    }

    public func update(context: PowerContext) async {
        let newProfile = LocationUploadPolicy.profile(for: context)
        guard newProfile != profile else { return }
        profile = newProfile
        await tracker.setProfile(newProfile)
    }

    public var currentProfile: TrackingProfile {
        profile
    }

    func handle(_ sample: LocationSample) async {
        await sinks.persist([sample])
        guard LocationUploadPolicy.shouldUpload(sample, lastUploaded: lastUploaded, profile: profile) else { return }
        lastUploaded = sample
        pending.append(sample)
        // Batch: hold fixes until the profile's upload interval has passed, then send them in one request.
        if profile == .live || sample.timestamp.timeIntervalSince(lastFlush) >= profile.uploadInterval {
            await flushNow()
        }
    }

    /// Geofence transitions and SOS bypass batching.
    public func flushNow() async {
        let batch = pending
        pending.removeAll()
        lastFlush = batch.last?.timestamp ?? Date()
        if !batch.isEmpty {
            await sinks.enqueue(batch)
        }
        await sinks.flush()
    }
}
