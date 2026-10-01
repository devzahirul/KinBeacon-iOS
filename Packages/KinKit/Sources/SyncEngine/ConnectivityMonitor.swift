import Network

/// Reachability as an `AsyncStream<Bool>` (true = a usable path exists). The sync engine flushes on every
/// offline → online transition instead of polling.
public struct ConnectivityMonitor: Sendable {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.lynkto.kinbeacon.connectivity", qos: .utility))
        }
    }
}
