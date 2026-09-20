import Foundation

public struct Opportunity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let rewardKey: String
    public let scheduledAt: Date
    public let expiresAt: Date
    public let activity: ActivityDefinition
    public let dayKey: String
    public let minuteOfDay: Int

    public init(id: String, rewardKey: String, scheduledAt: Date, expiresAt: Date, activity: ActivityDefinition, dayKey: String, minuteOfDay: Int) {
        self.id = id; self.rewardKey = rewardKey; self.scheduledAt = scheduledAt; self.expiresAt = expiresAt
        self.activity = activity; self.dayKey = dayKey; self.minuteOfDay = minuteOfDay
    }
    public func isActive(at date: Date) -> Bool { date >= scheduledAt && date < expiresAt }
}

public struct ScheduleEngine: Sendable {
    public let configuration: AppConfiguration
    public init(configuration: AppConfiguration) { self.configuration = configuration }

    public func opportunities(on day: Date, calendar suppliedCalendar: Calendar) throws -> [Opportunity] {
        try configuration.validate()
        let schedule = configuration.schedule
        guard schedule.enabled else { return [] }
        let calendar = Self.gregorian(suppliedCalendar)
        guard schedule.weekdays.contains(calendar.component(.weekday, from: day)) else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { return [] }
        let dayKey = String(format: "%04d-%02d-%02d", year, month, dayNumber)
        // Search in civil time with strict matching: spring-forward gaps produce no slot.
        // First repeated time gives one opportunity during a fall-back hour.
        let slots: [(minute: Int, date: Date)] = stride(from: schedule.startMinute, to: schedule.endMinute, by: schedule.intervalMinutes).compactMap { minute in
            guard let date = calendar.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0), matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward), date < tomorrow else { return nil }
            return (minute, date)
        }
        let end: Date
        if schedule.endMinute == 1440 { end = tomorrow }
        else {
            guard let date = calendar.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(hour: schedule.endMinute / 60, minute: schedule.endMinute % 60, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) else { return [] }
            end = min(date, tomorrow)
        }
        let activities = configuration.activities.filter(\.isEnabled).sorted { $0.id < $1.id }
        guard !activities.isEmpty else { return [] }
        // Rotate through the canonical enabled list. A stable daily offset adds variety
        // while keeping phone/watch suggestions identical without completion history.
        // The guarantee is per day's scheduled suggestions, not manual substitutions.
        let dailyOffset = Int(Self.stableHash(dayKey) % UInt64(activities.count))
        return slots.enumerated().compactMap { index, slot in
            let expiresAt = index + 1 < slots.count ? min(slots[index + 1].date, end) : end
            guard slot.date < expiresAt else { return nil }
            let id = "\(dayKey)-m\(String(format: "%04d", slot.minute))"
            let rewardKey = "\(dayKey)-h\(String(format: "%02d", slot.minute / 60))"
            let activityIndex = (dailyOffset + index) % activities.count
            return Opportunity(id: id, rewardKey: rewardKey, scheduledAt: slot.date, expiresAt: expiresAt, activity: activities[activityIndex], dayKey: dayKey, minuteOfDay: slot.minute)
        }
    }

    public func current(at date: Date, calendar: Calendar) throws -> Opportunity? {
        try opportunities(on: date, calendar: calendar).first {
            $0.isActive(at: date) && !configuration.isSuppressed($0, at: date)
        }
    }

    public func next(after date: Date, calendar suppliedCalendar: Calendar) throws -> Opportunity? {
        try configuration.validate()
        let calendar = Self.gregorian(suppliedCalendar)
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if let opportunity = try opportunities(on: day, calendar: calendar).first(where: { $0.scheduledAt > date && !configuration.isSuppressed($0, at: $0.scheduledAt) }) { return opportunity }
        }
        return nil
    }

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = calendar.timeZone
        result.locale = calendar.locale
        return result
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// A bounded, dated plan: temporary skips and pauses can expire while the app is closed.
/// The platform refreshes this horizon on launch, foreground, and durable routine changes.
public struct ReminderPlan: Equatable, Sendable {
    public static let maximumReminders = 56
    public let opportunities: [Opportunity]
    public let currentOpportunity: Opportunity?
    public let coverageEnd: Date

    public init(configuration: AppConfiguration, at date: Date, calendar: Calendar,
                completedRewardKeys: Set<String> = []) throws {
        try configuration.validate()
        let engine = ScheduleEngine(configuration: configuration)
        let start = calendar.startOfDay(for: date)
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            throw ConfigurationError.invalidDailyOverride
        }
        var future: [Opportunity] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            future += try engine.opportunities(on: day, calendar: calendar).filter {
                $0.scheduledAt > date && $0.scheduledAt < end
                    && !configuration.isSuppressed($0, at: $0.scheduledAt)
                    && !completedRewardKeys.contains($0.rewardKey)
            }
        }
        opportunities = Array(future.prefix(Self.maximumReminders))
        coverageEnd = future.count > Self.maximumReminders ? future[Self.maximumReminders].scheduledAt : end
        let current = try engine.current(at: date, calendar: calendar)
        currentOpportunity = current.flatMap { completedRewardKeys.contains($0.rewardKey) ? nil : $0 }
    }
}
