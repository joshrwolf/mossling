import SpriteKit
import MosslingCore
import MosslingApplication

@MainActor
final class ForestScene: SKScene {
    private let backdrop = SKSpriteNode(imageNamed: "ForestClearing")
    private let moonlight = SKSpriteNode(color: SKColor(red: 0.15, green: 0.20, blue: 0.43, alpha: 1), size: .zero)
    private let habitat = SKNode()
    private let effects = SKNode()
    private let creature = ForestCreature(stage: .seedling)
    private var snapshot: ForestSnapshot?
    private var permitsMotion = false
    private var reactionIndex = 0
    var momentFinished: (() -> Void)?

    init(canvasSize: CGSize) {
        super.init(size: canvasSize)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.09, green: 0.18, blue: 0.13, alpha: 1)
        backdrop.zPosition = -10
        moonlight.zPosition = -9
        habitat.zPosition = 0
        creature.zPosition = 5
        effects.zPosition = 8
        addChild(backdrop)
        addChild(moonlight)
        addChild(habitat)
        addChild(creature)
        addChild(effects)
        layoutWorld()
    }

    required init?(coder: NSCoder) { nil }

    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        self.size = size
        layoutWorld()
        if let snapshot { placeHabitat(snapshot) }
    }

    private var home: CGPoint { CGPoint(x: size.width * 0.43, y: size.height * 0.22) }
    private var fernPosition: CGPoint { CGPoint(x: size.width * 0.72, y: size.height * 0.21) }
    private var worldScale: CGFloat {
        #if os(watchOS)
        min(size.width / 260, size.height / 240)
        #else
        min(size.width / 390, size.height / 430)
        #endif
    }

    private func layoutWorld() {
        let imageSize = backdrop.texture?.size() ?? CGSize(width: 600, height: 900)
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        backdrop.size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
        moonlight.size = size
        moonlight.position = backdrop.position
        creature.position = home
        creature.setScale(worldScale)
    }

    func present(_ transition: ForestTransition, motion: Bool) {
        settle(transition.to, motion: motion)
        guard motion else { return }
        switch transition.moment {
        case .none: break
        case .snack:
            creature.hop()
            motes(at: home)
        case .discovery:
            reveal(transition.discoveries)
            investigate()
            run(.sequence([.wait(forDuration: 2.6), .run { [weak self] in self?.momentFinished?() }]), withKey: "moment")
        case .evolution:
            if let before = transition.from { creature.configure(stage: before.stage) }
            creature.stretch()
            motes(at: CGPoint(x: home.x, y: home.y + 70 * worldScale))
            run(.sequence([
                .wait(forDuration: 0.9),
                .run { [weak self] in
                    guard let self else { return }
                    self.creature.evolve(to: transition.to.stage)
                    self.reveal(transition.discoveries)
                },
                .wait(forDuration: 1.6),
                .run { [weak self] in self?.momentFinished?() }
            ]), withKey: "moment")
        }
    }

    func settle(_ snapshot: ForestSnapshot, motion: Bool) {
        removeAllActions()
        effects.removeAllChildren()
        creature.settle()
        self.snapshot = snapshot
        permitsMotion = motion
        creature.configure(stage: snapshot.stage)
        layoutWorld()
        moonlight.alpha = snapshot.affinity == .moonlit ? 0.43 : 0
        placeHabitat(snapshot)
        if motion { scheduleBehaviors() }
    }

    func react() {
        guard permitsMotion, action(forKey: "moment") == nil else { return }
        creature.removeAction(forKey: "walk")
        reactionIndex = (reactionIndex + 1) % 3
        switch reactionIndex {
        case 0: creature.look()
        case 1: creature.hop()
        default: investigate()
        }
    }

    private func scheduleBehaviors() {
        run(.repeatForever(.sequence([
            .wait(forDuration: 5), .run { [weak self] in self?.creature.look() },
            .wait(forDuration: 7), .run { [weak self] in self?.investigate() },
            .wait(forDuration: 8), .run { [weak self] in self?.creature.hop() },
            .wait(forDuration: 6)
        ])), withKey: "behavior")
    }

    private func investigate() {
        let destination = CGPoint(x: size.width * (snapshot?.unlocks.contains(.fern) == true ? 0.58 : 0.49), y: home.y)
        creature.run(.sequence([
            .move(to: destination, duration: 0.65),
            .run { [weak self] in self?.creature.look() },
            .wait(forDuration: 1.3), .move(to: home, duration: 0.7)
        ]), withKey: "walk")
    }

    private func placeHabitat(_ snapshot: ForestSnapshot) {
        habitat.removeAllChildren()
        for unlock in snapshot.unlocks {
            let node: SKNode
            switch unlock {
            case .fern:
                let fern = SKSpriteNode(imageNamed: "ForestFern")
                fern.size = CGSize(width: 112, height: 112)
                fern.anchorPoint = CGPoint(x: 0.5, y: 0.08)
                fern.position = fernPosition
                node = fern
            case .mushrooms:
                node = mushroomCluster()
                node.position = CGPoint(x: size.width * 0.18, y: size.height * 0.24)
            case .pond:
                let pond = SKShapeNode(ellipseOf: CGSize(width: 115, height: 36))
                pond.fillColor = SKColor(red: 0.30, green: 0.57, blue: 0.58, alpha: 1)
                pond.strokeColor = SKColor(red: 0.71, green: 0.83, blue: 0.66, alpha: 1)
                pond.lineWidth = 3
                pond.position = CGPoint(x: size.width * 0.66, y: size.height * 0.12)
                node = pond
            case .wildflowers:
                let flowers = SKNode()
                for index in 0..<5 {
                    let flower = SKShapeNode(circleOfRadius: 4)
                    flower.fillColor = index.isMultiple(of: 2) ? .white : SKColor(red: 0.93, green: 0.68, blue: 0.38, alpha: 1)
                    flower.strokeColor = .clear
                    flower.position = CGPoint(x: index * 9, y: index % 2 * 8)
                    flowers.addChild(flower)
                }
                flowers.position = CGPoint(x: size.width * 0.78, y: size.height * 0.32)
                node = flowers
            case .steppingStones:
                let stones = SKNode()
                for index in 0..<4 {
                    let stone = SKShapeNode(ellipseOf: CGSize(width: 22, height: 10))
                    stone.fillColor = SKColor(red: 0.52, green: 0.55, blue: 0.40, alpha: 1)
                    stone.strokeColor = .clear
                    stone.position = CGPoint(x: index * 15, y: index * 12)
                    stones.addChild(stone)
                }
                stones.position = CGPoint(x: size.width * 0.14, y: size.height * 0.08)
                node = stones
            case .lanterns:
                let lantern = SKShapeNode(rectOf: CGSize(width: 15, height: 24), cornerRadius: 4)
                lantern.fillColor = SKColor(red: 0.99, green: 0.78, blue: 0.33, alpha: 1)
                lantern.strokeColor = SKColor(red: 0.40, green: 0.29, blue: 0.14, alpha: 1)
                lantern.lineWidth = 3
                lantern.glowWidth = 4
                lantern.position = CGPoint(x: size.width * 0.85, y: size.height * 0.52)
                node = lantern
            }
            node.name = unlock.rawValue
            node.setScale(worldScale)
            habitat.addChild(node)
        }
    }

    private func mushroomCluster() -> SKNode {
        let cluster = SKNode()
        for index in 0..<3 {
            let stem = SKShapeNode(rectOf: CGSize(width: 5, height: 15), cornerRadius: 2)
            stem.fillColor = SKColor(red: 0.91, green: 0.83, blue: 0.63, alpha: 1)
            stem.strokeColor = .clear
            stem.position = CGPoint(x: index * 13, y: index % 2 * 6)
            let cap = SKShapeNode(ellipseOf: CGSize(width: 21, height: 13))
            cap.fillColor = SKColor(red: 0.72, green: 0.35, blue: 0.20, alpha: 1)
            cap.strokeColor = .clear
            cap.position.y = 8
            stem.addChild(cap)
            cluster.addChild(stem)
        }
        return cluster
    }

    private func reveal(_ discoveries: [ForestUnlock]) {
        for discovery in discoveries {
            guard let node = habitat.childNode(withName: discovery.rawValue) else { continue }
            node.yScale = worldScale * 0.05
            node.alpha = 0
            node.run(.group([.scaleY(to: worldScale, duration: 0.8), .fadeIn(withDuration: 0.4)]))
            motes(at: node.position)
        }
    }

    private func motes(at point: CGPoint) {
        for index in 0..<7 {
            let mote = SKShapeNode(circleOfRadius: CGFloat(2 + index % 2) * worldScale)
            mote.fillColor = SKColor(red: 0.96, green: 0.78, blue: 0.36, alpha: 1)
            mote.strokeColor = .clear
            mote.position = point
            effects.addChild(mote)
            mote.run(.sequence([
                .group([.moveBy(x: CGFloat(index - 3) * 11 * worldScale, y: CGFloat(30 + index % 3 * 17) * worldScale, duration: 0.85), .fadeOut(withDuration: 0.85)]),
                .removeFromParent()
            ]))
        }
    }
}
