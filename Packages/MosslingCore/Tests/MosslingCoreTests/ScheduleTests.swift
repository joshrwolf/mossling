import Foundation
import Testing
@testable import MosslingCore

func utcDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
func testCalendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}
func testEngine(_ schedule: ScheduleConfiguration = .standard) -> ScheduleEngine {
    ScheduleEngine(configuration: AppConfiguration(schedule: schedule))
}

@Suite("Civil-time scheduling")
struct ScheduleTests {
    @Test func standardSlotsAndBoundaries() throws {
        let engine = testEngine()
        let calendar = testCalendar()
        let slots = try engine.opportunities(on: utcDate("2026-09-21T12:00:00Z"), calendar: calendar)
        #expect(slots.count == 8)
        #expect(slots.first?.id == "2026-09-21-m0540")
        #expect(slots.first?.rewardKey == "2026-09-21-h09")
        #expect(slots.last?.expiresAt == utcDate("2026-09-21T17:00:00Z"))
        #expect(try engine.current(at: utcDate("2026-09-21T08:59:59Z"), calendar: calendar) == nil)
        #expect(try engine.current(at: utcDate("2026-09-21T09:00:00Z"), calendar: calendar)?.minuteOfDay == 540)
        #expect(try engine.current(at: utcDate("2026-09-21T09:59:59Z"), calendar: calendar)?.minuteOfDay == 540)
        #expect(try engine.current(at: utcDate("2026-09-21T10:00:00Z"), calendar: calendar)?.minuteOfDay == 600)
        #expect(try engine.current(at: utcDate("2026-09-21T17:00:00Z"), calendar: calendar) == nil)
    }

    @Test func weekendAndNextWeek() throws {
        let engine = testEngine(), calendar = testCalendar()
        #expect(try engine.opportunities(on: utcDate("2026-09-19T12:00:00Z"), calendar: calendar).isEmpty)
        #expect(try engine.next(after: utcDate("2026-09-18T17:00:00Z"), calendar: calendar)?.scheduledAt == utcDate("2026-09-21T09:00:00Z"))
        #expect(try engine.next(after: utcDate("2026-09-21T09:00:00Z"), calendar: calendar)?.scheduledAt == utcDate("2026-09-21T10:00:00Z"))
    }

    @Test func springForwardSkipsMissingHour() throws {
        let engine = testEngine(.init(weekdays: [1], startMinute: 60, endMinute: 240))
        let slots = try engine.opportunities(on: utcDate("2026-03-08T12:00:00Z"), calendar: testCalendar("America/Denver"))
        #expect(slots.map(\.minuteOfDay) == [60, 180])
        #expect(slots[0].scheduledAt == utcDate("2026-03-08T08:00:00Z"))
        #expect(slots[0].expiresAt == slots[1].scheduledAt)
        #expect(slots[1].scheduledAt == utcDate("2026-03-08T09:00:00Z"))
    }

    @Test func fallBackSchedulesRepeatedHourOnce() throws {
        let engine = testEngine(.init(weekdays: [1], startMinute: 60, endMinute: 240))
        let slots = try engine.opportunities(on: utcDate("2026-11-01T12:00:00Z"), calendar: testCalendar("America/Denver"))
        #expect(slots.map(\.minuteOfDay) == [60, 120, 180])
        #expect(slots[0].scheduledAt == utcDate("2026-11-01T07:00:00Z"))
        #expect(slots[0].expiresAt.timeIntervalSince(slots[0].scheduledAt) == 7200)
        #expect(try engine.current(at: utcDate("2026-11-01T08:30:00Z"), calendar: testCalendar("America/Denver"))?.id == slots[0].id)
    }

    @Test func nonexistentWindowEndMovesToNextValidTime() throws {
        let engine = testEngine(.init(weekdays: [1], startMinute: 60, endMinute: 150))
        let slots = try engine.opportunities(on: utcDate("2026-03-08T12:00:00Z"), calendar: testCalendar("America/Denver"))
        #expect(slots.count == 1)
        #expect(slots[0].expiresAt == utcDate("2026-03-08T09:00:00Z"))
    }

    @Test func timezoneUsesLocalDateNotUTC() throws {
        let engine = testEngine(.init(weekdays: [1,2,3,4,5,6,7], startMinute: 0, endMinute: 120))
        let date = utcDate("2026-09-21T01:00:00Z")
        let denver = try engine.opportunities(on: date, calendar: testCalendar("America/Denver"))
        let tokyo = try engine.opportunities(on: date, calendar: testCalendar("Asia/Tokyo"))
        #expect(denver[0].dayKey == "2026-09-20")
        #expect(tokyo[0].dayKey == "2026-09-21")
    }

    @Test func midnightEndAndNinetyMinuteSlots() throws {
        let engine = testEngine(.init(weekdays: [2], startMinute: 1260, endMinute: 1440, intervalMinutes: 90))
        let slots = try engine.opportunities(on: utcDate("2026-09-21T12:00:00Z"), calendar: testCalendar())
        #expect(slots.map(\.minuteOfDay) == [1260, 1350])
        #expect(slots.last?.expiresAt == utcDate("2026-09-22T00:00:00Z"))
    }

    @Test func assignmentAndIdentityStableAcrossRevisionAndArrayOrder() throws {
        var config = AppConfiguration.standard
        let date = utcDate("2026-09-21T12:00:00Z"), calendar = testCalendar()
        let first = try ScheduleEngine(configuration: config).opportunities(on: date, calendar: calendar)
        config.revision = 17
        config.activities.reverse()
        let second = try ScheduleEngine(configuration: config).opportunities(on: date, calendar: calendar)
        #expect(first == second)
        config.schedule.startMinute = 570
        let shifted = try ScheduleEngine(configuration: config).opportunities(on: date, calendar: calendar)
        #expect(first[0].id != shifted[0].id)
        #expect(first[0].rewardKey == shifted[0].rewardKey)
    }

    @Test func disabledSchedulesDoNotProduceOpportunities() throws {
        var config = AppConfiguration.standard
        config.schedule.enabled = false; config.schedule.weekdays = []; config.activities = []
        let engine = ScheduleEngine(configuration: config)
        #expect(try engine.opportunities(on: utcDate("2026-09-21T12:00:00Z"), calendar: testCalendar()).isEmpty)
        #expect(try engine.next(after: utcDate("2026-09-21T12:00:00Z"), calendar: testCalendar()) == nil)
        #expect(config.schedule.recurringSlots.isEmpty)
    }

    @Test func rejectsInvalidAndOversizedSchedules() throws {
        #expect(throws: ConfigurationError.emptyWeekdays) { try ScheduleConfiguration(weekdays: []).validate() }
        #expect(throws: ConfigurationError.invalidWeekdays) { try ScheduleConfiguration(weekdays: [0]).validate() }
        #expect(throws: ConfigurationError.invalidWindow) { try ScheduleConfiguration(startMinute: 1020, endMinute: 540).validate() }
        #expect(throws: ConfigurationError.invalidInterval) { try ScheduleConfiguration(intervalMinutes: 0).validate() }
        #expect(throws: ConfigurationError.tooManySlots) { try ScheduleConfiguration(weekdays: [1,2,3,4,5,6,7], startMinute: 0, endMinute: 1440).validate() }
        let exactLimit = ScheduleConfiguration(weekdays: [1,2,3,4,5,6,7])
        try exactLimit.validate()
        #expect(exactLimit.recurringSlots.count == 56)
    }

    @Test func validatesActivities() throws {
        var config = AppConfiguration.standard
        config.activities = []
        #expect(throws: ConfigurationError.noEnabledActivities) { try config.validate() }
        config.activities = [.starters[0], .starters[0]]
        #expect(throws: ConfigurationError.duplicateActivityIDs) { try config.validate() }
        var activity = ActivityDefinition.starters[0]; activity.targetValue = 0
        #expect(throws: ConfigurationError.invalidActivity(activity.id)) { try activity.validate() }
    }
}
