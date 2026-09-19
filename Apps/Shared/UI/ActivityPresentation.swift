import MosslingCore

extension ActivityDefinition {
    var targetSummary: String {
        switch targetKind {
        case .repetitions: "\(targetValue) reps"
        case .duration:
            targetValue.isMultiple(of: 60) ? "\(targetValue / 60) min" : "\(targetValue) sec"
        }
    }
}
