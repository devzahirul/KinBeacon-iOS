import Foundation
import ManagedSettings
import ScreenTimeShared

/// Handles the shield's buttons. "Request 15 min" is queued in the App Group; the app sends it (through the durable
/// outbox) the next time it runs, including from its background refresh.
final class KinShieldAction: ShieldActionDelegate {
    private let store = SharedPolicyStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handle(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action, completionHandler: completionHandler)
    }

    private func handle(_ action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            try? store.enqueue(ShieldRequest(appName: nil, createdAt: Date()))
            // `.defer` keeps the shield up and re-asks the configuration — it will update once a grant arrives.
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        default:
            completionHandler(.close)
        }
    }
}
