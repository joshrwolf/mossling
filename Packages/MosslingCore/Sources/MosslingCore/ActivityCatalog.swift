import Foundation

public enum ActivityFamily: String, CaseIterable, Sendable, Identifiable {
    case pushUps, squats, marching, sideSteps, walking, calfRaises, lunges
    case sideLegRaises, legCurls, kneeExtensions, toeRaises, punches, shoulders

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pushUps: "Push-ups"
        case .squats: "Squats"
        case .marching: "Marching"
        case .sideSteps: "Side steps"
        case .walking: "Walking"
        case .calfRaises: "Calf raises"
        case .lunges: "Lunges"
        case .sideLegRaises: "Side leg raises"
        case .legCurls: "Leg curls"
        case .kneeExtensions: "Knee extensions"
        case .toeRaises: "Toe raises"
        case .punches: "Punches"
        case .shoulders: "Shoulder movement"
        }
    }
    public var variations: [ActivityVariation] { ActivityCatalog.variations.filter { $0.family == self } }
    public var guidance: String {
        switch self {
        case .shoulders: "Choose a movement. Range and control matter more than difficulty."
        case .marching: "Seated and standing options. Choose the movement that fits your space."
        case .squats: "Chair stands and mini squats offer different support and range."
        case .sideSteps: "Step jacks stay grounded. Jumping jacks add impact."
        default: ""
        }
    }
}

public struct ActivityVariation: Identifiable, Equatable, Sendable {
    public let id: String
    public let family: ActivityFamily
    public let label: String
    public let equipment: String
    public let title: String
    public let instructions: String
    public let movement: ActivityMovement
    public let targetKind: ActivityTargetKind
    public let targetValue: Int

    public var activity: ActivityDefinition {
        ActivityDefinition(id: id, title: title, instructions: instructions, targetKind: targetKind,
                           targetValue: targetValue, movement: movement, catalogVariationID: id)
    }
}

public enum ActivityCatalog {
    public static func variation(id: String) -> ActivityVariation? { variations.first { $0.id == id } }

    public static let variations: [ActivityVariation] = {
        func base(_ movement: ActivityMovement, _ family: ActivityFamily, _ label: String,
                  _ equipment: String) -> ActivityVariation {
            let value = templates.first { $0.movement == movement }!
            return ActivityVariation(id: value.id, family: family, label: label, equipment: equipment,
                title: movement == .shoulderMobility ? "Arm circles" : value.title,
                instructions: movement == .shoulderMobility
                    ? "Extend your arms out to the sides below shoulder height. Trace small circles with your arms, then reverse direction halfway. Keep the movement within a comfortable range."
                    : value.instructions, movement: movement,
                targetKind: value.targetKind, targetValue: value.targetValue)
        }
        func variant(_ id: String, _ family: ActivityFamily, _ label: String, _ equipment: String,
                     _ title: String, _ movement: ActivityMovement, _ target: Int, _ instructions: String,
                     timed: Bool = false) -> ActivityVariation {
            ActivityVariation(id: id, family: family, label: label, equipment: equipment, title: title,
                instructions: instructions, movement: movement,
                targetKind: timed ? .duration : .repetitions, targetValue: target)
        }
        return [
            base(.wallPush, .pushUps, "Wall", "Wall"),
            variant("incline-push", .pushUps, "Incline", "Stable raised surface", "Incline push-ups", .inclinePush, 8,
                    "Place your hands on a stable raised surface. Keep your body straight, lower your chest toward the edge, then press back. A higher surface reduces the load."),
            variant("floor-push", .pushUps, "Floor", "Floor space", "Floor push-ups", .floorPush, 5,
                    "Hands beneath your shoulders, body straight from head to heels. Bend your elbows to lower your chest, then press back."),
            base(.chairStand, .squats, "Chair stand", "Stable chair"),
            base(.miniSquat, .squats, "Mini squat", "Stable support"),
            variant("squat", .squats, "Free squat", "Standing space", "Squats", .squat, 8,
                    "Stand with feet about shoulder-width apart. Bend your hips and knees, keeping your heels down and knees aligned with your toes. Stand back up."),
            variant("paused-squat", .squats, "Paused", "Standing space", "Paused squats", .squat, 6,
                    "Bend your hips and knees into a squat with heels down. Pause for two seconds at a comfortable depth, then stand up with control."),
            base(.seatedMarch, .marching, "Seated", "Stable chair"),
            base(.march, .marching, "Standing", "Standing space"),
            variant("brisk-march", .marching, "Brisk", "Standing space", "Brisk marching", .march, 60,
                    "March in place at a brisk, controlled pace. Swing the opposite arm with each step and keep your torso steady.", timed: true),
            base(.sideStep, .sideSteps, "Step-touch", "Room to step sideways"),
            base(.stepJack, .sideSteps, "Step jack", "Room to raise your arms"),
            variant("jumping-jack", .sideSteps, "Jumping jack", "Clear space · impact", "Jumping jacks", .jumpingJack, 30,
                    "Jump your feet apart as you raise your arms, then jump back with arms down. Land with knees slightly bent. Choose step jacks for a grounded option.", timed: true),
            base(.walk, .walking, "Steady", "Room to walk"),
            variant("brisk-walk", .walking, "Brisk", "Room to walk", "Brisk walking", .walk, 120,
                    "Walk at a brisk pace with a natural arm swing. Choose a clear route and a pace you can maintain for the snack.", timed: true),
            base(.calfRaise, .calfRaises, "Two legs", "Stable support"),
            variant("single-leg-calf-raise", .calfRaises, "Single leg", "Stable support", "Single-leg calf raises", .singleLegCalfRaise, 8,
                    "Hold a stable support and lift one foot. Rise onto the ball of your standing foot, then lower your heel with control. Switch legs halfway; each raise counts as one rep."),
            base(.reverseLunge, .lunges, "Supported", "Stable support"),
            variant("free-lunge", .lunges, "Unsupported", "Clear floor space", "Unsupported reverse lunges", .freeLunge, 8,
                    "Step one foot back and bend both knees within a comfortable range, keeping your front heel down. Return to standing and switch legs. Each return counts as one rep."),
            base(.sideLegRaise, .sideLegRaises, "Bodyweight", "Stable support"),
            variant("band-side-leg-raise", .sideLegRaises, "Band", "Loop band · stable support", "Band side leg raises", .bandSideLegRaise, 10,
                    "Place a light loop band around your ankles and hold a stable support. Lift one leg a short distance sideways with toes forward and hips level. Lower and alternate; each lift counts as one rep."),
            base(.legCurl, .legCurls, "Bodyweight", "Stable support"),
            variant("paused-leg-curl", .legCurls, "Paused", "Stable support", "Paused leg curls", .legCurl, 8,
                    "Hold a stable support. Bend one knee to lift your heel behind you, keeping your thighs side by side. Hold for two seconds, lower and switch. Each curl counts as one rep."),
            variant("weighted-leg-curl", .legCurls, "Weighted", "Light ankle weights · support", "Weighted leg curls", .weightedLegCurl, 8,
                    "Wear light, secured ankle weights and hold a stable support. Bend one knee to lift your heel behind you, keeping your thighs side by side. Lower and alternate; each curl counts as one rep."),
            base(.seatedKneeExtension, .kneeExtensions, "Bodyweight", "Stable chair"),
            variant("paused-knee-extension", .kneeExtensions, "Paused", "Stable chair", "Paused knee extensions", .seatedKneeExtension, 8,
                    "Sit upright and straighten one knee. Hold your foot up for two seconds, then lower with control. Alternate legs; each extension counts as one rep."),
            variant("weighted-knee-extension", .kneeExtensions, "Weighted", "Light ankle weights · chair", "Weighted knee extensions", .weightedKneeExtension, 8,
                    "Wear light, secured ankle weights and sit upright on a stable chair. Straighten one knee, then lower your foot with control. Alternate legs; each extension counts as one rep."),
            base(.seatedToeRaise, .toeRaises, "Seated", "Stable chair"),
            variant("standing-toe-raise", .toeRaises, "Standing", "Wall", "Standing toe raises", .standingToeRaise, 10,
                    "Rest your back against a wall with feet a short step forward. Keep both heels planted, lift the fronts of your feet, then lower with control."),
            base(.standingPunch, .punches, "Alternating", "Room to extend your arms"),
            variant("step-punch", .punches, "Step and punch", "Room to step sideways", "Step and punch", .stepPunch, 45,
                    "Step sideways as you punch forward with the opposite arm at chest height. Bring your foot and hand back, then switch sides. Keep your elbows slightly bent.", timed: true),
            base(.shoulderMobility, .shoulders, "Arm circles", "Room to extend your arms"),
            base(.wallSlide, .shoulders, "Wall slides", "Wall")
        ]
    }()

    /// Consolidate only the editable rotation. Session and event snapshots remain immutable.
    static func migratedRotation(_ activities: [ActivityDefinition]) -> [ActivityDefinition] {
        let identified = activities.map { activity -> ActivityDefinition in
            var value = activity
            if value.catalogVariationID == nil,
               let template = templates.first(where: { $0.id == value.id && $0.movement == value.movement && $0.targetKind == value.targetKind }) {
                value.catalogVariationID = template.id
            }
            return value
        }
        var winners: [ActivityFamily: String] = [:]
        for activity in identified {
            guard let family = activity.family else { continue }
            if winners[family] == nil { winners[family] = activity.id }
            if activity.isEnabled,
               let previous = identified.first(where: { $0.id == winners[family] }), !previous.isEnabled {
                winners[family] = activity.id
            }
        }
        return identified.compactMap { activity in
            guard let family = activity.family, winners[family] != activity.id else { return activity }
            // Keep an individually customized sibling as a custom activity.
            if let template = templates.first(where: { $0.id == activity.id }),
               activity.title != template.title || activity.instructions != template.instructions
                || activity.targetKind != template.targetKind || activity.targetValue != template.targetValue {
                var custom = activity
                custom.catalogVariationID = nil
                return custom
            }
            return nil
        }
    }
    static let startingTemplates: [ActivityDefinition] = [
        .init(id: "walk", title: "Walk", instructions: "Walk around your space at a comfortable pace.", targetKind: .duration, targetValue: 120),
        .init(id: "sit-to-stand", title: "Chair stands", instructions: "Stand up from a stable chair and sit back down with control. Use support as needed.", targetKind: .repetitions, targetValue: 8),
        .init(id: "wall-push", title: "Wall push-ups", instructions: "Place your hands on a stable wall. Bend and straighten your arms with control at a comfortable angle.", targetKind: .repetitions, targetValue: 8),
        .init(id: "calf-raise", title: "Calf raises", instructions: "Hold a stable support, rise onto your toes, then lower with control.", targetKind: .repetitions, targetValue: 10),
        .init(id: "easy-mobility", title: "Shoulder mobility", instructions: "Move your shoulders and arms through a comfortable, pain-free range.", targetKind: .duration, targetValue: 60)
    ]
    static let templates: [ActivityDefinition] = startingTemplates + [
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

extension AppConfiguration {
    /// A preview can reuse a saved family, but must never borrow a custom row's identity.
    public func activityDraft(for family: ActivityFamily) -> ActivityDefinition {
        if let existing = activities.first(where: { $0.family == family }) { return existing }
        var draft = family.variations[0].activity
        while activities.contains(where: { $0.id == draft.id }) { draft.id = UUID().uuidString }
        return draft
    }
}
