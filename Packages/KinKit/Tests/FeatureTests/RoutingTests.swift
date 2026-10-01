import Domain
import Foundation
@testable import Routing
@testable import Session
import Testing
import TestSupport

@MainActor
@Suite("Routing & activity")
struct RoutingTests {
    @Test("Deep links resolve to a tab and a route")
    func deepLinks() throws {
        let id = UUID()
        #expect(try DeepLink(url: #require(URL(string: "kinbeacon://alert/\(id.uuidString)"))) == .alert(id))
        #expect(try DeepLink(url: #require(URL(string: "kinbeacon://member/emma")))?.parentDestination?.1 == .childDetail("emma"))
        #expect(try DeepLink(url: #require(URL(string: "kinbeacon://checkin")))?.childDestination?.1 == .checkIn)
        #expect(try DeepLink(url: #require(URL(string: "https://kinbeacon.app/alert"))) == nil)
        #expect(try DeepLink(url: #require(URL(string: "kinbeacon://alert/not-a-uuid"))) == nil)
    }

    @Test("Router push/pop/show")
    func router() {
        let router = Router<ParentRoute>()
        router.push(.notifications)
        router.push(.settings)
        router.pop()
        #expect(router.path == [.notifications])
        router.show(.places)
        #expect(router.path == [.places])
        router.popToRoot()
        #expect(router.path.isEmpty)
    }

    @Test("Activity can't navigate into the future and resets on range change")
    func activityNavigation() {
        let clock = TestClock(Fixtures.monday(hour: 12))
        let model = ActivityModel(service: NoActivity(), now: { clock.now }, calendar: Fixtures.calendar)
        #expect(!model.canGoForward)
        model.step(1)
        #expect(model.anchor == Fixtures.monday(hour: 0))
        model.step(-1)
        #expect(model.canGoForward)
        model.range = .week
        #expect(model.anchor == Fixtures.monday(hour: 0))
        #expect(model.loadKey(member: "a") != model.loadKey(member: "b"))
    }
}

struct NoActivity: ActivityService {
    func screenTime(for member: MemberID, range: ScreenTimeRange, anchor: Date) async throws -> ScreenTimeSummary {
        throw KinError.notFound
    }

    func activity(for member: MemberID, limit: Int) async throws -> [ActivityEvent] {
        []
    }

    func visits(for member: MemberID, on day: Date) async throws -> [PlaceVisit] {
        []
    }
}
