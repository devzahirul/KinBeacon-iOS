public import Foundation
import CryptoKit

/// A command a parent sends to a child's device through a silent push (`content-available: 1`).
///
/// Silent pushes are best-effort (APNs coalesces and throttles them, and drops them entirely when the user
/// force-quits the app), so every command is also persisted server-side and re-fetched by the BGAppRefresh
/// heartbeat. That makes idempotency mandatory — the same command can arrive twice.
public struct RemoteCommand: Identifiable, Hashable, Codable, Sendable {
    public enum Action: Hashable, Codable, Sendable {
        case locateNow
        case applyControls(revision: Int)
        case grantExtraTime(requestID: UUID, minutes: Int)
        case denyExtraTime(requestID: UUID)
        case requestCheckIn
        case fixPermissions(PermissionKind)
        case startLiveSession(seconds: Int)
        case ping
    }

    public var id: UUID
    public var target: MemberID
    public var action: Action
    public var issuedAt: Date
    public var expiresAt: Date
    /// Base64 HMAC-SHA256 over the canonical encoding of every other field.
    public var signature: String

    public init(id: UUID = UUID(), target: MemberID, action: Action, issuedAt: Date, expiresAt: Date, signature: String = "") {
        self.id = id
        self.target = target
        self.action = action
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.signature = signature
    }
}

/// Authenticates commands with a per-device key exchanged at pairing time (stored in the Keychain).
///
/// Why sign at all when APNs is already TLS? Because the push *payload* is assembled by our backend and relayed by
/// third parties (APNs/FCM). A signature binds the command to the paired parent, so a compromised push credential
/// alone can't unlock a child's apps or start live tracking.
public struct CommandAuthenticator: Sendable {
    public enum Rejection: Error, Equatable, Sendable {
        case badSignature
        case expired
        case notYetValid
        case replayed
        case wrongTarget
    }

    /// Tolerated clock difference between server and device.
    public static let allowedClockSkew: TimeInterval = 5 * 60

    private let key: SymmetricKey

    public init(keyData: Data) {
        key = SymmetricKey(data: keyData)
    }

    public static func generateKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public func sign(_ command: RemoteCommand) -> RemoteCommand {
        var signed = command
        signed.signature = signature(for: command)
        return signed
    }

    public func verify(_ command: RemoteCommand, for device: MemberID, now: Date, alreadySeen: (UUID) -> Bool) -> Rejection? {
        guard let provided = Data(base64Encoded: command.signature),
              HMAC<SHA256>.isValidAuthenticationCode(provided, authenticating: Self.canonicalBytes(command), using: key)
        else { return .badSignature }
        guard command.target == device else { return .wrongTarget }
        guard now < command.expiresAt else { return .expired }
        guard command.issuedAt <= now.addingTimeInterval(Self.allowedClockSkew) else { return .notYetValid }
        guard !alreadySeen(command.id) else { return .replayed }
        return nil
    }

    private func signature(for command: RemoteCommand) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Self.canonicalBytes(command), using: key)).base64EncodedString()
    }

    /// Deterministic bytes: sorted keys, integer timestamps, signature blanked.
    static func canonicalBytes(_ command: RemoteCommand) -> Data {
        var unsigned = command
        unsigned.signature = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64(date.timeIntervalSince1970.rounded(.down)))
        }
        return (try? encoder.encode(unsigned)) ?? Data()
    }
}
