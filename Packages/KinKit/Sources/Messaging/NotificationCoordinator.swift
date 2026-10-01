#if os(iOS)
    public import Domain
    public import Foundation
    public import UserNotifications
    import KinCore
    import UIKit

    /// `UNUserNotificationCenterDelegate` + APNs registration. Turns taps and action buttons into typed
    /// `NotificationRoute`s handled by the composition root.
    @MainActor
    public final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
        public enum Route: Equatable, Sendable {
            case respond(requestID: UUID, approve: Bool)
            case replyOK
            case openRequest(UUID)
            case openAlert(UUID)
            case openMember(MemberID)
        }

        public var onRoute: (@MainActor (Route) async -> Void)?
        public var onDeviceToken: (@MainActor (String) -> Void)?

        override public init() {
            super.init()
        }

        /// Cheap and synchronous: must run before `didFinishLaunching` returns so a cold launch from a notification
        /// tap is delivered to the delegate.
        public func install() {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.setNotificationCategories(NotificationContentFactory.categories)
        }

        public func registerForRemoteNotifications() {
            UIApplication.shared.registerForRemoteNotifications()
        }

        public func didRegister(deviceToken: Data) {
            let token = PushPayload.hexToken(deviceToken)
            Log.push.info("APNs token registered")
            onDeviceToken?(token)
        }

        public nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .list, .sound]
        }

        public nonisolated func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let info = response.notification.request.content.userInfo
            let action = response.actionIdentifier
            let requestID = (info[NotificationUserInfoKey.requestID] as? String).flatMap(UUID.init(uuidString:))
            let alertID = (info[NotificationUserInfoKey.alertID] as? String).flatMap(UUID.init(uuidString:))
            let memberID = (info[NotificationUserInfoKey.memberID] as? String).map(MemberID.init(rawValue:))
            let route: Route? = switch (action, requestID, alertID, memberID) {
            case (NotificationAction.approve.rawValue, let id?, _, _): .respond(requestID: id, approve: true)
            case (NotificationAction.deny.rawValue, let id?, _, _): .respond(requestID: id, approve: false)
            case (NotificationAction.replyOK.rawValue, _, _, _): .replyOK
            case let (_, id?, _, _): .openRequest(id)
            case let (_, _, id?, _): .openAlert(id)
            case let (_, _, _, member?): .openMember(member)
            default: nil
            }
            guard let route else { return }
            await MainActor.run { [weak self] in
                guard let handler = self?.onRoute else { return }
                Task { await handler(route) }
            }
        }
    }
#endif
