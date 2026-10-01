@testable import Domain
import Foundation
import Testing
import TestSupport

@Suite("TimeRequestPolicy")
struct TimeRequestPolicyTests {
    let now = Fixtures.monday(hour: 10)
    let active = Fixtures.activeSchoolMode()

    func request(minutesAgo: Double, status: TimeRequestStatus = .denied) -> TimeRequest {
        TimeRequest(childID: Fixtures.child, option: .fifteenMinutes, createdAt: now.addingTimeInterval(-minutesAgo * 60), status: status)
    }

    @Test("A normal request passes")
    func valid() {
        #expect(TimeRequestPolicy.validate(message: "Homework video", history: [], activeMode: active, now: now) == nil)
    }

    @Test("Nothing to ask for when no mode is active")
    func noMode() {
        #expect(TimeRequestPolicy.validate(message: "", history: [], activeMode: nil, now: now) == .noActiveMode)
    }

    @Test("Messages are capped at 200 characters")
    func tooLong() {
        let message = String(repeating: "a", count: 201)
        #expect(TimeRequestPolicy.validate(message: message, history: [], activeMode: active, now: now) == .messageTooLong)
        #expect(TimeRequestPolicy.normalizedMessage("  \n ") == nil)
        #expect(TimeRequestPolicy.normalizedMessage("  hi  ") == "hi")
    }

    @Test("Only one request may wait at a time")
    func alreadyPending() {
        #expect(TimeRequestPolicy
            .validate(message: "", history: [request(minutesAgo: 5, status: .pending)], activeMode: active, now: now) == .alreadyPending)
        // …but a stale pending request doesn't block forever.
        #expect(TimeRequestPolicy
            .validate(message: "", history: [request(minutesAgo: 45, status: .pending)], activeMode: active, now: now) == nil)
    }

    @Test("Rate limited to three per hour")
    func rateLimit() {
        let history = [request(minutesAgo: 50), request(minutesAgo: 20), request(minutesAgo: 10)]
        let violation = TimeRequestPolicy.validate(message: "", history: history, activeMode: active, now: now)
        #expect(violation == .tooManyRequests(retryAfter: now.addingTimeInterval(10 * 60)))
    }

    @Test("Pending requests expire after 30 minutes")
    func expiry() {
        #expect(TimeRequestPolicy.resolveExpiry(request(minutesAgo: 31, status: .pending), now: now).status == .expired)
        #expect(TimeRequestPolicy.resolveExpiry(request(minutesAgo: 5, status: .pending), now: now).status == .pending)
    }

    @Test("Every option respects DeviceActivity's 15-minute floor")
    func minimumOption() {
        #expect(ExtraTimeOption.allCases.allSatisfy { $0.minutes >= 15 })
    }
}

@Suite("Permission health")
struct PermissionHealthTests {
    @Test("Turning off location raises a critical alert")
    func locationRegression() {
        var degraded = PermissionHealthReport.healthy
        degraded.states[.location] = .denied
        let alerts = PermissionHealthEvaluator.alerts(
            memberID: Fixtures.child,
            from: .healthy,
            to: degraded,
            now: Fixtures.monday(hour: 10)
        )
        #expect(alerts.map(\.kind) == [.locationPermissionOff])
        #expect(alerts.first?.severity == .critical)
        #expect(alerts.first?.isFixableRemotely == true)
    }

    @Test("Background refresh changes are reported but not alerted")
    func backgroundRefresh() {
        var degraded = PermissionHealthReport.healthy
        degraded.states[.backgroundRefresh] = .denied
        #expect(PermissionHealthEvaluator.alerts(memberID: Fixtures.child, from: .healthy, to: degraded, now: .now).isEmpty)
        #expect(degraded.issues == [.backgroundRefresh])
    }

    @Test("Recoveries are detected")
    func recovery() {
        var degraded = PermissionHealthReport.healthy
        degraded.states[.notifications] = .denied
        #expect(PermissionHealthEvaluator.recoveries(from: degraded, to: .healthy) == [.notifications])
    }

    @Test("While-in-use location is only 'limited'")
    func whenInUse() {
        #expect(LocationAuthorization.whenInUse.permissionState == .limited)
        #expect(!LocationAuthorization.whenInUse.permissionState.isSatisfied)
        #expect(LocationAuthorization.always.permissionState == .granted)
    }
}

@Suite("Remote command authentication")
struct CommandAuthenticatorTests {
    let key = CommandAuthenticator.generateKeyData()
    let now = Fixtures.monday(hour: 10)

    func command(target: MemberID = Fixtures.child, issuedAt: Date? = nil, expiresIn: TimeInterval = 300) -> RemoteCommand {
        let issued = issuedAt ?? now
        return RemoteCommand(
            target: target,
            action: .grantExtraTime(requestID: UUID(), minutes: 15),
            issuedAt: issued,
            expiresAt: issued.addingTimeInterval(expiresIn)
        )
    }

    @Test("A signed, fresh command is accepted")
    func valid() {
        let authenticator = CommandAuthenticator(keyData: key)
        let signed = authenticator.sign(command())
        #expect(authenticator.verify(signed, for: Fixtures.child, now: now, alreadySeen: { _ in false }) == nil)
    }

    @Test("Tampering with the action invalidates the signature")
    func tampered() {
        let authenticator = CommandAuthenticator(keyData: key)
        var signed = authenticator.sign(command())
        signed.action = .grantExtraTime(requestID: UUID(), minutes: 600)
        #expect(authenticator.verify(signed, for: Fixtures.child, now: now, alreadySeen: { _ in false }) == .badSignature)
    }

    @Test("A different pairing key is rejected")
    func wrongKey() {
        let signed = CommandAuthenticator(keyData: CommandAuthenticator.generateKeyData()).sign(command())
        #expect(CommandAuthenticator(keyData: key).verify(signed, for: Fixtures.child, now: now, alreadySeen: { _ in
            false
        }) == .badSignature)
    }

    @Test("Expired, future-dated, misaddressed and replayed commands are rejected")
    func rejections() {
        let authenticator = CommandAuthenticator(keyData: key)
        #expect(authenticator.verify(
            authenticator.sign(command(expiresIn: -1)),
            for: Fixtures.child,
            now: now,
            alreadySeen: { _ in false }
        ) == .expired)
        let future = authenticator.sign(command(issuedAt: now.addingTimeInterval(3600), expiresIn: 600))
        #expect(authenticator.verify(future, for: Fixtures.child, now: now, alreadySeen: { _ in false }) == .notYetValid)
        #expect(authenticator.verify(
            authenticator.sign(command(target: "someone-else")),
            for: Fixtures.child,
            now: now,
            alreadySeen: { _ in false }
        ) == .wrongTarget)
        #expect(authenticator.verify(authenticator.sign(command()), for: Fixtures.child, now: now, alreadySeen: { _ in true }) == .replayed)
    }

    @Test("Small clock skew is tolerated")
    func skew() {
        let authenticator = CommandAuthenticator(keyData: key)
        let slightlyAhead = authenticator.sign(command(issuedAt: now.addingTimeInterval(120), expiresIn: 600))
        #expect(authenticator.verify(slightlyAhead, for: Fixtures.child, now: now, alreadySeen: { _ in false }) == nil)
    }
}

@Suite("Screen time aggregation")
struct ScreenTimeTests {
    let app = AppDescriptor(id: "a", name: "A", symbol: "a", palette: 0)
    let other = AppDescriptor(id: "b", name: "B", symbol: "b", palette: 0)

    @Test("Hourly buckets roll up into days")
    func daily() {
        let hourly = (0 ..< 48).map { UsageBucket(start: Fixtures.monday(hour: 0).addingTimeInterval(Double($0) * 3600), minutes: 1) }
        let days = ScreenTimeAggregator.dailyBuckets(from: hourly, calendar: Fixtures.calendar)
        #expect(days.map(\.minutes) == [24, 24])
    }

    @Test("Top apps merge duplicates and sort by usage")
    func topApps() {
        let top = ScreenTimeAggregator.topApps(
            [AppUsage(app: app, minutes: 10), AppUsage(app: other, minutes: 25), AppUsage(app: app, minutes: 20)],
            limit: 1
        )
        #expect(top.map(\.app.id) == ["a"])
        #expect(top.first?.minutes == 30)
    }

    @Test("Change and limit progress")
    func change() {
        let summary = ScreenTimeSummary(
            range: .day,
            anchor: Fixtures.monday(hour: 0),
            buckets: [UsageBucket(start: Fixtures.monday(hour: 9), minutes: 72)],
            topApps: [],
            previousTotalMinutes: 100,
            dailyLimitMinutes: 60
        )
        #expect(summary.change == -0.28)
        #expect(summary.limitProgress == 1)
        #expect(ScreenTimeSummary(range: .day, anchor: .now, buckets: [], topApps: [], previousTotalMinutes: 0, dailyLimitMinutes: 0)
            .change == nil)
    }
}
