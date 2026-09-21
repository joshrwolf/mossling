import MosslingCore

public struct ForestPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Logical projection independent of screen size, camera and rendering framework.
public enum ForestProjection {
    public static let tileWidth = 80.0
    public static let tileHeight = 40.0
    public static let rise = 18.0
    public static func point(for cell: ForestCell) -> ForestPoint {
        ForestPoint(x: Double(cell.x - cell.y) * tileWidth / 2,
                    y: -Double(cell.x + cell.y) * tileHeight / 2 + Double(ForestWorld.elevation(at: cell)) * rise)
    }
    public static func cell(at point: ForestPoint, among cells: [ForestCell]) -> ForestCell? {
        cells.sorted { depth($0) > depth($1) }.first {
            let center = self.point(for: $0)
            return abs(point.x - center.x) / (tileWidth / 2) + abs(point.y - center.y) / (tileHeight / 2) <= 1
        }
    }
    public static func depth(_ cell: ForestCell) -> Double { Double(cell.x + cell.y) * 10 }
}
