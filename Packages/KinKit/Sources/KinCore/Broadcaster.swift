import os

/// A multicast `AsyncStream` source — the async/await equivalent of a hot `StateFlow`/`SharedFlow`.
///
/// `AsyncStream` is single-consumer, but several screens observe the same family state at once (map, controls,
/// alerts badge). Each call to `stream()` gets its own continuation; when `replaysLatest` is `true` the newest value is
/// delivered immediately, so a screen that appears later never renders an empty state for one frame.
///
/// A lock (not an actor) guards the state so `stream()` and `yield(_:)` are synchronous and callable from any
/// isolation domain without a hop. Termination removes the continuation, so cancelled `.task {}` loops never leak.
public final class Broadcaster<Element: Sendable>: Sendable {
    private struct State {
        var continuations: [Int: AsyncStream<Element>.Continuation] = [:]
        var nextID = 0
        var latest: Element?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let replaysLatest: Bool
    private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy

    public init(replaysLatest: Bool = false, bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(16)) {
        self.replaysLatest = replaysLatest
        self.bufferingPolicy = bufferingPolicy
    }

    /// The most recent value, if any (only tracked when `replaysLatest` is `true`).
    public var latest: Element? {
        state.withLock { $0.latest }
    }

    public var subscriberCount: Int {
        state.withLock { $0.continuations.count }
    }

    public func stream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        let id: Int = state.withLock { state in
            let id = state.nextID
            state.nextID += 1
            state.continuations[id] = continuation
            if replaysLatest, let latest = state.latest {
                continuation.yield(latest)
            }
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func yield(_ element: Element) {
        let continuations = state.withLock { state in
            if replaysLatest {
                state.latest = element
            }
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(element)
        }
    }

    public func finish() {
        let continuations = state.withLock { state in
            defer { state.continuations.removeAll() }
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}
