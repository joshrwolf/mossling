import Foundation

public enum ConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case invalidWeekdays, emptyWeekdays, invalidWindow, invalidInterval, tooManySlots
    case invalidActivity(String), duplicateActivityIDs, noEnabledActivities, invalidCompanionName, invalidRevision, invalidDailyOverride

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
        case .invalidDailyOverride: "The temporary routine change could not be validated."
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

/// Stable movement identity, independent of editable coaching copy and targets.
public enum ActivityMovement: String, Codable, CaseIterable, Sendable {
    case walk, chairStand, wallPush, calfRaise, shoulderMobility
    case march, sideStep, stepJack, miniSquat, reverseLunge, sideLegRaise
    case legCurl, seatedKneeExtension, seatedMarch, seatedToeRaise, wallSlide, standingPunch
    case custom

    public var title: String {
        switch self {
        case .walk: "Walk"
        case .chairStand: "Chair stands"
        case .wallPush: "Wall push-ups"
        case .calfRaise: "Calf raises"
        case .shoulderMobility: "Shoulder mobility"
        case .march: "March in place"
        case .sideStep: "Side steps"
        case .stepJack: "Step jacks"
        case .miniSquat: "Mini squats"
        case .reverseLunge: "Reverse lunges"
        case .sideLegRaise: "Side leg raises"
        case .legCurl: "Standing leg curls"
        case .seatedKneeExtension: "Seated knee extensions"
        case .seatedMarch: "Seated marching"
        case .seatedToeRaise: "Seated toe raises"
        case .wallSlide: "Wall slides"
        case .standingPunch: "Standing punches"
        case .custom: "Custom activity"
        }
    }

    static func initial(for id: String) -> Self {
        switch id {
        case "walk": .walk
        case "sit-to-stand": .chairStand
        case "wall-push": .wallPush
        case "calf-raise": .calfRaise
        case "easy-mobility": .shoulderMobility
        case "march": .march
        case "side-step": .sideStep
        case "step-jack": .stepJack
        case "mini-squat": .miniSquat
        case "reverse-lunge": .reverseLunge
        case "side-leg-raise": .sideLegRaise
        case "leg-curl": .legCurl
        case "seated-knee-extension": .seatedKneeExtension
        case "seated-march": .seatedMarch
        case "seated-toe-raise": .seatedToeRaise
        case "wall-slide": .wallSlide
        case "standing-punch": .standingPunch
        default: .custom
        }
    }
}

public struct ActivityDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var instructions: String
    public var targetKind: ActivityTargetKind
    public var targetValue: Int
    public var isEnabled: Bool
    public var movement: ActivityMovement

    public init(id: String, title: String, instructions: String, targetKind: ActivityTargetKind, targetValue: Int, isEnabled: Bool = true, movement: ActivityMovement? = nil) {
        self.id = id; self.title = title; self.instructions = instructions
        self.targetKind = targetKind; self.targetValue = targetValue; self.isEnabled = isEnabled
        self.movement = movement ?? .initial(for: id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, instructions, targetKind, targetValue, isEnabled, movement
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        instructions = try values.decode(String.self, forKey: .instructions)
        targetKind = try values.decode(ActivityTargetKind.self, forKey: .targetKind)
        targetValue = try values.decode(Int.self, forKey: .targetValue)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        movement = try values.decodeIfPresent(ActivityMovement.self, forKey: .movement) ?? .initial(for: id)
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80,
              !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.count <= 1000,
              targetValue > 0, targetValue <= (targetKind == .duration ? 3600 : 1000)
        else { throw ConfigurationError.invalidActivity(id) }
    }

    public static let starters: [Self] = [
        .init(id: "walk", title: "Walk", instructions: "Walk around your space at a comfortable pace.", targetKind: .duration, targetValue: 120),
        .init(id: "sit-to-stand", title: "Chair stands", instructions: "Stand up from a stable chair and sit back down with control. Use support as needed.", targetKind: .repetitions, targetValue: 8),
        .init(id: "wall-push", title: "Wall push-ups", instructions: "Place your hands on a stable wall. Bend and straighten your arms with control at a comfortable angle.", targetKind: .repetitions, targetValue: 8),
        .init(id: "calf-raise", title: "Calf raises", instructions: "Hold a stable support, rise onto your toes, then lower with control.", targetKind: .repetitions, targetValue: 10),
        .init(id: "easy-mobility", title: "Shoulder mobility", instructions: "Move your shoulders and arms through a comfortable, pain-free range.", targetKind: .duration, targetValue: 60)
    ]
    /// Available to every installation; adding a catalog activity is a normal configuration save.
    public static let catalog: [Self] = starters + [
        .init(id: "march", title: "March in place", instructions: "Stand tall and alternate lifting your knees. Swing the opposite arm with each step and keep a steady pace.", targetKind: .duration, targetValue: 60, movement: .march),
        .init(id: "side-step", title: "Side steps", instructions: "Step to one side, bring the other foot in, then return the other way. Keep your knees slightly bent and avoid crossing your feet.", targetKind: .duration, targetValue: 60, movement: .sideStep),
        .init(id: "step-jack", title: "Step jacks", instructions: "Step one foot out as you raise both arms, then bring it back as you lower them. Alternate sides without jumping; raise your arms only as far as comfortable.", targetKind: .duration, targetValue: 45, movement: .stepJack),
        .init(id: "mini-squat", title: "Mini squats", instructions: "Hold a stable chair back. Bend your knees and hips a short way, keeping your heels down and knees aligned with your toes. Stand back up with control.", targetKind: .repetitions, targetValue: 8, movement: .miniSquat),
        .init(id: "reverse-lunge", title: "Reverse lunges", instructions: "Hold a stable support. Step one foot back and bend both knees a short way, keeping your front heel down. Return to standing and switch legs. Each return counts as one rep.", targetKind: .repetitions, targetValue: 8, movement: .reverseLunge),
        .init(id: "side-leg-raise", title: "Side leg raises", instructions: "Hold a stable chair back. Lift one leg a short distance to the side with toes facing forward and hips level, then lower it. Alternate legs; each lift counts as one rep.", targetKind: .repetitions, targetValue: 10, movement: .sideLegRaise),
        .init(id: "leg-curl", title: "Standing leg curls", instructions: "Hold a stable chair back. Bend one knee to bring your heel up behind you, keeping your thighs side by side. Lower and switch legs. Each curl counts as one rep.", targetKind: .repetitions, targetValue: 10, movement: .legCurl),
        .init(id: "seated-knee-extension", title: "Seated knee extensions", instructions: "Sit upright on a stable chair with your feet on the floor. Straighten one knee to lift your foot, then lower with control. Alternate legs; each extension counts as one rep.", targetKind: .repetitions, targetValue: 10, movement: .seatedKneeExtension),
        .init(id: "seated-march", title: "Seated marching", instructions: "Sit upright on a stable chair. Lift one knee with the leg bent, lower your foot, then switch sides. Keep your torso steady and continue at a comfortable pace.", targetKind: .duration, targetValue: 60, movement: .seatedMarch),
        .init(id: "seated-toe-raise", title: "Seated toe raises", instructions: "Sit on a stable chair with both feet flat. Keep your heels down, lift the fronts of both feet, then lower them. Each lift and lower counts as one rep.", targetKind: .repetitions, targetValue: 12, movement: .seatedToeRaise),
        .init(id: "wall-slide", title: "Wall slides", instructions: "Face a wall with your forearms resting against it. Slide your arms upward within a comfortable range, then back down. Keep your ribs down and avoid arching your back.", targetKind: .repetitions, targetValue: 8, movement: .wallSlide),
        .init(id: "standing-punch", title: "Standing punches", instructions: "Stand with feet apart and knees slightly bent. Alternate punching forward at chest height, drawing each hand back. Keep your elbows soft rather than locking them.", targetKind: .duration, targetValue: 45, movement: .standingPunch)
    ]

}

/// Temporary changes use an absolute deadline captured at the originating phone's next
/// local midnight. Travel and DST therefore cannot extend a pause indefinitely.
public struct DailyRoutineOverride: Codable, Equatable, Sendable {
    public var expiresAt: Date
    public var pausedForDay: Bool
    public var skippedRewardKeys: Set<String>

    public init(expiresAt: Date, pausedForDay: Bool = false, skippedRewardKeys: Set<String> = []) {
        self.expiresAt = expiresAt; self.pausedForDay = pausedForDay; self.skippedRewardKeys = skippedRewardKeys
    }

    public func validate() throws {
        guard expiresAt.timeIntervalSinceReferenceDate.isFinite, skippedRewardKeys.count <= 24 else {
            throw ConfigurationError.invalidDailyOverride
        }
        for key in skippedRewardKeys {
            let parts = key.split(separator: "-")
            guard key.count == 14, parts.count == 4,
                  parts[0].count == 4, Int(parts[0]) != nil,
                  parts[1].count == 2, let month = Int(parts[1]), (1...12).contains(month),
                  parts[2].count == 2, let day = Int(parts[2]), (1...31).contains(day),
                  parts[3].count == 3, parts[3].first == "h",
                  let hour = Int(parts[3].dropFirst()), (0...23).contains(hour) else {
                throw ConfigurationError.invalidDailyOverride
            }
        }
    }

}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var revision: Int
    public var companionName: String
    public var schedule: ScheduleConfiguration
    public var activities: [ActivityDefinition]
    public var dailyOverride: DailyRoutineOverride?
    public var companionAffinity: CompanionAffinity?
    public var world: ForestWorld
    public static let standard = Self()

    public init(revision: Int = 0, companionName: String = "Moss", schedule: ScheduleConfiguration = .standard, activities: [ActivityDefinition] = ActivityDefinition.starters, dailyOverride: DailyRoutineOverride? = nil, companionAffinity: CompanionAffinity? = nil, world: ForestWorld = ForestWorld()) {
        self.revision = revision; self.companionName = companionName; self.schedule = schedule; self.activities = activities; self.dailyOverride = dailyOverride
        self.companionAffinity = companionAffinity
        self.world = world
    }

    public func isPaused(at date: Date) -> Bool {
        guard let dailyOverride, date < dailyOverride.expiresAt else { return false }
        return dailyOverride.pausedForDay
    }

    public func isSkipped(_ opportunity: Opportunity, at date: Date) -> Bool {
        guard let dailyOverride, date < dailyOverride.expiresAt else { return false }
        return dailyOverride.skippedRewardKeys.contains(opportunity.rewardKey)
    }

    public func isSuppressed(_ opportunity: Opportunity, at date: Date) -> Bool {
        isPaused(at: date) || isSkipped(opportunity, at: date)
    }

    /// Caller increments configuration revision in the same durable transaction.
    public mutating func pauseForToday(at date: Date, calendar: Calendar) throws {
        try prepareDailyOverride(at: date, calendar: calendar)
        dailyOverride?.pausedForDay = true
    }

    public mutating func skip(_ opportunity: Opportunity, at date: Date, calendar: Calendar) throws {
        guard opportunity.isActive(at: date) else { throw CompletionError.expired }
        try prepareDailyOverride(at: date, calendar: calendar)
        dailyOverride?.skippedRewardKeys.insert(opportunity.rewardKey)
        try dailyOverride?.validate()
    }

    public mutating func resumeToday(at date: Date) {
        guard let dailyOverride, date < dailyOverride.expiresAt else { self.dailyOverride = nil; return }
        self.dailyOverride?.pausedForDay = false
    }

    private mutating func prepareDailyOverride(at date: Date, calendar: Calendar) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let midnight = calendar.dateInterval(of: .day, for: date)?.end else {
            throw ConfigurationError.invalidDailyOverride
        }
        if dailyOverride == nil || date >= dailyOverride!.expiresAt {
            dailyOverride = DailyRoutineOverride(expiresAt: midnight)
        }
    }

    public func validate() throws {
        guard revision >= 0 else { throw ConfigurationError.invalidRevision }
        let name = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw ConfigurationError.invalidCompanionName }
        try world.validate()
        try schedule.validate()
        try dailyOverride?.validate()
        guard Set(activities.map(\.id)).count == activities.count else { throw ConfigurationError.duplicateActivityIDs }
        for activity in activities { try activity.validate() }
        guard !schedule.enabled || activities.contains(where: \.isEnabled) else { throw ConfigurationError.noEnabledActivities }
    }
}
