@testable import Domain
import Foundation
import Testing
import TestSupport

@Suite("Accounts, visits and timeline")
struct AccountTests {
    @Test("Email and pairing-code validation", arguments: [
        ("parent@example.com", true), ("a@b.co", true), ("no-at.example.com", false), ("x@nodot", false), ("sp ace@x.com", false),
    ])
    func email(input: String, valid: Bool) {
        #expect(AccountValidation.isValidEmail(input) == valid)
    }

    @Test("Pairing codes are exactly six digits")
    func codes() {
        #expect(AccountValidation.isValidPairingCode("482913"))
        #expect(AccountValidation.isValidPairingCode("482 913"))
        #expect(!AccountValidation.isValidPairingCode("48291"))
        #expect(!AccountValidation.isValidPairingCode("48291a"))
        #expect(ChildInvite(code: "482913", memberID: "c", expiresAt: .now).formattedCode == "482 913")
    }

    @Test("Visits are rebuilt from raw history, ignoring drive-bys")
    func visits() {
        let home = Place(
            id: "home",
            name: "Home",
            kind: .home,
            coordinate: Fixtures.offset(Fixtures.school.coordinate, northMeters: 3000),
            address: ""
        )
        let start = Fixtures.monday(hour: 7)
        var samples: [LocationSample] = (0 ..< 6).map { Fixtures.sample(home.coordinate, at: start.addingTimeInterval(Double($0) * 300)) }
        // A 1-minute drive past school doesn't count…
        samples.append(Fixtures.sample(Fixtures.offset(home.coordinate, northMeters: 1500), at: start.addingTimeInterval(1900)))
        // …then a real stay at school.
        samples += (0 ..< 10).map { Fixtures.sample(at: start.addingTimeInterval(3600 + Double($0) * 300)) }
        let visits = VisitBuilder.visits(from: samples.shuffled(), places: [home, Fixtures.school], now: start.addingTimeInterval(7200))
        #expect(visits.map(\.placeName) == ["School", "Home"])
        #expect(visits.first?.leftAt == nil)
        #expect(visits.last?.leftAt == start.addingTimeInterval(1900))
    }

    @Test("Timeline merges check-ins, requests and alerts newest first")
    func timeline() {
        let now = Fixtures.monday(hour: 12)
        let checkIn = CheckIn(memberID: Fixtures.child, kind: .imOK, createdAt: now.addingTimeInterval(-60))
        let request = TimeRequest(
            childID: Fixtures.child,
            option: .thirtyMinutes,
            createdAt: now.addingTimeInterval(-600),
            status: .approved(until: now.addingTimeInterval(1200))
        )
        let sos = SafetyAlert(memberID: Fixtures.child, kind: .sos, createdAt: now.addingTimeInterval(-3600))
        let events = ActivityTimeline.events(checkIns: [checkIn], requests: [request], alerts: [sos], limit: 10)
        #expect(events.count == 4)
        #expect(events.first?.kind == .checkIn(.imOK, message: nil))
        #expect(events.last?.kind == .sos)
        #expect(ActivityTimeline.events(checkIns: [checkIn], requests: [request], alerts: [sos], limit: 2).count == 2)
    }
}
