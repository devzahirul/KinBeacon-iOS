public import Foundation

/// Device conditions the tracking strategy adapts to.
public struct PowerContext: Hashable, Sendable {
    public var battery: BatteryState
    public var isLowPowerMode: Bool
    public var isAppInForeground: Bool
    /// An SOS is open or a parent is watching live: accuracy beats battery for a few minutes.
    public var isLiveSessionActive: Bool

    public init(battery: BatteryState, isLowPowerMode: Bool = false, isAppInForeground: Bool = false, isLiveSessionActive: Bool = false) {
        self.battery = battery
        self.isLowPowerMode = isLowPowerMode
        self.isAppInForeground = isAppInForeground
        self.isLiveSessionActive = isLiveSessionActive
    }
}

/// How the child's device should track right now. The CoreLocation adapter maps this onto
/// `CLLocationUpdate.LiveConfiguration` / `desiredAccuracy` / significant-change monitoring.
public enum TrackingProfile: String, Hashable, Sendable {
    /// SOS / parent watching live: best accuracy, every update uploaded.
    case live
    /// Normal day: `.otherNavigation`-style updates, the OS pauses them automatically when stationary.
    case balanced
    /// Low battery or Low Power Mode: significant-location-change + geofences only (cell/Wi-Fi, ~500 m).
    case lowPower

    public var desiredAccuracyMeters: Double {
        switch self {
        case .live: 10
        case .balanced: 50
        case .lowPower: 500
        }
    }

    /// Minimum distance between two uploaded samples.
    public var uploadDistanceMeters: Double {
        switch self {
        case .live: 10
        case .balanced: 75
        case .lowPower: 400
        }
    }

    /// Minimum time between uploads while moving; a heartbeat is still sent after `heartbeatInterval`.
    public var uploadInterval: TimeInterval {
        switch self {
        case .live: 5
        case .balanced: 60
        case .lowPower: 600
        }
    }

    public var heartbeatInterval: TimeInterval {
        switch self {
        case .live: 30
        case .balanced: 15 * 60
        case .lowPower: 30 * 60
        }
    }
}

/// Decides *how* to track and *which* samples are worth a network round-trip.
///
/// Battery cost on iOS is dominated by two things: GPS radio time and cellular radio wake-ups. The policy attacks
/// both: it lowers accuracy when the battery is low, and it drops samples that don't move the needle (jitter while
/// sitting in a classroom), batching the rest so the radio wakes once instead of once per fix.
public enum LocationUploadPolicy {
    public static let lowBatteryThreshold = 0.2
    /// Fixes worse than this are noise (indoor cell triangulation) unless nothing better exists.
    public static let maxUsableAccuracy = 1000.0

    public static func profile(for context: PowerContext) -> TrackingProfile {
        if context.isLiveSessionActive {
            return .live
        }
        if context.isLowPowerMode || (context.battery.level <= lowBatteryThreshold && !context.battery.isCharging) {
            return .lowPower
        }
        return .balanced
    }

    public static func shouldUpload(_ sample: LocationSample, lastUploaded: LocationSample?, profile: TrackingProfile) -> Bool {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxUsableAccuracy else { return false }
        guard let last = lastUploaded else { return true }
        guard sample.timestamp > last.timestamp else { return false }

        let elapsed = sample.timestamp.timeIntervalSince(last.timestamp)
        if elapsed >= profile.heartbeatInterval {
            return true
        }

        let distance = sample.coordinate.distance(to: last.coordinate)
        // Movement must exceed both the profile threshold and the combined uncertainty, otherwise it's GPS jitter.
        let significant = distance >= max(profile.uploadDistanceMeters, (sample.horizontalAccuracy + last.horizontalAccuracy) / 2)
        // A much more accurate fix at the same spot is worth sending (cell → GPS upgrade).
        let accuracyUpgrade = sample.horizontalAccuracy < last.horizontalAccuracy / 3
        return (significant && elapsed >= profile.uploadInterval) || accuracyUpgrade
    }

    /// Thins a batch collected while offline/backgrounded: keeps the first, last and every sample that passes
    /// `shouldUpload` relative to the previously kept one.
    public static func thin(_ samples: [LocationSample], lastUploaded: LocationSample?, profile: TrackingProfile) -> [LocationSample] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var kept: [LocationSample] = []
        var reference = lastUploaded
        for sample in ordered where shouldUpload(sample, lastUploaded: reference, profile: profile) {
            kept.append(sample)
            reference = sample
        }
        if let last = ordered.last, kept.last != last, last.horizontalAccuracy <= maxUsableAccuracy, kept.isEmpty == false {
            kept.append(last)
        }
        return kept
    }
}

// MARK: - Geofencing

public enum GeofenceTransition: Hashable, Sendable {
    case entered(PlaceID)
    case exited(PlaceID)
}

/// Server-/demo-side geofence evaluation with hysteresis: a member must be `radius - margin` inside to "arrive" and
/// `radius + margin` outside to "leave", so a child standing at the school gate doesn't produce an alert storm.
/// (On the child's device `CLMonitor` does this natively and survives app termination.)
public struct GeofenceEvaluator: Sendable {
    public var places: [Place]
    public var hysteresisMeters: Double
    public private(set) var inside: Set<PlaceID> = []

    public init(places: [Place], hysteresisMeters: Double = 30, initiallyInside: Set<PlaceID> = []) {
        self.places = places
        self.hysteresisMeters = hysteresisMeters
        inside = initiallyInside
    }

    public mutating func evaluate(_ sample: LocationSample) -> [GeofenceTransition] {
        // A 300 m-accurate fix can't tell us whether we crossed a 150 m fence.
        guard sample.horizontalAccuracy <= 200 else { return [] }
        var transitions: [GeofenceTransition] = []
        for place in places {
            let distance = place.coordinate.distance(to: sample.coordinate)
            let wasInside = inside.contains(place.id)
            if !wasInside, distance <= place.radius - hysteresisMeters {
                inside.insert(place.id)
                transitions.append(.entered(place.id))
            } else if wasInside, distance >= place.radius + hysteresisMeters {
                inside.remove(place.id)
                transitions.append(.exited(place.id))
            }
        }
        return transitions
    }

    /// The place the sample is in, preferring the smallest (most specific) fence.
    public func currentPlace(for coordinate: Coordinate) -> Place? {
        places.filter { $0.contains(coordinate) }.min { $0.radius < $1.radius }
    }
}
