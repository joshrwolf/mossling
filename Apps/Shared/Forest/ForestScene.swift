import SpriteKit
import MosslingCore
import MosslingApplication

@MainActor
final class ForestScene: SKScene {
    private let world = SKNode()
    private let terrain = SKNode()
    private let objects = SKNode()
    private let effects = SKNode()
    private let selection = SKNode()
    private let creature = ForestCreature(stage: .seedling)
    private var snapshot: ForestSnapshot?
    private var residentCell = ForestWorld.home
    private var permitsMotion = false
    private var visitIndex = 0
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero
    private var dragOrigin = CGPoint.zero
    private let mapCells = ForestRegion.allCases.flatMap(\.cells)
    var momentFinished: (() -> Void)?

    init(canvasSize: CGSize) {
        super.init(size: canvasSize)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.07, green: 0.14, blue: 0.11, alpha: 1)
        addChild(world)
        terrain.zPosition = -1000
        effects.zPosition = 1000
        selection.zPosition = 900
        [terrain, objects, effects, selection].forEach { world.addChild($0) }
        world.addChild(creature)
        layoutCamera()
    }
    required init?(coder: NSCoder) { nil }

    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        self.size = size
        layoutCamera()
    }
    private func layoutCamera() {
        #if os(watchOS)
        let scale = min(size.width / 360, size.height / 180)
        let center = point(ForestWorld.home)
        #else
        let points = mapCells.map(point)
        let left = points.map(\.x).min() ?? 0, right = points.map(\.x).max() ?? 0
        let bottom = points.map(\.y).min() ?? 0, top = points.map(\.y).max() ?? 0
        let scale = min(size.width / (right - left + 100), size.height / (top - bottom + 180))
        let center = CGPoint(x: (left + right) / 2, y: (bottom + top) / 2)
        #endif
        world.setScale(scale * zoom)
        world.position = CGPoint(x: size.width / 2 - center.x * world.xScale + pan.x,
                                 y: size.height * 0.48 - center.y * world.yScale + pan.y)
    }
    func magnify(by factor: CGFloat) { zoom = min(2.5, max(0.85, zoom * factor)); layoutCamera() }
    func moveCamera(by translation: CGSize, ended: Bool) {
        pan = CGPoint(x: min(size.width * 0.65, max(-size.width * 0.65, dragOrigin.x + translation.width)),
                      y: min(size.height * 0.4, max(-size.height * 0.4, dragOrigin.y - translation.height)))
        if ended { dragOrigin = pan }
        layoutCamera()
    }
    func centerCamera() { zoom = 1; pan = .zero; dragOrigin = .zero; layoutCamera() }
    func cell(at location: CGPoint) -> ForestCell? {
        let local = world.convert(CGPoint(x: location.x, y: size.height - location.y), from: self)
        return ForestProjection.cell(at: .init(x: local.x, y: local.y), among: snapshot?.world.cells ?? [])
    }
    private func point(_ cell: ForestCell) -> CGPoint {
        let projected = ForestProjection.point(for: cell)
        return CGPoint(x: projected.x, y: projected.y)
    }
    func present(_ transition: ForestTransition, motion: Bool) {
        settle(transition.to, motion: motion)
        guard motion else { return }
        switch transition.moment {
        case .none: break
        case .snack, .discovery:
            creature.hop()
            motes(at: creature.position)
            run(.sequence([.wait(forDuration: 2), .run { [weak self] in self?.momentFinished?() }]), withKey: "moment")
        case .evolution:
            if let before = transition.from { creature.configure(stage: before.stage) }
            creature.stretch()
            motes(at: creature.position)
            run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in
                self?.creature.evolve(to: transition.to.stage)
            }, .wait(forDuration: 1.6), .run { [weak self] in self?.momentFinished?() }]), withKey: "moment")
        }
    }
    func settle(_ snapshot: ForestSnapshot, motion: Bool) {
        removeAllActions()
        creature.settle()
        effects.removeAllChildren()
        self.snapshot = snapshot
        permitsMotion = motion
        residentCell = ForestWorld.home
        creature.configure(stage: snapshot.stage)
        creature.setScale(0.5)
        creature.position = point(residentCell)
        creature.zPosition = ForestProjection.depth(residentCell) + 3
        drawWorld(snapshot)
        if motion {
            run(.repeatForever(.sequence([.wait(forDuration: 4), .run { [weak self] in self?.react() },
                                          .wait(forDuration: 12)])), withKey: "behavior")
        }
    }
    func react() {
        guard permitsMotion, action(forKey: "moment") == nil, creature.action(forKey: "walk") == nil,
              let snapshot else { return }
        let destinations = snapshot.world.placements
        guard !destinations.isEmpty else { creature.hop(); return }
        let object = destinations[visitIndex % destinations.count]
        visitIndex += 1
        guard let destination = snapshot.world.interactionCell(for: object, from: residentCell),
              let route = snapshot.world.path(from: residentCell, to: destination) else { return }
        var actions: [SKAction] = []
        for (from, to) in zip(route, route.dropFirst()) {
            actions.append(.run { [weak self] in self?.creature.face(from: from, to: to); self?.creature.hop() })
            actions.append(.group([.move(to: point(to), duration: 0.45), .sequence([
                .wait(forDuration: 0.225), .run { [weak self] in self?.creature.zPosition = ForestProjection.depth(to) + 3 }
            ])]))
        }
        actions += [.run { [weak self] in
            guard let self else { return }
            self.residentCell = destination
            self.creature.face(from: destination, to: object.cell)
            self.creature.look()
            self.motes(at: self.point(object.cell))
        }]
        creature.run(.sequence(actions), withKey: "walk")
    }
    func showPlacement(_ kind: HabitatKind?, at cell: ForestCell?) {
        selection.removeAllChildren()
        guard let kind, let cell, let snapshot else { return }
        var proposal = snapshot.world
        let valid = (try? proposal.place(kind, at: cell, growth: snapshot.growth)) != nil
        let color: SKColor = valid ? .green : .red
        for tile in HabitatPlacement(kind: kind, cell: cell).footprint {
            let marker = diamond(color: color.withAlphaComponent(0.25))
            marker.strokeColor = color
            marker.lineWidth = 2
            marker.position = point(tile)
            selection.addChild(marker)
        }
        let preview = habitatNode(kind)
        preview.position = point(cell)
        preview.alpha = 0.6
        selection.addChild(preview)
    }
    private func drawWorld(_ snapshot: ForestSnapshot) {
        terrain.removeAllChildren(); objects.removeAllChildren()
        let open = Set(snapshot.world.cells)
        let columns = ((mapCells.map(\.x).min() ?? 0) - 2)...((mapCells.map(\.x).max() ?? 0) + 2)
        let rows = ((mapCells.map(\.y).min() ?? 0) - 2)...((mapCells.map(\.y).max() ?? 0) + 2)
        for y in rows {
            for x in columns {
                let cell = ForestCell(x, y)
                let available = open.contains(cell)
                let surface = ForestWorld.terrain(at: cell)
                let variation = CGFloat(abs(x * 17 + y * 31) % 5) * 0.015
                let color: SKColor
                switch surface {
                case .path, .stairs: color = SKColor(red: 0.57 + variation, green: 0.49 + variation, blue: 0.30, alpha: 1)
                case .water: color = SKColor(red: 0.22, green: 0.46 + variation, blue: 0.49, alpha: 1)
                default: color = SKColor(red: 0.28 + variation, green: 0.43 + variation, blue: 0.20, alpha: 1)
                }
                let tile = diamond(color: color)
                tile.position = point(cell)
                tile.alpha = available ? 1 : 0.23
                tile.zPosition = ForestProjection.depth(cell)
                terrain.addChild(tile)
                if x == 6 {
                    let wall = polygon([CGPoint(x: -40, y: 0), CGPoint(x: 0, y: -20), CGPoint(x: 0, y: -38), CGPoint(x: -40, y: -18)],
                                       color: SKColor(red: 0.25, green: 0.28, blue: 0.20, alpha: 1))
                    wall.position = tile.position
                    wall.zPosition = tile.zPosition - 1
                    wall.alpha = tile.alpha
                    terrain.addChild(wall)
                }
                if surface == .stairs {
                    for index in 0..<4 {
                        let step = SKShapeNode(rectOf: CGSize(width: 42, height: 3), cornerRadius: 1)
                        step.fillColor = SKColor(white: 0.7, alpha: 1); step.strokeColor = .clear
                        step.position = CGPoint(x: tile.position.x, y: tile.position.y - CGFloat(index) * 4)
                        step.zPosition = tile.zPosition + 1; step.alpha = tile.alpha
                        terrain.addChild(step)
                    }
                }
                if surface == .tree || (!available && (x + y).isMultiple(of: 3)) {
                    let tree = treeNode(shade: available ? 1 : 0.55)
                    tree.position = point(cell)
                    tree.zPosition = ForestProjection.depth(cell) + 2
                    tree.alpha = 1
                    objects.addChild(tree)
                }
            }
        }
        for object in snapshot.world.placements {
            let node = habitatNode(object.kind)
            node.position = point(object.cell)
            node.zPosition = ForestProjection.depth(object.cell) + 2
            objects.addChild(node)
        }
        world.alpha = snapshot.affinity == .moonlit ? 0.72 : 1
    }
    private func diamond(color: SKColor) -> SKShapeNode {
        polygon([CGPoint(x: 0, y: 20), CGPoint(x: 40, y: 0), CGPoint(x: 0, y: -20), CGPoint(x: -40, y: 0)], color: color)
    }
    private func polygon(_ points: [CGPoint], color: SKColor) -> SKShapeNode {
        let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = color; node.strokeColor = color; node.lineWidth = 0.5
        return node
    }
    private func treeNode(shade: CGFloat) -> SKNode {
        let node = SKNode()
        let trunk = SKShapeNode(rectOf: CGSize(width: 12, height: 42), cornerRadius: 3)
        trunk.position.y = 20; trunk.fillColor = SKColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1); trunk.strokeColor = .clear
        node.addChild(trunk)
        for index in 0..<3 {
            let width = CGFloat(42 - index * 8)
            let crown = polygon([CGPoint(x: -width, y: 0), CGPoint(x: width, y: 0), CGPoint(x: 0, y: 55)],
                                color: SKColor(red: (0.14 + CGFloat(index) * 0.025) * shade, green: (0.31 + CGFloat(index) * 0.025) * shade, blue: 0.18 * shade, alpha: 1))
            crown.position.y = CGFloat(18 + index * 23)
            node.addChild(crown)
        }
        return node
    }
    private func habitatNode(_ kind: HabitatKind) -> SKNode {
        if kind == .fern {
            let fern = SKSpriteNode(imageNamed: "ForestFern")
            fern.size = CGSize(width: 65, height: 65); fern.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            return fern
        }
        let node = SKNode()
        switch kind {
        case .stump:
            let stump = SKShapeNode(rectOf: CGSize(width: 46, height: 46), cornerRadius: 9)
            stump.position.y = 20; stump.fillColor = SKColor(red: 0.44, green: 0.29, blue: 0.16, alpha: 1)
            stump.strokeColor = SKColor(red: 0.64, green: 0.45, blue: 0.25, alpha: 1); stump.lineWidth = 3
            let top = SKShapeNode(ellipseOf: CGSize(width: 46, height: 20))
            top.position.y = 43; top.fillColor = SKColor(red: 0.68, green: 0.51, blue: 0.30, alpha: 1); top.strokeColor = .brown
            let door = SKShapeNode(rectOf: CGSize(width: 17, height: 25), cornerRadius: 8)
            door.position.y = 11; door.fillColor = SKColor(white: 0.08, alpha: 1); door.strokeColor = .clear
            [stump, top, door].forEach { node.addChild($0) }
        case .pond:
            let pond = SKShapeNode(ellipseOf: CGSize(width: 100, height: 42))
            pond.position.y = -15; pond.fillColor = SKColor(red: 0.25, green: 0.59, blue: 0.63, alpha: 1)
            pond.strokeColor = .lightGray; pond.lineWidth = 4; node.addChild(pond)
        case .lanterns:
            let lamp = SKShapeNode(rectOf: CGSize(width: 15, height: 30), cornerRadius: 4)
            lamp.position.y = 25; lamp.fillColor = .yellow; lamp.strokeColor = .brown; node.addChild(lamp)
        case .mushrooms, .wildflowers, .steppingStones:
            for index in 0..<4 {
                let prop = SKShapeNode(ellipseOf: CGSize(width: kind == .steppingStones ? 17 : 10, height: 7))
                prop.position = CGPoint(x: index * 9 - 14, y: index % 2 * 9)
                prop.fillColor = kind == .mushrooms ? .orange : kind == .wildflowers ? .white : .gray
                prop.strokeColor = .clear; node.addChild(prop)
            }
        case .fern: break
        }
        return node
    }
    private func motes(at point: CGPoint) {
        for index in 0..<5 {
            let mote = SKShapeNode(circleOfRadius: 2)
            mote.fillColor = .yellow; mote.strokeColor = .clear; mote.position = point
            effects.addChild(mote)
            mote.run(.sequence([.group([.moveBy(x: CGFloat(index - 2) * 8, y: 35, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
        }
    }
}
