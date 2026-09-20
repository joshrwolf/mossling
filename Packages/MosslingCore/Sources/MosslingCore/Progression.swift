import Foundation

public struct SnackSession: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let opportunity: Opportunity
    public let activity: ActivityDefinition
    public private(set) var accumulatedSeconds: TimeInterval
    public private(set) var runningSince: Date?
    public private(set) var completed: Bool
    public let startedAt: Date?

    public init(id: UUID = UUID(), opportunity: Opportunity, activity: ActivityDefinition, accumulatedSeconds: TimeInterval = 0, runningSince: Date? = nil, completed: Bool = false, startedAt: Date? = nil) {
        self.id = id; self.opportunity = opportunity; self.activity = activity
        self.accumulatedSeconds = accumulatedSeconds.isFinite ? max(0, accumulatedSeconds) : 0
        self.runningSince = completed ? nil : runningSince; self.completed = completed; self.startedAt = startedAt
    }
    public static let completionGrace: TimeInterval = 5 * 60

    /// Only a validated, persisted start receives grace. Legacy sessions keep their deadline.
    public var completionDeadline: Date {
        guard let startedAt, opportunity.isActive(at: startedAt) else { return opportunity.expiresAt }
        return opportunity.expiresAt.addingTimeInterval(Self.completionGrace)
    }

    public static func start(opportunity: Opportunity, activity: ActivityDefinition, at date: Date) throws -> Self {
        try SessionStartValidator.validate(opportunity: opportunity, activity: activity, at: date)
        return Self(opportunity: opportunity, activity: activity, runningSince: date, startedAt: date)
    }

    public func elapsed(at date: Date) -> TimeInterval {
        let safeAccumulated = accumulatedSeconds.isFinite ? max(0, accumulatedSeconds) : 0
        return safeAccumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    public mutating func pause(at date: Date) {
        accumulatedSeconds = elapsed(at: date); runningSince = nil
    }
    public mutating func resume(at date: Date) {
        guard !completed, runningSince == nil else { return }
        runningSince = date
    }
    public mutating func markCompleted(at date: Date) {
        pause(at: date); completed = true
    }
}

public enum CompletionError: Error, LocalizedError, Equatable, Sendable {
    case alreadyCompleted, notStarted, expired, timerIncomplete, invalidActivity, insufficientTime
    public var errorDescription: String? {
        switch self {
        case .alreadyCompleted: "This snack is already complete."
        case .notStarted: "This snack is not available yet."
        case .expired: "This snack has expired."
        case .timerIncomplete: "Let the activity timer finish before confirming."
        case .invalidActivity: "This activity needs a valid target."
        case .insufficientTime: "Choose a shorter activity to finish within this snack’s five-minute grace period."
        }
    }
}

public enum SessionStartValidator {
    public static func validate(opportunity: Opportunity, activity: ActivityDefinition, at date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite, date >= opportunity.scheduledAt else { throw CompletionError.notStarted }
        guard opportunity.isActive(at: date) else { throw CompletionError.expired }
        guard (try? activity.validate()) != nil else { throw CompletionError.invalidActivity }
        if activity.targetKind == .duration,
           date.addingTimeInterval(Double(activity.targetValue)) >= opportunity.expiresAt.addingTimeInterval(SnackSession.completionGrace) {
            throw CompletionError.insufficientTime
        }
    }
}

public enum CompletionValidator {
    public static func validate(session: SnackSession, completedAt date: Date) throws {
        guard !session.completed else { throw CompletionError.alreadyCompleted }
        guard date.timeIntervalSinceReferenceDate.isFinite, date >= session.opportunity.scheduledAt,
              session.startedAt.map({ date >= $0 }) ?? true else { throw CompletionError.notStarted }
        guard date < session.completionDeadline else { throw CompletionError.expired }
        guard (try? session.activity.validate()) != nil else { throw CompletionError.invalidActivity }
        if session.activity.targetKind == .duration, session.elapsed(at: date) < Double(session.activity.targetValue) {
            throw CompletionError.timerIncomplete
        }
    }
}

public struct CompletionEvent: Codable, Equatable, Sendable, Identifiable {
    public let eventID: UUID
    public let sessionID: UUID
    public let opportunityID: String
    public let rewardKey: String
    public let scheduledAt: Date
    public let completedAt: Date
    public let activity: ActivityDefinition
    public let sourceDeviceID: UUID
    public var id: UUID { eventID }

    public init(eventID: UUID = UUID(), sessionID: UUID, opportunityID: String, rewardKey: String, scheduledAt: Date, completedAt: Date, activity: ActivityDefinition, sourceDeviceID: UUID) {
        self.eventID = eventID; self.sessionID = sessionID; self.opportunityID = opportunityID; self.rewardKey = rewardKey
        self.scheduledAt = scheduledAt; self.completedAt = completedAt; self.activity = activity; self.sourceDeviceID = sourceDeviceID
    }

    fileprivate var isStructurallyValid: Bool {
        guard scheduledAt.timeIntervalSinceReferenceDate.isFinite, completedAt.timeIntervalSinceReferenceDate.isFinite,
              completedAt >= scheduledAt, (try? activity.validate()) != nil,
              opportunityID.count == 16, rewardKey.count == 14 else { return false }
        let components = opportunityID.split(separator: "-")
        guard components.count == 4, components[0].count == 4, components[1].count == 2, components[2].count == 2,
              Int(components[0]) != nil, let month = Int(components[1]), (1...12).contains(month),
              let day = Int(components[2]), (1...31).contains(day), components[3].first == "m",
              let minute = Int(components[3].dropFirst()), (0..<1440).contains(minute) else { return false }
        return rewardKey == "\(opportunityID.prefix(10))-h\(String(format: "%02d", minute / 60))"
    }

    fileprivate var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

public enum CompanionStage: String, Codable, CaseIterable, Sendable {
    case seedling, sprout, guardian, groveKeeper
    public var title: String {
        switch self { case .seedling: "Seedling"; case .sprout: "Sprout"; case .guardian: "Forest guardian"; case .groveKeeper: "Grove keeper" }
    }
    public var minimumGrowth: Int {
        switch self { case .seedling: 0; case .sprout: 30; case .guardian: 150; case .groveKeeper: 1_200 }
    }
    public var visualLevel: Int {
        switch self { case .seedling: 0; case .sprout: 1; case .guardian: 2; case .groveKeeper: 3 }
    }
}
public enum ForestUnlock: String, Codable, CaseIterable, Sendable {
    case fern, mushrooms, pond, wildflowers, steppingStones, lanterns
    public var title: String {
        switch self {
        case .fern: "Little fern"; case .mushrooms: "Mushroom friends"; case .pond: "Quiet pond"
        case .wildflowers: "Wildflower meadow"; case .steppingStones: "Woodland stepping stones"; case .lanterns: "Welcoming lanterns"
        }
    }
    public var requiredGrowth: Int {
        switch self {
        case .fern: 10; case .mushrooms: 50; case .pond: 100
        case .wildflowers: 300; case .steppingStones: 600; case .lanterns: 900
        }
    }
    public var symbolName: String {
        switch self {
        case .fern: "leaf"; case .mushrooms: "sparkles"; case .pond: "water.waves"
        case .wildflowers: "camera.macro"; case .steppingStones: "circle.grid.2x2"; case .lanterns: "lamp.desk"
        }
    }
}

/// A reversible cosmetic preference, synchronized by the phone with other settings.
public enum CompanionAffinity: String, Codable, CaseIterable, Sendable {
    case sunlit, moonlit
    public var title: String { self == .sunlit ? "Sunlit" : "Moonlit" }
    public var detail: String {
        self == .sunlit ? "Golden light, warm blossoms, and a sunny clearing." : "Moonlight, cool blossoms, and a starlit clearing."
    }
}

public struct ProgressionMilestone: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let requiredGrowth: Int
    public let symbolName: String
    public var requiredSnackCount: Int { requiredGrowth / ProgressionCatalog.growthPerSnack }
}

/// Content revisions are independent of the permanent reward economy. Append milestones;
/// never move an existing threshold upward or reinterpret previously earned reward keys.
public enum ProgressionCatalog {
    public static let version = 2
    public static let rewardRuleVersion = 1
    public static let growthPerSnack = 10
    public static let affinityGrowth = CompanionStage.sprout.minimumGrowth
    public static let milestones: [ProgressionMilestone] = (
        CompanionStage.allCases.filter { $0 != .seedling }.map {
            ProgressionMilestone(id: "stage.\($0.rawValue)", title: $0.title,
                requiredGrowth: $0.minimumGrowth, symbolName: "sparkles")
        } + ForestUnlock.allCases.map {
            ProgressionMilestone(id: "forest.\($0.rawValue)", title: $0.title,
                requiredGrowth: $0.requiredGrowth, symbolName: $0.symbolName)
        }
    ).sorted {
        $0.requiredGrowth == $1.requiredGrowth ? $0.id < $1.id : $0.requiredGrowth < $1.requiredGrowth
    }
}

public struct CompanionProgress: Codable, Equatable, Sendable {
    public let completedSnackCount: Int
    public let growth: Int
    public let stage: CompanionStage
    public let forestUnlocks: [ForestUnlock]
    public let rewardRuleVersion: Int
    public var catalogVersion: Int { ProgressionCatalog.version }
    public var canChooseAffinity: Bool { growth >= ProgressionCatalog.affinityGrowth }
    public var unlockedMilestones: [ProgressionMilestone] {
        ProgressionCatalog.milestones.filter { $0.requiredGrowth <= growth }
    }
    public var nextMilestone: ProgressionMilestone? {
        ProgressionCatalog.milestones.first { $0.requiredGrowth > growth }
    }
    public func milestones(since previous: CompanionProgress) -> [ProgressionMilestone] {
        unlockedMilestones.filter { $0.requiredGrowth > previous.growth }
    }
    public var nextStageGrowth: Int? {
        CompanionStage.allCases.map(\.minimumGrowth).filter { $0 > growth }.min()
    }
    public var stageProgress: Double {
        guard let target = nextStageGrowth else { return 1 }
        return min(1, max(0, Double(growth - stage.minimumGrowth) / Double(target - stage.minimumGrowth)))
    }
    fileprivate init(uniqueRewards: Int) {
        completedSnackCount = uniqueRewards
        let earnedGrowth = uniqueRewards * ProgressionCatalog.growthPerSnack
        growth = earnedGrowth
        stage = CompanionStage.allCases.filter { $0.minimumGrowth <= earnedGrowth }.max { $0.minimumGrowth < $1.minimumGrowth } ?? .seedling
        forestUnlocks = ForestUnlock.allCases.filter { $0.requiredGrowth <= earnedGrowth }
        rewardRuleVersion = ProgressionCatalog.rewardRuleVersion
    }
}

public struct CompletionLedger: Codable, Equatable, Sendable {
    public private(set) var events: [CompletionEvent]
    public init(events: [CompletionEvent] = []) { self.events = []; merge(events) }
    public mutating func merge(_ incoming: [CompletionEvent]) {
        var byID: [UUID: CompletionEvent] = [:]
        for event in (events + incoming) where event.isStructurallyValid {
            if let existing = byID[event.eventID] {
                // Commutative deterministic conflict handling; no dependence on transport order.
                if event.canonicalData.lexicographicallyPrecedes(existing.canonicalData) { byID[event.eventID] = event }
            } else { byID[event.eventID] = event }
        }
        events = byID.values.sorted { left, right in
            left.completedAt == right.completedAt ? left.eventID.uuidString < right.eventID.uuidString : left.completedAt < right.completedAt
        }
    }
    public var progress: CompanionProgress { CompanionProgress(uniqueRewards: Set(events.filter(\.isStructurallyValid).map(\.rewardKey)).count) }
    public func containsReward(key: String) -> Bool { events.contains { $0.rewardKey == key && $0.isStructurallyValid } }

    private enum CodingKeys: String, CodingKey { case events }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(events: try container.decode([CompletionEvent].self, forKey: .events))
    }
}
