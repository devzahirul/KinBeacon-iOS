#if os(iOS)
    public import Domain
    import Foundation
    import KinCore
    import UIKit

    /// Battery + Low Power Mode + foreground state as a replaying stream of `PowerContext`.
    /// Lives for the app's lifetime (owned by the composition root), so observers are registered once.
    @MainActor
    public final class PowerMonitor {
        private let hub = Broadcaster<PowerContext>(replaysLatest: true)
        private var observers: [any NSObjectProtocol] = []

        public init() {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let names: [Notification.Name] = [
                UIDevice.batteryLevelDidChangeNotification,
                UIDevice.batteryStateDidChangeNotification,
                .NSProcessInfoPowerStateDidChange,
                UIApplication.didBecomeActiveNotification,
                UIApplication.didEnterBackgroundNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publish() }
                }
            }
            publish()
        }

        public var battery: BatteryState {
            let device = UIDevice.current
            // -1 on the simulator: report a full battery rather than "0 %".
            let level = device.batteryLevel < 0 ? 1 : Double(device.batteryLevel)
            return BatteryState(level: level, isCharging: device.batteryState == .charging || device.batteryState == .full)
        }

        public var context: PowerContext {
            PowerContext(
                battery: battery,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isAppInForeground: UIApplication.shared.applicationState == .active
            )
        }

        public func updates() -> AsyncStream<PowerContext> {
            hub.stream()
        }

        private func publish() {
            hub.yield(context)
        }
    }
#endif
