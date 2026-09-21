import SpriteKit
import MosslingCore

/// Atlas frames use source-image pixels measured from the top-left corner.
/// Anchors refer to the ground contact point, independent of transparent margins.
@MainActor
enum ForestArt {
    enum Prop: CaseIterable {
        case oak, birch, stump, rock, fern, mushrooms, pond, flowers, stones, lantern, stairs, branch

        var frame: CGRect {
            switch self {
            case .oak: CGRect(x: 10, y: 10, width: 350, height: 419)
            case .birch: CGRect(x: 396, y: 10, width: 312, height: 420)
            case .stump: CGRect(x: 730, y: 85, width: 380, height: 345)
            case .rock: CGRect(x: 1117, y: 148, width: 318, height: 277)
            case .fern: CGRect(x: 14, y: 445, width: 351, height: 290)
            case .mushrooms: CGRect(x: 427, y: 496, width: 254, height: 215)
            case .pond: CGRect(x: 719, y: 455, width: 401, height: 277)
            case .flowers: CGRect(x: 1155, y: 486, width: 270, height: 227)
            case .stones: CGRect(x: 43, y: 755, width: 316, height: 297)
            case .lantern: CGRect(x: 410, y: 737, width: 240, height: 319)
            case .stairs: CGRect(x: 744, y: 744, width: 326, height: 316)
            case .branch: CGRect(x: 1105, y: 805, width: 325, height: 235)
            }
        }
        var width: CGFloat {
            switch self {
            case .oak: 132
            case .birch: 112
            case .stump: 90
            case .rock: 38
            case .fern: 48
            case .mushrooms: 34
            case .pond: 118
            case .flowers: 34
            case .stones: 44
            case .lantern: 35
            case .stairs: 56
            case .branch: 43
            }
        }
        var anchor: CGPoint {
            switch self {
            case .pond, .stones: CGPoint(x: 0.5, y: 0.5)
            case .stairs: CGPoint(x: 0.5, y: 0.42)
            default: CGPoint(x: 0.5, y: 0.12)
            }
        }
    }
    enum Ground: Int { case grass, soil, water, stone }

    private static let props = SKTexture(imageNamed: "WoodlandProps")
    private static let ground = SKTexture(imageNamed: "WoodlandGround")
    private static let companion = SKTexture(imageNamed: "BrackenSprites")
    private static var propTextures: [Prop: SKTexture] = [:]
    private static var groundTextures: [Int: SKTexture] = [:]
    private static var companionTextures: [CompanionStage: SKTexture] = [:]

    private static func texture(in atlas: SKTexture, frame: CGRect) -> SKTexture {
        let size = atlas.size()
        let rect = CGRect(x: frame.minX / size.width, y: 1 - frame.maxY / size.height,
                          width: frame.width / size.width, height: frame.height / size.height)
        let texture = SKTexture(rect: rect, in: atlas)
        texture.filteringMode = .linear
        return texture
    }

    static func sprite(_ prop: Prop) -> SKSpriteNode {
        let texture = propTextures[prop] ?? texture(in: props, frame: prop.frame)
        propTextures[prop] = texture
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: prop.width, height: prop.width * prop.frame.height / prop.frame.width)
        node.anchorPoint = prop.anchor
        return node
    }

    static func material(_ material: Ground) -> SKTexture {
        if let cached = groundTextures[material.rawValue] { return cached }
        let index = material.rawValue
        let frame = CGRect(x: (index % 2) * 627 + 2, y: (index / 2) * 627 + 2, width: 623, height: 623)
        let texture = texture(in: ground, frame: frame)
        groundTextures[index] = texture
        return texture
    }

    static func character(_ stage: CompanionStage) -> SKTexture {
        if let cached = companionTextures[stage] { return cached }
        let frame: CGRect
        switch stage {
        case .seedling: frame = CGRect(x: 237, y: 105, width: 212, height: 463)
        case .sprout: frame = CGRect(x: 823, y: 58, width: 240, height: 512)
        case .guardian: frame = CGRect(x: 212, y: 690, width: 277, height: 524)
        case .groveKeeper: frame = CGRect(x: 814, y: 671, width: 290, height: 548)
        }
        let texture = texture(in: companion, frame: frame)
        companionTextures[stage] = texture
        return texture
    }
}

extension CompanionStage {
    var sceneHeight: Double {
        switch self {
        case .seedling: 120
        case .sprout: 140
        case .guardian: 158
        case .groveKeeper: 172
        }
    }
}
