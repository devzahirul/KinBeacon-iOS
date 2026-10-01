public import Domain
public import Foundation
public import UserNotifications

/// Notification categories and their actionable buttons. A parent can approve extra time straight from the lock
/// screen — the action runs in the background without launching the UI (`UNNotificationActionOptions` = []).
public enum NotificationCategory: String, CaseIterable, Sendable {
    case timeRequest = "KIN_TIME_REQUEST"
    case checkIn = "KIN_CHECK_IN"
    case safetyAlert = "KIN_SAFETY_ALERT"
    case checkInRequest = "KIN_CHECK_IN_REQUEST"
}

public enum NotificationAction: String, Sendable {
    case approve = "KIN_APPROVE"
    case deny = "KIN_DENY"
    case replyOK = "KIN_REPLY_OK"
    case view = "KIN_VIEW"
}

public enum NotificationUserInfoKey {
    public static let requestID = "requestID"
    public static let alertID = "alertID"
    public static let memberID = "memberID"
    public static let deepLink = "deepLink"
}

public enum NotificationContentFactory {
    public static var categories: Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: NotificationCategory.timeRequest.rawValue,
                actions: [
                    UNNotificationAction(identifier: NotificationAction.approve.rawValue, title: String(localized: "Approve"), options: []),
                    UNNotificationAction(
                        identifier: NotificationAction.deny.rawValue,
                        title: String(localized: "Not now"),
                        options: [.destructive]
                    ),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.checkInRequest.rawValue,
                actions: [UNNotificationAction(
                    identifier: NotificationAction.replyOK.rawValue,
                    title: String(localized: "I'm OK"),
                    options: []
                )],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: NotificationCategory.safetyAlert.rawValue,
                actions: [UNNotificationAction(
                    identifier: NotificationAction.view.rawValue,
                    title: String(localized: "View"),
                    options: [.foreground]
                )],
                intentIdentifiers: [],
                options: [.hiddenPreviewsShowTitle]
            ),
            UNNotificationCategory(identifier: NotificationCategory.checkIn.rawValue, actions: [], intentIdentifiers: [], options: []),
        ]
    }

    /// Builds the content for a family event. Pure — unit-tested without a notification center.
    public static func content(for event: FamilyEvent, memberName: String) -> UNMutableNotificationContent? {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch event {
        case let .timeRequest(request):
            guard request.status == .pending else { return nil }
            content.title = String(localized: "\(memberName) asked for \(request.option.title)")
            content.body = request.message ?? request.appName
                .map { String(localized: "To keep using \($0).") } ?? String(localized: "Tap to approve or decline.")
            content.categoryIdentifier = NotificationCategory.timeRequest.rawValue
            content.userInfo = [
                NotificationUserInfoKey.requestID: request.id.uuidString,
                NotificationUserInfoKey.memberID: request.childID.rawValue,
            ]
            content.threadIdentifier = "requests-\(request.childID)"
            content.interruptionLevel = .active
        case let .checkIn(checkIn):
            content.title = String(localized: "\(memberName): \(checkIn.kind.title)")
            content.body = checkIn.message ?? checkIn.kind.subtitle
            content.categoryIdentifier = NotificationCategory.checkIn.rawValue
            content.threadIdentifier = "checkins-\(checkIn.memberID)"
            content.userInfo = [NotificationUserInfoKey.memberID: checkIn.memberID.rawValue]
            // "Need help" breaks through Focus; "I'm OK" stays quiet.
            content.interruptionLevel = checkIn.kind.isUrgent ? .timeSensitive : .passive
            content.relevanceScore = checkIn.kind.isUrgent ? 1 : 0.2
        case let .alert(alert):
            content.title = alert.title
            content.body = alert.summary(childName: memberName)
            content.categoryIdentifier = NotificationCategory.safetyAlert.rawValue
            content.userInfo = [
                NotificationUserInfoKey.alertID: alert.id.uuidString,
                NotificationUserInfoKey.memberID: alert.memberID.rawValue,
            ]
            content.interruptionLevel = alert.severity == .critical ? .timeSensitive : .active
            content.relevanceScore = 1
        case .activity:
            return nil
        }
        return content
    }
}

/// Presents local notifications for events received while the app is running (demo backend / SSE). In production
/// the same content arrives as remote pushes rendered from the identical `NotificationContentFactory` on the server.
public struct LocalNotificationPresenter: NotificationPresenting {
    public init() {}

    public func requestAuthorization() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert,
            .sound,
            .badge,
            .providesAppNotificationSettings,
        ])) ?? false
    }

    public func present(_ event: FamilyEvent, memberName: String) async {
        guard let content = NotificationContentFactory.content(for: event, memberName: memberName) else { return }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
