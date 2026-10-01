@testable import Domain
import Foundation
import Testing
import TestSupport

@Suite("WeeklySchedule")
struct ScheduleTests {
    let calendar = Fixtures.calendar
    let school = WeeklySchedule(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 15, minute: 15), days: Weekday.schoolDays)
    let bedtime = WeeklySchedule(start: TimeOfDay(hour: 21), end: TimeOfDay(hour: 7), days: [.friday])

    @Test("Active inside the window on a school day", arguments: [8, 12, 15])
    func activeDuringSchoolHours(hour: Int) {
        #expect(school.isActive(at: Fixtures.monday(hour: hour), calendar: calendar))
    }

    @Test("End is exclusive and weekends are off")
    func boundaries() {
        #expect(!school.isActive(at: Fixtures.monday(hour: 15, minute: 15), calendar: calendar))
        #expect(!school.isActive(at: Fixtures.monday(hour: 7, minute: 59), calendar: calendar))
        #expect(!school.isActive(at: Fixtures.saturday(hour: 10), calendar: calendar))
    }

    @Test("Overnight windows belong to the day they start")
    func overnight() {
        // Friday 2026-09-25 21:00 → Saturday 07:00.
        #expect(bedtime.spansMidnight)
        #expect(bedtime.durationMinutes == 600)
        #expect(bedtime.isActive(at: Fixtures.date(day: 25, hour: 23), calendar: calendar))
        #expect(bedtime.isActive(at: Fixtures.saturday(hour: 6), calendar: calendar))
        #expect(!bedtime.isActive(at: Fixtures.saturday(hour: 7), calendar: calendar))
        // Sunday night is not included.
        #expect(!bedtime.isActive(at: Fixtures.date(day: 27, hour: 23), calendar: calendar))
    }

    @Test("Active interval reports concrete start and end")
    func activeInterval() throws {
        let interval = try #require(school.activeInterval(containing: Fixtures.monday(hour: 10), calendar: calendar))
        #expect(interval.start == Fixtures.monday(hour: 8))
        #expect(interval.end == Fixtures.monday(hour: 15, minute: 15))
    }

    @Test("Next start skips the weekend")
    func nextStart() {
        let fridayAfternoon = Fixtures.date(day: 25, hour: 16)
        #expect(school.nextStart(after: fridayAfternoon, calendar: calendar) == Fixtures.monday(hour: 8))
        #expect(school.nextStart(after: Fixtures.monday(hour: 7), calendar: calendar) == Fixtures.monday(hour: 8))
    }

    @Test("TimeOfDay clamps and wraps")
    func timeOfDay() {
        #expect(TimeOfDay(hour: 25, minute: 70) == TimeOfDay(hour: 23, minute: 59))
        #expect(TimeOfDay(minutesSinceMidnight: -30) == TimeOfDay(hour: 23, minute: 30))
        #expect(TimeOfDay(minutesSinceMidnight: 1440 + 61) == TimeOfDay(hour: 1, minute: 1))
    }

    @Test("Weekday order follows the calendar's first weekday")
    func weekdayOrder() {
        #expect(Weekday.ordered(calendar: calendar).first == .monday)
        var us = calendar
        us.firstWeekday = 1
        #expect(Weekday.ordered(calendar: us).first == .sunday)
        #expect(Weekday.sunday.previous == .saturday)
    }
}

@Suite("ModeResolver")
struct ModeResolverTests {
    let calendar = Fixtures.calendar

    @Test("Picks the enabled mode whose window contains now")
    func activeSchoolMode() throws {
        let mode = try #require(ModeResolver.activeMode(in: Fixtures.controls(), at: Fixtures.monday(hour: 10), calendar: calendar))
        #expect(mode.kind == .school)
        #expect(mode.until == Fixtures.monday(hour: 15, minute: 15))
        #expect(!mode.isPaused(at: Fixtures.monday(hour: 10)))
    }

    @Test("Disabled modes never activate")
    func disabled() {
        #expect(ModeResolver.activeMode(in: Fixtures.controls(enabled: false), at: Fixtures.monday(hour: 10), calendar: calendar) == nil)
    }

    @Test("Stricter mode wins when windows overlap")
    func priority() throws {
        var configuration = Fixtures.controls()
        configuration.update(ModeSettings(
            kind: .bedtime,
            isEnabled: true,
            schedule: WeeklySchedule(start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 11), days: Weekday.everyDay)
        ))
        let mode = try #require(ModeResolver.activeMode(in: configuration, at: Fixtures.monday(hour: 10), calendar: calendar))
        #expect(mode.kind == .bedtime)
    }

    @Test("An extra-time grant pauses but never extends the mode")
    func grantPauses() throws {
        let start = Fixtures.monday(hour: 15)
        let grant = ExtraTimeGrant(requestID: UUID(), startsAt: start, minutes: 60)
        let mode = try #require(ModeResolver.activeMode(
            in: Fixtures.controls(),
            at: start.addingTimeInterval(60),
            grant: grant,
            calendar: calendar
        ))
        #expect(mode.isPaused(at: start.addingTimeInterval(60)))
        #expect(mode.pausedUntil == Fixtures.monday(hour: 15, minute: 15))
    }

    @Test("Next transition is the end of the current window")
    func nextTransition() {
        let next = ModeResolver.nextTransition(in: Fixtures.controls(), after: Fixtures.monday(hour: 10), calendar: calendar)
        #expect(next == Fixtures.monday(hour: 15, minute: 15))
    }
}
