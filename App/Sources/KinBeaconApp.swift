import AppFeature
import SwiftUI

/// Thin shell: every line of product code lives in the KinKit package.
@main
struct KinBeaconApp: App {
    @UIApplicationDelegateAdaptor(KinAppDelegate.self) private var delegate

    var body: some Scene {
        KinBeaconScene(container: delegate.container)
    }
}
