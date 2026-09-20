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

@Suite("Temporary routine changes")
struct DailyRoutineTests {
    @Test func skipUsesRewardIdentityWithoutChangingBoundariesOrSchedule() throws {
        let now = utcDate("2026-09-21T09:40:00Z"), calendar = testCalendar()
        var configuration = AppConfiguration.standard
        let originalSchedule = configuration.schedule
        let skipped = try #require(try ScheduleEngine(configuration: configuration).current(at: now, calendar: calendar))
        try configuration.skip(skipped, at: now, calendar: calendar)
        #expect(configuration.schedule == originalSchedule)
        #expect(try ScheduleEngine(configuration: configuration).current(at: now, calendar: calendar) == nil)
        #expect(try ScheduleEngine(configuration: configuration).next(after: now, calendar: calendar)?.scheduledAt == skipped.expiresAt)
        #expect(try ScheduleEngine(configuration: configuration).opportunities(on: now, calendar: calendar).first?.expiresAt == skipped.expiresAt)
        configuration.schedule.startMinute = 570
        #expect(try ScheduleEngine(configuration: configuration).current(at: now, calendar: calendar) == nil)
        #expect(try ScheduleEngine(configuration: configuration).current(at: utcDate("2026-09-22T09:40:00Z"), calendar: calendar) != nil)
    }

    @Test func pauseExpiresAtCapturedLocalMidnightAcrossDSTAndTravel() throws {
        var configuration = AppConfiguration.standard
        let calendar = testCalendar("America/Denver")
        let now = utcDate("2026-11-01T06:30:00Z") // 00:30 before the repeated hour.
        try configuration.pauseForToday(at: now, calendar: calendar)
        let midnight = utcDate("2026-11-02T07:00:00Z")
        #expect(configuration.dailyOverride?.expiresAt == midnight)
        #expect(configuration.isPaused(at: midnight.addingTimeInterval(-1)))
        #expect(!configuration.isPaused(at: midnight))
        // Asking again after travel keeps the original absolute deadline.
        try configuration.pauseForToday(at: now.addingTimeInterval(3600), calendar: testCalendar("Asia/Tokyo"))
        #expect(configuration.dailyOverride?.expiresAt == midnight)
        let restored = try AppDocument.decode(AppDocument(configuration: configuration).encoded())
        #expect(!restored.configuration.isPaused(at: midnight))
    }

    @Test func resumePreservesSkipsAndExpiredOverrideGetsFreshDeadline() throws {
        var configuration = AppConfiguration.standard
        let calendar = testCalendar(), now = utcDate("2026-09-21T09:10:00Z")
        let opportunity = try #require(try ScheduleEngine(configuration: configuration).current(at: now, calendar: calendar))
        try configuration.skip(opportunity, at: now, calendar: calendar)
        try configuration.pauseForToday(at: now, calendar: calendar)
        configuration.resumeToday(at: now)
        #expect(!configuration.isPaused(at: now))
        #expect(configuration.isSkipped(opportunity, at: now))
        let tomorrow = utcDate("2026-09-22T09:10:00Z")
        try configuration.pauseForToday(at: tomorrow, calendar: calendar)
        #expect(configuration.dailyOverride?.skippedRewardKeys.isEmpty == true)
        #expect(configuration.dailyOverride?.expiresAt == utcDate("2026-09-23T00:00:00Z"))
    }

    @Test func reminderPlanResumesTomorrowWithoutAnotherRefresh() throws {
        var configuration = AppConfiguration.standard
        let calendar = testCalendar(), now = utcDate("2026-09-21T09:10:00Z")
        try configuration.pauseForToday(at: now, calendar: calendar)
        let plan = try ReminderPlan(configuration: configuration, at: now, calendar: calendar)
        #expect(plan.currentOpportunity == nil)
        #expect(plan.opportunities.first?.scheduledAt == utcDate("2026-09-22T09:00:00Z"))
        #expect(plan.coverageEnd == utcDate("2026-09-28T00:00:00Z"))
        #expect(plan.opportunities.count == 32)
        #expect(plan.opportunities.allSatisfy { $0.scheduledAt > now && $0.scheduledAt < plan.coverageEnd })
    }

    @Test func reminderPlanHonorsCapacityCompletedRewardsAndCurrentSnooze() throws {
        let configuration = AppConfiguration(schedule: .init(weekdays: [1,2,3,4,5,6,7]))
        let calendar = testCalendar(), before = utcDate("2026-09-21T00:00:00Z")
        let full = try ReminderPlan(configuration: configuration, at: before, calendar: calendar)
        #expect(full.opportunities.count == ReminderPlan.maximumReminders)
        let now = utcDate("2026-09-21T09:10:00Z")
        let active = try ReminderPlan(configuration: configuration, at: now, calendar: calendar)
        #expect(active.currentOpportunity?.rewardKey == "2026-09-21-h09")
        #expect(active.opportunities.first?.rewardKey == "2026-09-21-h10")
        let completed = try ReminderPlan(configuration: configuration, at: now, calendar: calendar,
            completedRewardKeys: ["2026-09-21-h09", "2026-09-21-h10"])
        #expect(completed.currentOpportunity == nil)
        #expect(completed.opportunities.first?.rewardKey == "2026-09-21-h11")
    }
}

@Suite("Balanced daily activity suggestions")
struct ActivityRotationTests {
    @Test(arguments: [60, 90, 120]) func eachCadenceBalancesTheWholeDayWithoutEarlyRepeats(interval: Int) throws {
        let configuration = AppConfiguration(schedule: .init(weekdays: [2], startMinute: 0, endMinute: 1440, intervalMinutes: interval))
        let slots = try ScheduleEngine(configuration: configuration).opportunities(
            on: utcDate("2026-09-21T12:00:00Z"), calendar: testCalendar())
        let ids = slots.map(\.activity.id)
        let enabledIDs = Set(configuration.activities.filter(\.isEnabled).map(\.id))
        let counts = enabledIDs.map { id in ids.filter { $0 == id }.count }
        #expect(slots.count == 1440 / interval)
        #expect((counts.max() ?? 0) - (counts.min() ?? 0) <= 1)
        #expect(zip(ids, ids.dropFirst()).allSatisfy { $0 != $1 })
        for start in stride(from: 0, to: ids.count, by: enabledIDs.count) {
            let cycle = Array(ids[start..<min(start + enabledIDs.count, ids.count)])
            #expect(Set(cycle).count == cycle.count)
        }
        #expect(slots.last?.expiresAt == utcDate("2026-09-22T00:00:00Z"))
    }

    @Test func canonicalOrderSurvivesSerializationRevisionAndDifferentInputOrder() throws {
        let date = utcDate("2026-09-21T12:00:00Z"), calendar = testCalendar()
        var configuration = AppConfiguration.standard
        let original = try ScheduleEngine(configuration: configuration).opportunities(on: date, calendar: calendar)
        configuration.revision = 100
        configuration.activities.reverse()
        let phone = try ScheduleEngine(configuration: configuration).opportunities(on: date, calendar: calendar)
        let wire = try ConfigurationSnapshot(configuration: configuration, authorityID: UUID()).encoded()
        let watch = try ConfigurationSnapshot.decode(wire).configuration
        let watchSlots = try ScheduleEngine(configuration: watch).opportunities(on: date, calendar: calendar)
        #expect(phone == original)
        #expect(watchSlots == original)
    }

    @Test func disabledActivitiesNeverEnterRotationAndSingletonAlwaysWorks() throws {
        var configuration = AppConfiguration.standard
        for index in configuration.activities.indices {
            configuration.activities[index].isEnabled = index < 2
        }
        let date = utcDate("2026-09-21T12:00:00Z"), calendar = testCalendar()
        let two = try ScheduleEngine(configuration: configuration).opportunities(on: date, calendar: calendar)
        #expect(Set(two.map(\.activity.id)) == Set(configuration.activities.prefix(2).map(\.id)))
        #expect(zip(two, two.dropFirst()).allSatisfy { $0.activity.id != $1.activity.id })
        configuration.activities[1].isEnabled = false
        let one = try ScheduleEngine(configuration: configuration).opportunities(on: date, calendar: calendar)
        #expect(one.count == 8)
        #expect(one.allSatisfy { $0.activity.id == configuration.activities[0].id })
    }

    @Test func DSTMissingAndRepeatedHoursKeepBalancedActualOpportunities() throws {
        let calendar = testCalendar("America/Denver")
        let configuration = AppConfiguration(schedule: .init(weekdays: [1], startMinute: 0, endMinute: 480))
        for date in [utcDate("2026-03-08T12:00:00Z"), utcDate("2026-11-01T12:00:00Z")] {
            let slots = try ScheduleEngine(configuration: configuration).opportunities(on: date, calendar: calendar)
            #expect(Set(slots.map(\.id)).count == slots.count)
            #expect(Set(slots.prefix(configuration.activities.count).map(\.activity.id)).count == configuration.activities.count)
            #expect(zip(slots, slots.dropFirst()).allSatisfy { $0.activity.id != $1.activity.id })
            #expect(zip(slots, slots.dropFirst()).allSatisfy { $0.expiresAt == $1.scheduledAt })
        }
        let spring = try ScheduleEngine(configuration: configuration).opportunities(on: utcDate("2026-03-08T12:00:00Z"), calendar: calendar)
        #expect(spring.count == 7)
        #expect(!spring.contains { $0.minuteOfDay == 120 })
        let autumn = try ScheduleEngine(configuration: configuration).opportunities(on: utcDate("2026-11-01T12:00:00Z"), calendar: calendar)
        #expect(autumn.count == 8)
        #expect(autumn.filter { $0.minuteOfDay == 60 }.count == 1)
    }

    @Test func existingSessionSnapshotSurvivesActivityListChanges() throws {
        let date = utcDate("2026-09-21T09:05:00Z"), calendar = testCalendar()
        var configuration = AppConfiguration.standard
        let opportunity = try #require(try ScheduleEngine(configuration: configuration).current(at: date, calendar: calendar))
        let session = try SnackSession.start(opportunity: opportunity, activity: opportunity.activity, at: date)
        configuration.activities.removeAll { $0.id == opportunity.activity.id }
        _ = try ScheduleEngine(configuration: configuration).current(at: date, calendar: calendar)
        let restored = try AppDocument.decode(AppDocument(configuration: configuration, session: session).encoded())
        #expect(restored.session?.activity == opportunity.activity)
        #expect(restored.session?.opportunity == opportunity)
        #expect(restored.session?.completionDeadline == session.completionDeadline)
    }
}
