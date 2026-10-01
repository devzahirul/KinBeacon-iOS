public import UIKit
import Domain
import KinCore
import Messaging
import UserNotifications

/// UIKit entry points SwiftUI doesn't cover: APNs registration and silent pushes.
public final class KinAppDelegate: NSObject, UIApplicationDelegate {
    public let container: AppContainer

    override public init() {
        let signpost = Perf.begin("launch.delegate")
        container = AppContainer()
        Perf.end("launch.delegate", signpost)
        super.init()
    }

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let signpost = Perf.begin("launch.didFinishLaunching")
        defer { Perf.end("launch.didFinishLaunching", signpost) }
        // Must be set before this method returns so a cold launch from a notification tap is delivered.
        container.notifications.install()
        container.installNotificationRouting()
        if container.options.disableAnimations {
            UIView.setAnimationsEnabled(false)
        }
        // Registering for a token never shows a prompt; the alert permission is requested later, in context.
        application.registerForRemoteNotifications()
        MetricsReporter.shared.start()
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        container.notifications.didRegister(deviceToken: deviceToken)
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Silent push (`content-available: 1`) carrying a remote command. ~30 s of execution time.
    public func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        switch await container.handleRemoteNotification(userInfo) {
        case .executed: .newData
        case .failed: .failed
        case .rejected, nil: .noData
        }
    }
}

enum LocalNotificationPresenterBridge {
    static func requestAuthorization() async -> Bool {
        await LocalNotificationPresenter().requestAuthorization()
    }
}
