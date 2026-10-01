import CoreLocation
@testable import LocationKit
import Testing

/// Regression: CLMonitor aborts the process ("Monitor name is not valid") for names containing dots. This shipped to
/// a device once (child pairing crash), so the real name is exercised against the real framework here.
@Suite("Geofence monitor")
struct GeofenceMonitorTests {
    @Test("The app's CLMonitor name is accepted by CoreLocation")
    func monitorNameIsValid() async {
        #expect(GeofenceMonitor.monitorName.allSatisfy { $0.isLetter || $0.isNumber })
        let monitor = await CLMonitor(GeofenceMonitor.monitorName)
        _ = await monitor.identifiers
    }

    @Test("Concurrent first use creates exactly one monitor")
    func singleFlight() async {
        let geofences = GeofenceMonitor()
        async let first = geofences.transitions()
        async let second = geofences.transitions()
        _ = await (first, second)
        await geofences.monitor([])
    }
}
