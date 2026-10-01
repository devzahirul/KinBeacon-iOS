public import Domain
public import Foundation
import KinCore

/// Verifies and executes remote commands delivered by silent push or fetched by the background heartbeat.
///
/// Silent pushes give the app roughly 30 s of background time, so the processor has a hard 25 s budget and reports
/// an outcome that maps 1:1 to `UIBackgroundFetchResult` — iOS uses that result to decide how generously to wake
/// the app next time.
public actor RemoteCommandProcessor {
    public enum Outcome: Equatable, Sendable {
        case executed
        case rejected(CommandAuthenticator.Rejection)
        case failed
    }

    public typealias Handler = @Sendable (RemoteCommand.Action) async throws -> Void

    public static let executionBudget: Duration = .seconds(25)

    private let device: MemberID
    private let authenticator: CommandAuthenticator?
    private let ledger: any CommandLedger
    private let handler: Handler
    private let now: @Sendable () -> Date
    private let budget: Duration

    /// `authenticator == nil` only in demo mode (no pairing key exists).
    public init(
        device: MemberID,
        authenticator: CommandAuthenticator?,
        ledger: any CommandLedger,
        budget: Duration = RemoteCommandProcessor.executionBudget,
        now: @escaping @Sendable () -> Date = { Date() },
        handler: @escaping Handler
    ) {
        self.budget = budget
        self.device = device
        self.authenticator = authenticator
        self.ledger = ledger
        self.now = now
        self.handler = handler
    }

    public func process(_ command: RemoteCommand) async -> Outcome {
        let date = now()
        if let authenticator {
            let seen = await ledger.hasSeen(command.id)
            if let rejection = authenticator.verify(command, for: device, now: date, alreadySeen: { _ in seen }) {
                Log.push.notice("Rejected command \(command.id, privacy: .public): \(String(describing: rejection), privacy: .public)")
                return .rejected(rejection)
            }
        } else if await ledger.hasSeen(command.id) {
            return .rejected(.replayed)
        }
        // Record before executing: a crash mid-way must not cause a second execution on redelivery.
        await ledger.record(command.id, at: date)
        let handler = handler
        let budget = budget
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await handler(command.action) }
                group.addTask {
                    try await Task.sleep(for: budget)
                    throw CancellationError()
                }
                try await group.next()
                group.cancelAll()
            }
            Log.push.info("Executed command \(command.id, privacy: .public)")
            return .executed
        } catch {
            Log.push.error("Command \(command.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Executes a batch fetched by the heartbeat, oldest first.
    public func process(_ commands: [RemoteCommand]) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for command in commands.sorted(by: { $0.issuedAt < $1.issuedAt }) {
            await outcomes.append(process(command))
        }
        return outcomes
    }
}

/// APNs payload ⇄ `RemoteCommand`.
///
///     { "aps": { "content-available": 1 }, "kin": { "command": { …RemoteCommand JSON… } } }
public enum PushPayload {
    public static func command(from userInfo: [AnyHashable: Any]) -> RemoteCommand? {
        guard let kin = userInfo["kin"] as? [String: Any], let command = kin["command"],
              JSONSerialization.isValidJSONObject(command),
              let data = try? JSONSerialization.data(withJSONObject: command) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(RemoteCommand.self, from: data)
    }

    public static func hexToken(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}
