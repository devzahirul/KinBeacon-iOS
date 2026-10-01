import Foundation

/// Capped exponential backoff with "full jitter" (AWS architecture blog), so a fleet of child devices that lost
/// connectivity in the same school building doesn't hammer the API in lock-step when Wi-Fi comes back.
public struct ExponentialBackoff: Sendable {
    public var base: Duration
    public var multiplier: Double
    public var maximum: Duration
    public var jitter: Bool

    public init(base: Duration = .seconds(2), multiplier: Double = 2, maximum: Duration = .seconds(300), jitter: Bool = true) {
        self.base = base
        self.multiplier = multiplier
        self.maximum = maximum
        self.jitter = jitter
    }

    /// Delay before retry number `attempt` (0-based). `random` is injectable so tests are deterministic.
    public func delay(forAttempt attempt: Int, random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> Duration {
        let exponent = Double(max(0, min(attempt, 30)))
        let raw = base.timeInterval * pow(multiplier, exponent)
        let capped = min(raw, maximum.timeInterval)
        let value = jitter ? random(0 ... capped) : capped
        return .milliseconds(Int64(value * 1000))
    }
}

public extension Duration {
    /// The duration as fractional seconds.
    var timeInterval: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
