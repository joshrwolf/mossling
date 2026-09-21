import SwiftUI
import SpriteKit
import MosslingCore

/// Built-in movements have explicit poses; custom activities use a neutral character.
@MainActor
private enum ActivityArtwork {
    private static let atlas = SKTexture(imageNamed: "BrackenActivities")
    private static var images: [Int: CGImage] = [:]

    static func image(for activity: ActivityDefinition) -> CGImage {
        let index: Int
        switch activity.movement {
        case .walk: index = 0
        case .chairStand: index = 1
        case .wallPush: index = 2
        case .calfRaise: index = 3
        case .shoulderMobility: index = 4
        case .custom: index = 5
        }
        if let image = images[index] { return image }
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
        images[index] = image
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
