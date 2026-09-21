import MosslingCore

public struct ForestSnapshot: Equatable, Sendable {
    public let growth: Int
    public let stage: CompanionStage
    public let unlocks: [ForestUnlock]
    public let affinity: CompanionAffinity?

    public init(progress: CompanionProgress, affinity: CompanionAffinity?) {
        growth = progress.growth
        stage = progress.stage
        unlocks = progress.forestUnlocks
        self.affinity = affinity
    }
}

public struct ForestTransition: Equatable, Sendable {
    public enum Moment: Equatable, Sendable { case none, snack, discovery, evolution }
    public let from: ForestSnapshot?
    public let to: ForestSnapshot
    public let moment: Moment
    public let discoveries: [ForestUnlock]
}

/// Tracks presentation only. A new view starts at saved progress without replaying rewards.
public struct ForestPlayback: Sendable {
    private var presented: ForestSnapshot?
    public init() {}

    public mutating func receive(_ snapshot: ForestSnapshot, active: Bool, reduceMotion: Bool) -> ForestTransition {
        let previous = presented
        let discoveries = previous.map { old in snapshot.unlocks.filter { !old.unlocks.contains($0) } } ?? []
        let moment: ForestTransition.Moment
        if active, !reduceMotion, let previous, snapshot.growth > previous.growth {
            if snapshot.stage != previous.stage { moment = .evolution }
            else if !discoveries.isEmpty { moment = .discovery }
            else { moment = .snack }
        } else { moment = .none }
        // Hidden updates are presented on return. Once a moment starts, interruption
        // settles at the saved result instead of replaying it on every foreground.
        if presented == nil || active { presented = snapshot }
        return ForestTransition(from: previous, to: snapshot, moment: moment, discoveries: discoveries)
    }
}
