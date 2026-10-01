public import Domain
public import Foundation
public import Observation

/// Every destination in the parent app. Features push routes; only `AppFeature` maps a route to a view, so features
/// never import each other (and a deep link can open any screen).
public enum ParentRoute: Hashable, Sendable {
    case childDetail(MemberID)
    case locationDetail(MemberID)
    case deviceDetail(MemberID)
    case safetyDetail(MemberID)
    case modeSchedule(MemberID, ControlModeKind)
    case appLimits(MemberID)
    case downtime(MemberID)
    case alwaysAllowed(MemberID)
    case webFilter(MemberID)
    case safetyAlert(UUID)
    case timeRequest(UUID)
    case notifications
    case places
    case settings
}

public enum ChildRoute: Hashable, Sendable {
    case requestTime(appName: String?)
    case checkIn
    case sos
    case shieldPreview(appName: String)
    case permissionsInfo
    case settings
}

public enum ParentTab: String, Hashable, CaseIterable, Sendable {
    case map, controls, activity, family
}

public enum ChildTab: String, Hashable, CaseIterable, Sendable {
    case home, activity, help, settings
}

/// A typed navigation stack owner. One router per tab, held by the root view.
@MainActor
@Observable
public final class Router<Route: Hashable & Sendable> {
    public var path: [Route] = []

    public init() {}

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        _ = path.popLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    /// Replace the stack — used by deep links so "back" lands on the tab root, not on stale history.
    public func show(_ route: Route) {
        path = [route]
    }
}

/// `kinbeacon://` URLs and notification taps resolve to one of these, then to a tab + route.
public enum DeepLink: Equatable, Sendable {
    case alert(UUID)
    case request(UUID)
    case member(MemberID)
    case checkIn
    case requestTime

    public init?(url: URL) {
        guard url.scheme == "kinbeacon", let host = url.host() else { return nil }
        let argument = url.pathComponents.dropFirst().first
        switch host {
        case "alert": guard let id = argument.flatMap(UUID.init(uuidString:)) else { return nil }; self = .alert(id)
        case "request": guard let id = argument.flatMap(UUID.init(uuidString:)) else { return nil }; self = .request(id)
        case "member": guard let id = argument else { return nil }; self = .member(MemberID(rawValue: id))
        case "checkin": self = .checkIn
        case "request-time": self = .requestTime
        default: return nil
        }
    }

    public var parentDestination: (ParentTab, ParentRoute)? {
        switch self {
        case let .alert(id): (.map, .safetyAlert(id))
        case let .request(id): (.activity, .timeRequest(id))
        case let .member(id): (.map, .childDetail(id))
        case .checkIn, .requestTime: nil
        }
    }

    public var childDestination: (ChildTab, ChildRoute)? {
        switch self {
        case .checkIn: (.home, .checkIn)
        case .requestTime: (.home, .requestTime(appName: nil))
        case .alert, .request, .member: nil
        }
    }
}
