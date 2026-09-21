import Foundation

/// Transient view-space camera state. Coordinates use an upward-pointing y axis.
public struct ForestCamera: Equatable, Sendable {
    public private(set) var zoom = 1.0
    public private(set) var offset = ForestPoint(x: 0, y: 0)
    public private(set) var velocity = ForestPoint(x: 0, y: 0)
    public var isCoasting: Bool { velocity.x != 0 || velocity.y != 0 }
    public static let zoomRange = 0.85...3.0

    public init() {}

    public mutating func pan(by delta: ForestPoint, viewport: ForestPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        offset = bounded(.init(x: offset.x + delta.x, y: offset.y + delta.y), viewport: viewport)
    }

    /// Incremental scale plus centroid travel keeps the touched world point under the fingers.
    public mutating func magnify(by factor: Double, from start: ForestPoint, to end: ForestPoint, viewport: ForestPoint) {
        guard factor.isFinite, factor > 0, start.x.isFinite, start.y.isFinite,
              end.x.isFinite, end.y.isFinite else { return }
        let next = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom * factor))
        let ratio = next / zoom
        let origin = ForestPoint(x: viewport.x / 2, y: viewport.y * 0.48)
        offset = bounded(.init(x: end.x - origin.x - (start.x - origin.x - offset.x) * ratio,
                               y: end.y - origin.y - (start.y - origin.y - offset.y) * ratio), viewport: viewport)
        zoom = next
    }

    public mutating func coast(with velocity: ForestPoint) {
        guard velocity.x.isFinite, velocity.y.isFinite else { stop(); return }
        let speed = hypot(velocity.x, velocity.y)
        let scale = speed > 900 ? 900 / speed : 1
        self.velocity = .init(x: velocity.x * scale, y: velocity.y * scale)
        if speed < 20 { stop() }
    }

    public mutating func stop() { velocity = .init(x: 0, y: 0) }

    /// Exact exponential integration keeps the short release coast independent of frame rate.
    public mutating func advance(by seconds: Double, viewport: ForestPoint) {
        guard isCoasting, seconds.isFinite, seconds > 0 else { return }
        guard seconds <= 0.25 else { stop(); return }
        let decay = exp(-10 * seconds)
        let before = offset
        let delta = ForestPoint(x: velocity.x * (1 - decay) / 10, y: velocity.y * (1 - decay) / 10)
        pan(by: delta, viewport: viewport)
        velocity = .init(x: abs(offset.x - before.x - delta.x) > 0.00001 ? 0 : velocity.x * decay,
                         y: abs(offset.y - before.y - delta.y) > 0.00001 ? 0 : velocity.y * decay)
        if hypot(velocity.x, velocity.y) < 1 { stop() }
    }

    public mutating func reset() { self = Self() }

    private func bounded(_ point: ForestPoint, viewport: ForestPoint) -> ForestPoint {
        .init(x: min(viewport.x * 0.65, max(-viewport.x * 0.65, point.x)),
              y: min(viewport.y * 0.4, max(-viewport.y * 0.4, point.y)))
    }
}
