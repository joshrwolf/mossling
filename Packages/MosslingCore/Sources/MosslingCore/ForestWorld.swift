import Foundation

public struct ForestCell: Codable, Hashable, Sendable, Identifiable {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public var id: String { "\(x),\(y)" }
    public var title: String { "Column \(x + 1), row \(y + 1)" }
    public var neighbors: [Self] { [Self(x, y - 1), Self(x + 1, y), Self(x, y + 1), Self(x - 1, y)] }
}

public enum ForestRegion: String, Codable, CaseIterable, Sendable {
    case clearing, grove
    public var title: String { self == .clearing ? "Home clearing" : "Upper grove" }
    public var requiredGrowth: Int { self == .clearing ? 0 : 30 }
    public var cells: [ForestCell] {
        let columns = self == .clearing ? 0..<6 : 6..<10
        return (0..<6).flatMap { y in columns.map { ForestCell($0, y) } }
    }
}

public enum HabitatKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case stump, fern, mushrooms, pond, wildflowers, steppingStones, lanterns
    public var id: String { rawValue }
    public var unlock: ForestUnlock? { ForestUnlock(rawValue: rawValue) }
    public var title: String { self == .stump ? "Stump home" : unlock!.title }
    public var requiredGrowth: Int { unlock?.requiredGrowth ?? 0 }
    public var width: Int { self == .pond ? 2 : 1 }
    public var depth: Int { self == .pond ? 2 : 1 }
    public var blocksWalking: Bool { self != .steppingStones && self != .wildflowers }
    public var symbol: String { self == .stump ? "house" : unlock!.symbolName }
}

public struct HabitatPlacement: Codable, Equatable, Sendable, Identifiable {
    public let kind: HabitatKind
    public let cell: ForestCell
    public var id: String { kind.rawValue }
    public init(kind: HabitatKind, cell: ForestCell) { self.kind = kind; self.cell = cell }
    public var footprint: Set<ForestCell> {
        Set((0..<kind.depth).flatMap { y in (0..<kind.width).map { ForestCell(cell.x + $0, cell.y + y) } })
    }
}

public enum ForestTerrain: Sendable { case grass, path, water, tree, stairs }

public enum ForestWorldError: Error, LocalizedError, Equatable {
    case locked, outsideHabitat, occupied, blockedPath, invalidWorld
    public var errorDescription: String? {
        switch self {
        case .locked: "Complete more snacks to unlock this."
        case .outsideHabitat: "Choose a spot inside an open clearing."
        case .occupied: "This spot is occupied. Choose another."
        case .blockedPath: "Leave a clear route around the habitat and to every object."
        case .invalidWorld: "This habitat layout is invalid."
        }
    }
}

/// Phone-owned layout. Creature movement is transient; editing never spends earned growth.
public struct ForestWorld: Codable, Equatable, Sendable {
    public private(set) var regions: Set<ForestRegion>
    public private(set) var placements: [HabitatPlacement]
    public static let home = ForestCell(2, 2)
    public init() {
        regions = [.clearing]
        placements = [.init(kind: .stump, cell: ForestCell(1, 1))]
    }
    public var cells: [ForestCell] { ForestRegion.allCases.filter { regions.contains($0) }.flatMap(\.cells) }
    public static func elevation(at cell: ForestCell) -> Int { cell.x >= 6 ? 1 : 0 }
    public static func terrain(at cell: ForestCell) -> ForestTerrain {
        if [ForestCell(0, 0), ForestCell(5, 0), ForestCell(0, 5), ForestCell(9, 0), ForestCell(9, 5)].contains(cell) { return .tree }
        if [ForestCell(1, 4), ForestCell(1, 5), ForestCell(2, 5)].contains(cell) { return .water }
        if cell.x == 6 && cell.y == 2 { return .stairs }
        if cell.y == 2 || (cell.x == 3 && cell.y > 2) { return .path }
        return .grass
    }
    public var walkable: Set<ForestCell> {
        let occupied = Set(placements.filter { $0.kind.blocksWalking }.flatMap(\.footprint))
        return Set(cells.filter { Self.terrain(at: $0) != .tree && Self.terrain(at: $0) != .water && !occupied.contains($0) })
    }
    public func canStep(from: ForestCell, to: ForestCell) -> Bool {
        guard from.neighbors.contains(to), walkable.contains(from), walkable.contains(to) else { return false }
        return Self.elevation(at: from) == Self.elevation(at: to) || Self.terrain(at: from) == .stairs || Self.terrain(at: to) == .stairs
    }
    public func path(from start: ForestCell, to end: ForestCell) -> [ForestCell]? {
        let open = walkable
        guard open.contains(start), open.contains(end) else { return nil }
        var queue = [start], cursor = 0, seen: Set<ForestCell> = [start]
        var parents: [ForestCell: ForestCell] = [:]
        while cursor < queue.count {
            let current = queue[cursor]; cursor += 1
            if current == end {
                var route = [end]
                while let parent = parents[route.last!] { route.append(parent) }
                return route.reversed()
            }
            for next in current.neighbors where open.contains(next) && !seen.contains(next) {
                guard Self.elevation(at: current) == Self.elevation(at: next) || Self.terrain(at: current) == .stairs || Self.terrain(at: next) == .stairs else { continue }
                seen.insert(next); parents[next] = current; queue.append(next)
            }
        }
        return nil
    }
    public func interactionCell(for placement: HabitatPlacement, from start: ForestCell) -> ForestCell? {
        let footprint = placement.footprint
        let candidates = Set(footprint.flatMap(\.neighbors)).subtracting(footprint)
        var reachable: [(cell: ForestCell, distance: Int)] = []
        for cell in candidates {
            if let route = path(from: start, to: cell) { reachable.append((cell, route.count)) }
        }
        return reachable.sorted {
            $0.distance == $1.distance ? $0.cell.id < $1.cell.id : $0.distance < $1.distance
        }.first?.cell
    }
    public func validate() throws {
        guard regions.contains(.clearing), placements.count <= HabitatKind.allCases.count,
              Set(placements.map(\.kind)).count == placements.count else { throw ForestWorldError.invalidWorld }
        let land = Set(cells)
        var occupied = Set<ForestCell>()
        for object in placements {
            guard land.contains(object.cell), object.footprint.isSubset(of: land) else { throw ForestWorldError.outsideHabitat }
            guard !object.footprint.contains(Self.home), object.footprint.allSatisfy({ Self.terrain(at: $0) == .grass }),
                  occupied.isDisjoint(with: object.footprint) else { throw ForestWorldError.occupied }
            occupied.formUnion(object.footprint)
        }
        let open = walkable
        guard open.contains(Self.home), open.allSatisfy({ path(from: Self.home, to: $0) != nil }),
              placements.allSatisfy({ interactionCell(for: $0, from: Self.home) != nil }) else { throw ForestWorldError.blockedPath }
    }
    public func validateEntitlements(growth: Int) throws {
        guard regions.allSatisfy({ $0.requiredGrowth <= growth }),
              placements.allSatisfy({ $0.kind.requiredGrowth <= growth }) else { throw ForestWorldError.locked }
        try validate()
    }
    public mutating func place(_ kind: HabitatKind, at cell: ForestCell, growth: Int) throws {
        guard growth >= kind.requiredGrowth else { throw ForestWorldError.locked }
        var next = self
        next.placements.removeAll { $0.kind == kind }
        next.placements.append(.init(kind: kind, cell: cell))
        next.placements.sort { $0.id < $1.id }
        try next.validate()
        self = next
    }
    public mutating func remove(_ kind: HabitatKind) { placements.removeAll { $0.kind == kind } }
    public mutating func expand(_ region: ForestRegion, growth: Int) throws {
        guard growth >= region.requiredGrowth else { throw ForestWorldError.locked }
        var next = self
        next.regions.insert(region)
        try next.validate()
        self = next
    }
}
