@testable import Domain
import Foundation
import Testing
import TestSupport

@Suite("LocationUploadPolicy")
struct LocationPolicyTests {
    let start = Fixtures.monday(hour: 10)

    @Test("Profile follows battery, Low Power Mode and live sessions")
    func profileSelection() {
        #expect(LocationUploadPolicy.profile(for: PowerContext(battery: BatteryState(level: 0.8))) == .balanced)
        #expect(LocationUploadPolicy.profile(for: PowerContext(battery: BatteryState(level: 0.15))) == .lowPower)
        #expect(LocationUploadPolicy.profile(for: PowerContext(battery: BatteryState(level: 0.15, isCharging: true))) == .balanced)
        #expect(LocationUploadPolicy.profile(for: PowerContext(battery: BatteryState(level: 0.9), isLowPowerMode: true)) == .lowPower)
        #expect(LocationUploadPolicy.profile(for: PowerContext(battery: BatteryState(level: 0.1), isLiveSessionActive: true)) == .live)
    }

    @Test("The first usable fix is always uploaded")
    func firstFix() {
        #expect(LocationUploadPolicy.shouldUpload(Fixtures.sample(), lastUploaded: nil, profile: .balanced))
    }

    @Test("Garbage accuracy is rejected", arguments: [-1.0, 1500.0])
    func badAccuracy(accuracy: Double) {
        #expect(!LocationUploadPolicy.shouldUpload(Fixtures.sample(accuracy: accuracy), lastUploaded: nil, profile: .balanced))
    }

    @Test("Jitter inside the accuracy circle is dropped")
    func jitter() {
        let last = Fixtures.sample(accuracy: 40, at: start)
        let jitter = Fixtures.sample(Fixtures.offset(last.coordinate, northMeters: 30), accuracy: 40, at: start.addingTimeInterval(120))
        #expect(!LocationUploadPolicy.shouldUpload(jitter, lastUploaded: last, profile: .balanced))
    }

    @Test("Real movement is uploaded once the interval has passed")
    func movement() {
        let last = Fixtures.sample(at: start)
        let moved = Fixtures.sample(Fixtures.offset(last.coordinate, northMeters: 200), at: start.addingTimeInterval(90))
        let tooSoon = Fixtures.sample(Fixtures.offset(last.coordinate, northMeters: 200), at: start.addingTimeInterval(20))
        #expect(LocationUploadPolicy.shouldUpload(moved, lastUploaded: last, profile: .balanced))
        #expect(!LocationUploadPolicy.shouldUpload(tooSoon, lastUploaded: last, profile: .balanced))
    }

    @Test("A stationary device still sends a heartbeat")
    func heartbeat() {
        let last = Fixtures.sample(at: start)
        let later = Fixtures.sample(at: start.addingTimeInterval(TrackingProfile.balanced.heartbeatInterval))
        #expect(LocationUploadPolicy.shouldUpload(later, lastUploaded: last, profile: .balanced))
    }

    @Test("A much better fix at the same spot is worth sending")
    func accuracyUpgrade() {
        let coarse = Fixtures.sample(accuracy: 300, at: start)
        let precise = Fixtures.sample(accuracy: 15, at: start.addingTimeInterval(10))
        #expect(LocationUploadPolicy.shouldUpload(precise, lastUploaded: coarse, profile: .balanced))
    }

    @Test("Out-of-order samples are ignored")
    func outOfOrder() {
        let last = Fixtures.sample(at: start)
        let older = Fixtures.sample(Fixtures.offset(last.coordinate, northMeters: 500), at: start.addingTimeInterval(-60))
        #expect(!LocationUploadPolicy.shouldUpload(older, lastUploaded: last, profile: .live))
    }

    @Test("Thinning a backlog keeps movement and the freshest fix")
    func thin() {
        let base = Fixtures.school.coordinate
        let samples: [LocationSample] = (0 ..< 20).map { (index: Int) -> LocationSample in
            let meters = Double(index / 5) * 300 + Double(index % 2) * 5
            let time: Date = start.addingTimeInterval(Double(index) * 70)
            return Fixtures.sample(Fixtures.offset(base, northMeters: meters), at: time)
        }
        let kept = LocationUploadPolicy.thin(samples.shuffled(), lastUploaded: nil, profile: .balanced)
        #expect(kept.count < samples.count)
        #expect(kept.count >= 4)
        #expect(kept.last == samples.last)
        #expect(kept == kept.sorted { $0.timestamp < $1.timestamp })
    }
}

@Suite("Geofencing")
struct GeofenceTests {
    @Test("Hysteresis prevents flapping at the fence")
    func hysteresis() {
        var evaluator = GeofenceEvaluator(places: [Fixtures.school], hysteresisMeters: 30)
        let center = Fixtures.school.coordinate
        #expect(evaluator.evaluate(Fixtures.sample(Fixtures.offset(center, northMeters: 140))).isEmpty) // inside radius but not by margin
        #expect(evaluator.evaluate(Fixtures.sample(Fixtures.offset(center, northMeters: 50))) == [.entered("school")])
        #expect(evaluator.evaluate(Fixtures.sample(Fixtures.offset(center, northMeters: 160))).isEmpty) // outside radius, within margin
        #expect(evaluator.evaluate(Fixtures.sample(Fixtures.offset(center, northMeters: 260))) == [.exited("school")])
    }

    @Test("Inaccurate fixes never cross a fence")
    func inaccurate() {
        var evaluator = GeofenceEvaluator(places: [Fixtures.school])
        #expect(evaluator.evaluate(Fixtures.sample(accuracy: 500)).isEmpty)
    }

    @Test("Radius is clamped to the reliable minimum")
    func minimumRadius() {
        let place = Place(id: "tiny", name: "Tiny", kind: .other, coordinate: Fixtures.school.coordinate, radius: 10, address: "")
        #expect(place.radius == Place.minimumRadius)
    }

    @Test("Haversine distance is accurate at city scale")
    func distance() {
        let origin = Fixtures.school.coordinate
        let north = Fixtures.offset(origin, northMeters: 1000)
        #expect(abs(origin.distance(to: north) - 1000) < 5)
    }
}
