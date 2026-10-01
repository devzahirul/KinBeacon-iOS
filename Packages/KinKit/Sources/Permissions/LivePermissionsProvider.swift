#if os(iOS)
    public import Domain
    import CoreLocation
    import KinCore
    import UIKit
    import UserNotifications

    /// Reads the real OS permission state and requests permissions *in context* (never at first launch).
    public final class LivePermissionsProvider: PermissionsProviding, Sendable {
        private let location: any LocationTracking
        private let screenTime: any ScreenTimeControlling

        public init(location: any LocationTracking, screenTime: any ScreenTimeControlling) {
            self.location = location
            self.screenTime = screenTime
        }

        public func currentReport() async -> PermissionHealthReport {
            async let locationState = locationPermission()
            async let notificationState = notificationPermission()
            async let refreshState = backgroundRefreshPermission()
            async let screenTimeState = screenTime.authorizationState()
            return await PermissionHealthReport(states: [
                .location: locationState,
                .notifications: notificationState,
                .backgroundRefresh: refreshState,
                .screenTime: screenTimeState,
            ])
        }

        public func request(_ kind: PermissionKind) async -> PermissionState {
            switch kind {
            case .location:
                var state = await location.requestWhenInUse()
                if state == .whenInUse {
                    state = await location.requestAlways()
                }
                let result = await locationPermission()
                // iOS shows each location prompt only once. If we still don't have "Always" + precise (denied earlier,
                // the upgrade was declined, or approximate only), the only path left is the Settings app.
                if result != .granted, state != .notDetermined {
                    await openSettings()
                }
                return result
            case .notifications:
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                if settings.authorizationStatus == .denied {
                    await openSettings()
                } else {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                }
                return await notificationPermission()
            case .backgroundRefresh:
                // Not requestable — the only path is the Settings app.
                await openSettings()
                return await backgroundRefreshPermission()
            case .screenTime:
                try? await screenTime.requestAuthorization(as: .child)
                return await screenTime.authorizationState()
            }
        }

        private func locationPermission() async -> PermissionState {
            let authorization = await location.authorization()
            guard authorization == .always else { return authorization.permissionState }
            // "Always" but approximate is not good enough for arrival alerts.
            let accuracy = await MainActor.run { CLLocationManager().accuracyAuthorization }
            return accuracy == .fullAccuracy ? .granted : .limited
        }

        private func notificationPermission() async -> PermissionState {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            case .notDetermined: .notDetermined
            @unknown default: .denied
            }
        }

        private func backgroundRefreshPermission() async -> PermissionState {
            await MainActor.run {
                switch UIApplication.shared.backgroundRefreshStatus {
                case .available: .granted
                case .denied: .denied
                case .restricted: .limited
                @unknown default: .denied
                }
            }
        }

        @MainActor
        private func openSettings() async {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        }
    }
#endif
