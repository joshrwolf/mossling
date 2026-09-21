import Foundation

/// Persist realized terrain, so future generator tuning cannot move an existing forest.
public struct ForestLandscape: Codable, Equatable, Sendable {
    public let seed: UInt64
    public let trees: Set<ForestCell>
    public let water: Set<ForestCell>
    public let paths: Set<ForestCell>
    public static let stairs = ForestCell(6, 2)

    public static let standard = Self(seed: 0,
        trees: [ForestCell(0, 0), ForestCell(5, 0), ForestCell(0, 5), ForestCell(9, 0), ForestCell(9, 5)],
        water: [ForestCell(1, 4), ForestCell(1, 5), ForestCell(2, 5)],
        paths: Set((0..<10).map { ForestCell($0, 2) } + (3..<6).map { ForestCell(3, $0) }))

    public func terrain(at cell: ForestCell) -> ForestTerrain {
        if cell == Self.stairs { return .stairs }
        if trees.contains(cell) { return .tree }
        if water.contains(cell) { return .water }
        if paths.contains(cell) { return .path }
        return .grass
    }

    public func validate() throws {
        let land = Set(ForestRegion.allCases.flatMap(\.cells))
        let corridor = Set((0..<10).map { ForestCell($0, 2) })
        guard trees.isSubset(of: land), water.isSubset(of: land), paths.isSubset(of: land),
              trees.isDisjoint(with: water), trees.isDisjoint(with: paths), water.isDisjoint(with: paths),
              corridor.isSubset(of: paths) else { throw ForestWorldError.invalidWorld }
    }

    /// Coordinate noise is stable across platforms and independent of traversal order.
    public func variation(at cell: ForestCell) -> UInt64 {
        var random = ForestRandom(state: seed &+ UInt64(bitPattern: Int64(cell.x)) &* 73_856_093
                                  &+ UInt64(bitPattern: Int64(cell.y)) &* 19_349_663)
        return random.next()
    }
}

struct ForestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
    mutating func choose<T>(_ values: [T]) -> T { values[Int(next() % UInt64(values.count))] }
}

extension ForestWorld {
    /// Composition first: a connected spine, edge pond, back canopy and an open building patch.
    public static func generated(seed: UInt64) throws -> Self {
        var random = ForestRandom(state: seed)
        let ponds: [[ForestCell]] = [
            [ForestCell(0, 4), ForestCell(0, 5), ForestCell(1, 5)],
            [ForestCell(1, 4), ForestCell(1, 5), ForestCell(2, 5)],
            [ForestCell(4, 4), ForestCell(4, 5), ForestCell(5, 5)]
        ]
        let water = Set(random.choose(ponds))
        let spur = water.contains(ForestCell(4, 5)) ? 2 : 3
        let paths = Set((0..<10).map { ForestCell($0, 2) } + (3..<6).map { ForestCell(spur, $0) })
        let stump = random.choose([ForestCell(1, 1), ForestCell(1, 3), ForestCell(4, 3)])
        let canopy = random.choose([[ForestCell(0, 0), ForestCell(1, 0)],
                                    [ForestCell(1, 0), ForestCell(2, 0)],
                                    [ForestCell(0, 0), ForestCell(5, 0)]])
        let trees = Set(canopy + [random.choose([ForestCell(8, 0), ForestCell(9, 0)]), ForestCell(9, 5)])
        let landscape = ForestLandscape(seed: seed, trees: trees, water: water, paths: paths)
        let world = Self(landscape: landscape, stump: stump)
        // Every branch of the small grammar is constrained; normal validation remains authoritative.
        try world.validate()
        return world
    }
}

extension ForestLandscape {
    private enum CodingKeys: String, CodingKey { case seed, trees, water, paths }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func cells(_ key: CodingKeys) throws -> Set<ForestCell> {
            let decoded = try values.decode([ForestCell].self, forKey: key)
            guard decoded.count <= 60, Set(decoded).count == decoded.count else { throw ForestWorldError.invalidWorld }
            return Set(decoded)
        }
        seed = try values.decode(UInt64.self, forKey: .seed)
        trees = try cells(.trees); water = try cells(.water); paths = try cells(.paths)
        try validate()
    }
}
