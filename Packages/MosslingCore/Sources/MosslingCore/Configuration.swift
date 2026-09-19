import Foundation

public enum ConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case invalidWeekdays, emptyWeekdays, invalidWindow, invalidInterval, tooManySlots
    case invalidActivity(String), duplicateActivityIDs, noEnabledActivities, invalidCompanionName, invalidRevision

    public var errorDescription: String? {
        switch self {
        case .invalidWeekdays: "Choose valid days of the week."
        case .emptyWeekdays: "Choose at least one day."
        case .invalidWindow: "The end of the active window must follow its start on the same day."
        case .invalidInterval: "Choose a 60, 90, or 120 minute interval."
        case .tooManySlots: "Choose at most 56 weekly reminders by shortening the window or increasing the interval."
        case .invalidActivity(let id): "Check the name, instructions, and target for activity \(id)."
        case .duplicateActivityIDs: "Activities must have unique identifiers."
        case .noEnabledActivities: "Enable at least one activity."
        case .invalidCompanionName: "Give your companion a name of 1–40 characters."
        case .invalidRevision: "Configuration revision cannot be negative."
        }
    }
}

public struct RecurringSlot: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var weekday: Int
    public var minuteOfDay: Int
    public var id: String { "w\(weekday)-m\(minuteOfDay)" }
    public init(weekday: Int, minuteOfDay: Int) { self.weekday = weekday; self.minuteOfDay = minuteOfDay }
}

public struct ScheduleConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    public var intervalMinutes: Int
    public static let standard = Self()

    public init(enabled: Bool = true, weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 540, endMinute: Int = 1020, intervalMinutes: Int = 60) {
        self.enabled = enabled; self.weekdays = weekdays; self.startMinute = startMinute
        self.endMinute = endMinute; self.intervalMinutes = intervalMinutes
    }

    public func validate() throws {
        guard weekdays.allSatisfy({ (1...7).contains($0) }) else { throw ConfigurationError.invalidWeekdays }
        guard !enabled || !weekdays.isEmpty else { throw ConfigurationError.emptyWeekdays }
        guard (0..<1440).contains(startMinute), (1...1440).contains(endMinute), startMinute < endMinute else { throw ConfigurationError.invalidWindow }
        guard [60, 90, 120].contains(intervalMinutes) else { throw ConfigurationError.invalidInterval }
        let dailyCount = (endMinute - startMinute + intervalMinutes - 1) / intervalMinutes
        guard dailyCount * weekdays.count <= 56 else { throw ConfigurationError.tooManySlots }
    }

    public var recurringSlots: [RecurringSlot] {
        guard enabled, (try? validate()) != nil else { return [] }
        return weekdays.sorted().flatMap { weekday in
            stride(from: startMinute, to: endMinute, by: intervalMinutes).map {
                RecurringSlot(weekday: weekday, minuteOfDay: $0)
            }
        }
    }
}

public enum ActivityTargetKind: String, Codable, CaseIterable, Sendable {
    case duration, repetitions
}

public struct ActivityDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var instructions: String
    public var targetKind: ActivityTargetKind
    public var targetValue: Int
    public var isEnabled: Bool

    public init(id: String, title: String, instructions: String, targetKind: ActivityTargetKind, targetValue: Int, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.instructions = instructions
        self.targetKind = targetKind; self.targetValue = targetValue; self.isEnabled = isEnabled
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80,
              !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.count <= 1000,
              targetValue > 0, targetValue <= (targetKind == .duration ? 3600 : 1000)
        else { throw ConfigurationError.invalidActivity(id) }
    }

    public static let starters: [Self] = [
        .init(id: "walk", title: "A little wander", instructions: "Take an easy walk around your space. Choose a comfortable pace.", targetKind: .duration, targetValue: 120),
        .init(id: "sit-to-stand", title: "Up and down", instructions: "Stand up from a stable chair and sit back down with control. Use support as needed.", targetKind: .repetitions, targetValue: 8),
        .init(id: "wall-push", title: "Wall push-ups", instructions: "With your hands on a stable wall, gently bend and straighten your arms at a comfortable angle.", targetKind: .repetitions, targetValue: 8),
        .init(id: "calf-raise", title: "Reach a little taller", instructions: "Hold a stable support, rise onto your toes, then lower gently.", targetKind: .repetitions, targetValue: 10),
        .init(id: "easy-mobility", title: "Loosen the leaves", instructions: "Move your shoulders and arms gently through a comfortable range. Keep it easy and pain-free.", targetKind: .duration, targetValue: 60)
    ]
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var revision: Int
    public var companionName: String
    public var schedule: ScheduleConfiguration
    public var activities: [ActivityDefinition]
    public static let standard = Self()

    public init(revision: Int = 0, companionName: String = "Moss", schedule: ScheduleConfiguration = .standard, activities: [ActivityDefinition] = ActivityDefinition.starters) {
        self.revision = revision; self.companionName = companionName; self.schedule = schedule; self.activities = activities
    }

    public func validate() throws {
        guard revision >= 0 else { throw ConfigurationError.invalidRevision }
        let name = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw ConfigurationError.invalidCompanionName }
        try schedule.validate()
        guard Set(activities.map(\.id)).count == activities.count else { throw ConfigurationError.duplicateActivityIDs }
        for activity in activities { try activity.validate() }
        guard !schedule.enabled || activities.contains(where: \.isEnabled) else { throw ConfigurationError.noEnabledActivities }
    }
}
