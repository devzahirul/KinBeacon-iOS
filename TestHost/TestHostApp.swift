import SwiftUI

/// Empty host for the unit-test bundle so the package tests run on a physical iPhone.
/// (Hosting them in KinBeacon would link the package twice and turn its modules into dynamic frameworks.)
@main
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup { Text("KinKit test host") }
    }
}
