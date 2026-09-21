import MosslingCore

extension CompanionStage {
    var artwork: String {
        switch self {
        case .seedling: "MossSeedling"
        case .sprout: "MossSprout"
        case .guardian: "MossGuardian"
        case .groveKeeper: "MossKeeper"
        }
    }

    var sceneHeight: Double {
        switch self {
        case .seedling: 124
        case .sprout: 158
        case .guardian: 180
        case .groveKeeper: 198
        }
    }
}
