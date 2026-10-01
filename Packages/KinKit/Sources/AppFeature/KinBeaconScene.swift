public import SwiftUI
import BackgroundTasks
import KinCore

/// The app's only scene. Background refresh uses SwiftUI's async `.backgroundTask` instead of hand-rolled
/// `BGTaskScheduler` handlers: the closure is structured concurrency, so cancellation on expiry is automatic.
public struct KinBeaconScene: Scene {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some Scene {
        WindowGroup {
            KinRootView(container: container)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundScheduler.scheduleRefresh()
            }
        }
        .backgroundTask(.appRefresh(AppConstants.refreshTaskID)) {
            BackgroundScheduler.scheduleRefresh() // keep the chain alive
            await container.backgroundRefresh()
        }
    }
}

enum BackgroundScheduler {
    /// iOS decides the real time based on usage; 15 min is the earliest we ask for.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on the simulator (BGTaskScheduler is unavailable there).
            Log.background.notice("BG refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }
}
