import SwiftUI
import SpriteKit
import MosslingCore

/// Movement identity selects artwork independently of editable activity copy.
@MainActor
private enum ActivityArtwork {
    private static let atlas = SKTexture(imageNamed: "BrackenActivities")
    private static var images: [ActivityMovement: CGImage] = [:]

    static func image(for activity: ActivityDefinition) -> CGImage {
        if let image = images[activity.movement] { return image }
        let index: Int
        switch activity.movement {
        case .walk: index = 0
        case .chairStand: index = 1
        case .wallPush: index = 2
        case .calfRaise: index = 3
        case .shoulderMobility: index = 4
        case .march: return individual("BrackenMarch", movement: .march)
        case .sideStep: return individual("BrackenSideStep", movement: .sideStep)
        case .stepJack: return individual("BrackenStepJack", movement: .stepJack)
        case .miniSquat: return individual("BrackenMiniSquat", movement: .miniSquat)
        case .reverseLunge: return individual("BrackenReverseLunge", movement: .reverseLunge)
        case .sideLegRaise: return individual("BrackenSideLegRaise", movement: .sideLegRaise)
        case .legCurl: return individual("BrackenLegCurl", movement: .legCurl)
        case .seatedKneeExtension: return individual("BrackenSeatedKneeExtension", movement: .seatedKneeExtension)
        case .seatedMarch: return individual("BrackenSeatedMarch", movement: .seatedMarch)
        case .seatedToeRaise: return individual("BrackenSeatedToeRaise", movement: .seatedToeRaise)
        case .wallSlide: return individual("BrackenWallSlide", movement: .wallSlide)
        case .standingPunch: return individual("BrackenStandingPunch", movement: .standingPunch)
        case .custom: index = 5
        }
        let frames = [CGRect(x: 146, y: 37, width: 282, height: 460),
                      CGRect(x: 604, y: 48, width: 376, height: 443),
                      CGRect(x: 1056, y: 40, width: 439, height: 449),
                      CGRect(x: 173, y: 516, width: 239, height: 466),
                      CGRect(x: 548, y: 526, width: 440, height: 456),
                      CGRect(x: 1176, y: 516, width: 241, height: 466)]
        let frame = frames[index], size = atlas.size()
        let texture = SKTexture(rect: CGRect(x: frame.minX / size.width, y: 1 - frame.maxY / size.height,
                                            width: frame.width / size.width, height: frame.height / size.height), in: atlas)
        let image = texture.cgImage()
        images[activity.movement] = image
        return image
    }
    private static func individual(_ name: String, movement: ActivityMovement) -> CGImage {
        let image = SKTexture(imageNamed: name).cgImage()
        images[movement] = image
        return image
    }
}

struct ActivityIllustration: View {
    let activity: ActivityDefinition

    var body: some View {
        Image(decorative: ActivityArtwork.image(for: activity), scale: 1)
            .resizable().scaledToFit().accessibilityHidden(true)
    }
}
