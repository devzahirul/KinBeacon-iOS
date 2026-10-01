public import Domain
public import Foundation
public import KinCore

/// Everything the Screen Time extensions need to make a decision, written by the app and read by the extensions.
///
/// The app and its extensions are separate processes. The only channel between them is the App Group container,
/// so this is a small, versioned, Codable document — not SwiftData (too heavy for the extensions' memory budget).
public struct SharedPolicy: Codable, Hashable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var configuration: ControlsConfiguration
    public var grant: ExtraTimeGrant?
    public var childName: String
    public var guardianName: String
    public var updatedAt: Date
    /// Apps allowed during every mode, chosen on this device with `FamilyActivityPicker`. Application tokens are
    /// device-specific, so the parent's own picker selection can't be used here — this list is chosen on the child's iPhone.
    public var deviceAllowedApps: AppSelection?

    public init(
        configuration: ControlsConfiguration,
        grant: ExtraTimeGrant? = nil,
        childName: String,
        guardianName: String,
        updatedAt: Date
    ) {
        schemaVersion = Self.schemaVersion
        self.configuration = configuration
        self.grant = grant
        self.childName = childName
        self.guardianName = guardianName
        self.updatedAt = updatedAt
    }

    public func activeMode(at date: Date, calendar: Calendar = .current) -> ActiveMode? {
        ModeResolver.activeMode(in: configuration, at: date, grant: grant, calendar: calendar)
    }
}

/// A "Request 15 min" tap on the system shield, queued by the ShieldAction extension for the app to send.
public struct ShieldRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var appName: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), appName: String?, createdAt: Date) {
        self.id = id
        self.appName = appName
        self.createdAt = createdAt
    }
}

/// File-backed store in the App Group container.
///
/// • The policy is a single file replaced atomically (`Data.write(options: .atomic)` = write-then-rename), so an
///   extension never reads a torn document while the app is writing.
/// • Shield requests are one file each: the extension only ever *creates* files and the app only ever *deletes*
///   them, so there is no read-modify-write race between processes and no need for `NSFileCoordinator`.
public struct SharedPolicyStore: Sendable {
    private let directory: URL

    public init(directory: URL = AppConstants.sharedContainerURL) {
        self.directory = directory
    }

    private var policyURL: URL {
        directory.appending(path: "policy.json")
    }

    private var requestsDirectory: URL {
        directory.appending(path: "ShieldRequests", directoryHint: .isDirectory)
    }

    public func loadPolicy() -> SharedPolicy? {
        guard let data = try? Data(contentsOf: policyURL) else { return nil }
        do {
            let policy = try Self.decoder.decode(SharedPolicy.self, from: data)
            return policy.schemaVersion == SharedPolicy.schemaVersion ? policy : nil
        } catch {
            Log.screenTime.error("Shared policy unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func save(_ policy: SharedPolicy) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(policy).write(to: policyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clearPolicy() {
        try? FileManager.default.removeItem(at: policyURL)
    }

    public func enqueue(_ request: ShieldRequest) throws {
        try FileManager.default.createDirectory(at: requestsDirectory, withIntermediateDirectories: true)
        let url = requestsDirectory.appending(path: "\(request.id.uuidString).json")
        try Self.encoder.encode(request).write(to: url, options: .atomic)
    }

    /// Returns queued shield requests (oldest first) and deletes them.
    public func drainRequests() -> [ShieldRequest] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil)) ?? []
        let requests = urls.compactMap { url -> ShieldRequest? in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? Self.decoder.decode(ShieldRequest.self, from: data)
        }
        return requests.sorted { $0.createdAt < $1.createdAt }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
