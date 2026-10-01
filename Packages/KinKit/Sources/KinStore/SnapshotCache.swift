public import Foundation
import KinCore

/// Stale-while-revalidate cache for a single Codable document (the last family snapshot / child dashboard).
///
/// The first frame after a cold launch renders this cached value instead of a spinner, then the live stream
/// replaces it. A flat JSON file in Caches is ~10× cheaper to read than spinning up a SwiftData stack, which is why
/// it is NOT stored in `KinDatabase` — the database is opened lazily, after the first frame.
public actor SnapshotCache<Value: Codable & Sendable> {
    private let url: URL

    public init(name: String, directory: URL = .cachesDirectory) {
        url = directory.appending(path: "\(name).json")
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            Log.storage.error("Snapshot cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
