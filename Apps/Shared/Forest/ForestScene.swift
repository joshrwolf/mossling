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
                .wait(forDuration: 0.225), .run { [weak self] in self?.creature.zPosition = ForestProjection.depth(to) + 3; self?.updateCanopies() }
            ])]))
        }
        actions += [.run { [weak self] in
            guard let self else { return }
            self.residentCell = destination
            self.updateCanopies()
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
        if kind == .pond { preview.position.y -= 20 }
        preview.alpha = 0.6
        selection.addChild(preview)
    }
    private func drawWorld(_ snapshot: ForestSnapshot) {
        terrain.removeAllChildren(); objects.removeAllChildren()
        let open = Set(snapshot.world.cells)
        let columns = ((mapCells.map(\.x).min() ?? 0) - 2)...((mapCells.map(\.x).max() ?? 0) + 2)
        let rows = ((mapCells.map(\.y).min() ?? 0) - 2)...((mapCells.map(\.y).max() ?? 0) + 2)
        let surroundings = rows.flatMap { y in columns.map { ForestCell($0, y) } }
        paintGround(surroundings, material: .grass, shade: 0.48)
        paintGround(snapshot.world.cells, material: .grass)
        paintGround(snapshot.world.cells.filter { ForestWorld.terrain(at: $0) == .path || ForestWorld.terrain(at: $0) == .stairs }, material: .soil)
        paintGround(snapshot.world.cells.filter { ForestWorld.terrain(at: $0) == .water }, material: .water)

        let cliff = CGMutablePath()
        for cell in surroundings {
            let available = open.contains(cell)
            let surface = ForestWorld.terrain(at: cell)
            let location = point(cell)
            if cell.x == 6 {
                cliff.addLines(between: [CGPoint(x: location.x, y: location.y + 20),
                                         CGPoint(x: location.x - 40, y: location.y),
                                         CGPoint(x: location.x - 40, y: location.y - 18),
                                         CGPoint(x: location.x, y: location.y + 2)])
                cliff.closeSubpath()
            }
            if available && surface == .stairs {
                let stairs = ForestArt.sprite(.stairs)
                stairs.position = location
                stairs.zPosition = 6
                terrain.addChild(stairs)
            }
            if surface == .tree || (!available && (cell.x + cell.y).isMultiple(of: 3)) {
                // Keep the front edge open; tall canopy belongs behind the playable clearing.
                let foreground = cell.x + cell.y > 10
                let prop: ForestArt.Prop = foreground ? .rock : (cell.x.isMultiple(of: 2) ? .oak : .birch)
                let tree = ForestArt.sprite(prop)
                tree.name = foreground ? nil : "canopy"
                tree.position = location
                tree.zPosition = ForestProjection.depth(cell) + 2
                tree.color = SKColor(red: 0.10, green: 0.20, blue: 0.15, alpha: 1)
                tree.colorBlendFactor = available ? 0 : 0.38
                objects.addChild(tree)
            } else if !available && (cell.x * 7 + cell.y * 3).isMultiple(of: 5) {
                let brush = ForestArt.sprite(cell.x.isMultiple(of: 2) ? .fern : .branch)
                brush.position = location
                brush.zPosition = ForestProjection.depth(cell) + 1
                brush.color = SKColor(red: 0.10, green: 0.20, blue: 0.15, alpha: 1)
                brush.colorBlendFactor = 0.4
                objects.addChild(brush)
            }
            if available && surface == .water {
                for (index, neighbor) in cell.neighbors.enumerated() where ForestWorld.terrain(at: neighbor) != .water {
                    let rock = ForestArt.sprite(.rock)
                    rock.setScale(0.35)
                    let edge = point(neighbor)
                    rock.position = CGPoint(x: (location.x + edge.x) / 2, y: (location.y + edge.y) / 2)
                    rock.zPosition = ForestProjection.depth(cell) + CGFloat(index) * 0.01
                    objects.addChild(rock)
                }
            }
        }
        paintSurface(cliff, material: .stone, shade: 0.8)
        for object in snapshot.world.placements {
            let node = habitatNode(object.kind)
            node.position = point(object.cell)
            if object.kind == .pond { node.position.y -= 20 }
            node.zPosition = ForestProjection.depth(object.cell) + 2
            objects.addChild(node)
        }
        updateCanopies()
        world.alpha = snapshot.affinity == .moonlit ? 0.82 : 1
    }

    /// A shared material spans the mask, so adjacent cells never become a checkerboard.
    private func paintGround(_ cells: [ForestCell], material: ForestArt.Ground, shade: CGFloat = 1) {
        guard !cells.isEmpty else { return }
        let path = CGMutablePath()
        let land = Set(cells)
        for cell in cells {
            let p = point(cell)
            let corners = [CGPoint(x: p.x, y: p.y + 20), CGPoint(x: p.x + 40, y: p.y),
                           CGPoint(x: p.x, y: p.y - 20), CGPoint(x: p.x - 40, y: p.y)]
            var outline: [CGPoint] = []
            for edge in 0..<4 {
                let a = corners[edge], b = corners[(edge + 1) % 4]
                outline.append(a)
                if material == .soil || material == .water, !land.contains(cell.neighbors[edge]) {
                    for step in 1..<5 {
                        let fraction = CGFloat(step) / 5
                        let roughness = CGFloat(abs(cell.x * 17 + cell.y * 31 + edge * 11 + step * 7) % 5 - 2)
                        outline.append(CGPoint(x: a.x + (b.x - a.x) * fraction + roughness,
                                               y: a.y + (b.y - a.y) * fraction + roughness * 0.5))
                    }
                }
            }
            path.addLines(between: outline)
            path.closeSubpath()
        }
        paintSurface(path, material: material, shade: shade)
    }

    private func paintSurface(_ path: CGPath, material: ForestArt.Ground, shade: CGFloat) {
        let mask = SKShapeNode(path: path)
        mask.fillColor = .white; mask.strokeColor = .white; mask.lineWidth = 0.6
        let layer = SKCropNode()
        layer.maskNode = mask
        layer.zPosition = material == .stone ? 5 : (material == .grass ? (shade < 1 ? 0 : 1) : (material == .soil ? 2 : 3))
        let bounds = path.boundingBoxOfPath
        let tileSize: CGFloat = 240
        for y in Int(floor(bounds.minY / tileSize))...Int(ceil(bounds.maxY / tileSize)) {
            for x in Int(floor(bounds.minX / tileSize))...Int(ceil(bounds.maxX / tileSize)) {
                let tile = SKSpriteNode(texture: ForestArt.material(material))
                tile.size = CGSize(width: tileSize + 0.5, height: tileSize + 0.5)
                tile.anchorPoint = .zero
                tile.position = CGPoint(x: CGFloat(x) * tileSize, y: CGFloat(y) * tileSize)
                tile.color = SKColor(red: 0.08, green: 0.16, blue: 0.12, alpha: 1)
                tile.colorBlendFactor = 1 - shade
                layer.addChild(tile)
            }
        }
        terrain.addChild(layer)
    }

    private func updateCanopies() {
        for case let tree as SKSpriteNode in objects.children where tree.name == "canopy" {
            let bounds = tree.frame.insetBy(dx: tree.size.width * 0.12, dy: 0)
            tree.alpha = tree.zPosition > creature.zPosition && bounds.contains(creature.position) ? 0.35 : 1
        }
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
    private func habitatNode(_ kind: HabitatKind) -> SKSpriteNode {
        let prop: ForestArt.Prop
        switch kind {
        case .stump: prop = .stump
        case .fern: prop = .fern
        case .mushrooms: prop = .mushrooms
        case .pond: prop = .pond
        case .wildflowers: prop = .flowers
        case .steppingStones: prop = .stones
        case .lanterns: prop = .lantern
        }
        return ForestArt.sprite(prop)
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
