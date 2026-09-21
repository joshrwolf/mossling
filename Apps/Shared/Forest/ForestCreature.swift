import SpriteKit
import MosslingCore

@MainActor
final class ForestCreature: SKNode {
    private var facing: CGFloat = 1
    private let bodySprite = SKSpriteNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 82, height: 16))
    private(set) var stage: CompanionStage = .seedling

    init(stage: CompanionStage) {
        super.init()
        shadow.fillColor = SKColor(white: 0, alpha: 0.22)
        shadow.strokeColor = .clear
        shadow.position.y = 5
        addChild(shadow)
        bodySprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(bodySprite)
        configure(stage: stage)
    }

    required init?(coder: NSCoder) { nil }

    func configure(stage: CompanionStage) {
        self.stage = stage
        let height = CGFloat(stage.sceneHeight)
        let texture = SKTexture(imageNamed: stage.artwork)
        bodySprite.texture = texture
        let size = texture.size()
        bodySprite.size = CGSize(width: height * size.width / max(1, size.height), height: height)
        bodySprite.position.y = -height * 0.08
        bodySprite.setScale(1)
        bodySprite.zRotation = 0
        bodySprite.alpha = 1
    }

    func settle() {
        children.filter { $0.name == "evolutionShell" }.forEach { $0.removeFromParent() }
        removeAllActions()
        resetPose()
        alpha = 1
        facing = 1
        bodySprite.colorBlendFactor = 0
        setScale(1)
    }

    func evolve(to stage: CompanionStage) {
        let shell = SKSpriteNode(texture: bodySprite.texture)
        shell.name = "evolutionShell"
        shell.size = bodySprite.size
        shell.anchorPoint = bodySprite.anchorPoint
        shell.position = bodySprite.position
        shell.xScale = bodySprite.xScale
        shell.yScale = bodySprite.yScale
        shell.zPosition = 1
        addChild(shell)
        configure(stage: stage)
        shell.run(.sequence([.group([.fadeOut(withDuration: 0.35), .scale(to: 1.08, duration: 0.35)]), .removeFromParent()]))
        hop()
    }

    private func resetPose() {
        bodySprite.removeAllActions()
        bodySprite.setScale(1)
        bodySprite.xScale = facing
        bodySprite.position.y = -bodySprite.size.height * 0.08
        bodySprite.zRotation = 0
    }

    func face(from: ForestCell, to: ForestCell) {
        let rear = to.x + to.y < from.x + from.y
        bodySprite.color = SKColor(red: 0.24, green: 0.38, blue: 0.17, alpha: 1)
        bodySprite.colorBlendFactor = rear ? 1 : 0
        facing = to.x > from.x || to.y < from.y ? 1 : -1
    }

    func look() {
        resetPose()
        bodySprite.run(.sequence([
            .rotate(toAngle: -0.09, duration: 0.22), .wait(forDuration: 0.35),
            .rotate(toAngle: 0.08, duration: 0.30), .wait(forDuration: 0.25),
            .rotate(toAngle: 0, duration: 0.20)
        ]), withKey: "gesture")
    }

    func hop() {
        resetPose()
        let base = -bodySprite.size.height * 0.08
        bodySprite.run(.sequence([
            .group([.scaleX(to: facing * 1.07, duration: 0.12), .scaleY(to: 0.90, duration: 0.12)]),
            .group([.moveTo(y: base + 19, duration: 0.18), .scaleX(to: facing * 0.96, duration: 0.18), .scaleY(to: 1.04, duration: 0.18)]),
            .moveTo(y: base, duration: 0.19), .group([.scaleX(to: facing, duration: 0.16), .scaleY(to: 1, duration: 0.16)])
        ]), withKey: "gesture")
    }

    func stretch() {
        resetPose()
        bodySprite.run(.sequence([
            .group([.scaleX(to: 1.12, duration: 0.35), .scaleY(to: 0.82, duration: 0.35)]),
            .group([.scaleX(to: 0.92, duration: 0.50), .scaleY(to: 1.16, duration: 0.50)])
        ]), withKey: "gesture")
    }
}
