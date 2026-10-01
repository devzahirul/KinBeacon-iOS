public import Domain
public import Foundation
public import Observation
import KinCore

/// Screen time for one member over a day/week/month, plus today's places. Reused by the child's own Activity tab.
@MainActor
@Observable
public final class ActivityModel {
    public enum Phase: Equatable {
        case loading
        case loaded(ScreenTimeSummary)
        case failed(KinError)
    }

    public var range: ScreenTimeRange = .day {
        didSet {
            if range != oldValue {
                anchor = calendar.startOfDay(for: now())
            }
        }
    }

    public private(set) var anchor: Date
    public private(set) var phase: Phase = .loading
    public private(set) var visits: [PlaceVisit] = []

    @ObservationIgnored private let service: any ActivityService
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(service: any ActivityService, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.service = service
        self.now = now
        self.calendar = calendar
        anchor = calendar.startOfDay(for: now())
    }

    /// Identity for `.task(id:)`: reloading whenever the member, range or date changes, cancelling stale loads.
    public func loadKey(member: MemberID?) -> String {
        "\(member?.rawValue ?? "-")|\(range.rawValue)|\(anchor.timeIntervalSince1970)"
    }

    public func load(member: MemberID) async {
        if case .loaded = phase {} else {
            phase = .loading
        }
        let anchor = range == .day ? anchor : min(now(), endOfPeriod)
        do {
            let summary = try await service.screenTime(for: member, range: range, anchor: anchor)
            try Task.checkCancellation()
            phase = .loaded(summary)
            visits = await range == .day ? (try? service.visits(for: member, on: self.anchor)) ?? [] : []
        } catch is CancellationError {
            // Superseded by a newer load.
        } catch {
            phase = .failed(error as? KinError ?? .server(status: 0))
        }
    }

    public var canGoForward: Bool {
        guard let next = calendar.date(byAdding: range.calendarComponent, value: 1, to: anchor) else { return false }
        return next <= now()
    }

    public func step(_ direction: Int) {
        guard direction < 0 || canGoForward,
              let next = calendar.date(byAdding: range.calendarComponent, value: direction, to: anchor) else { return }
        anchor = next
    }

    private var endOfPeriod: Date {
        calendar.date(byAdding: range.calendarComponent, value: 1, to: anchor).map { $0.addingTimeInterval(-1) } ?? anchor
    }

    public var periodTitle: String {
        switch range {
        case .day:
            return KinFormat.dayTitle(anchor, calendar: calendar, now: now())
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: anchor) ?? anchor
            return "\(anchor.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    public var comparisonLabel: String {
        switch range {
        case .day: String(localized: "from yesterday")
        case .week: String(localized: "from last week")
        case .month: String(localized: "from last month")
        }
    }
}
