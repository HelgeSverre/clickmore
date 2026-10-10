import Foundation

public struct ConnectorRoute: Equatable, Sendable {
    public let spotID: UUID
    public let points: [ScreenPoint]
}

/// Fixed-position routing inspired by ELK's port and edge spacing. Only the
/// decorative wires move: target coordinates and click order remain untouched.
public enum ConnectorRouter {
    public static func routes(trigger: ScreenPoint, spots: [ClickSpot], triggerRadius: Double,
                              spotRadius: Double, spacing: Double = 10) -> [ConnectorRoute] {
        let gap = max(1, spacing)
        let radius = max(1, triggerRadius)
        var result: [ConnectorRoute] = []
        for side in Side.allCases {
            let visible = spots.filter {
                side == Side.toward($0.position, from: trigger) && trigger.distance(to: $0.position) > radius + spotRadius + 2
            }
                .sorted {
                    let a = side.coordinates($0.position, from: trigger)
                    let b = side.coordinates($1.position, from: trigger)
                    return a.perpendicular == b.perpendicular ? $0.id.uuidString < $1.id.uuidString : a.perpendicular < b.perpendicular
                }
            let targets = visible.filter { side.coordinates($0.position, from: trigger).forward >= radius + spotRadius + 16 }
            for target in visible where side.coordinates(target.position, from: trigger).forward < radius + spotRadius + 16 {
                // A very short connection has no room for a routing lane.
                let distance = trigger.distance(to: target.position)
                let dx = (target.position.x - trigger.x) / distance
                let dy = (target.position.y - trigger.y) / distance
                result.append(ConnectorRoute(spotID: target.id, points: [
                    ScreenPoint(x: trigger.x + dx * radius, y: trigger.y + dy * radius),
                    ScreenPoint(x: target.position.x - dx * spotRadius, y: target.position.y - dy * spotRadius)
                ]))
            }
            guard !targets.isEmpty else { continue }
            let coordinates = targets.map { side.coordinates($0.position, from: trigger) }
            let lanes = spacedLanes(coordinates.map(\.perpendicular), gap: gap)
            let mid = Double(targets.count - 1) / 2
            let portGap = targets.count > 1 ? min(gap, radius * 1.3 / Double(targets.count - 1)) : 0
            // A shared fan-out corridor preserves the sorted order of the wires.
            // Diagonal transitions avoid overlapping vertical trunks while the
            // long parallel segments keep their requested lane spacing.
            let available = max(0, (coordinates.map(\.forward).min() ?? radius) - radius - spotRadius)
            let escape = radius + min(8, available * 0.15)
            let fanLength = max(24, lanes.enumerated().map { abs($0.element - (Double($0.offset) - mid) * portGap) }.max() ?? 0)
            let fanEnd = escape + min(fanLength, available * 0.6)
            for (index, target) in targets.enumerated() {
                let coordinate = coordinates[index]
                let port = (Double(index) - mid) * portGap
                let portForward = sqrt(max(0, radius * radius - port * port))
                let endForward = coordinate.forward - spotRadius
                let approach = max(fanEnd, endForward - 14)
                let points = [(portForward, port), (escape, port), (fanEnd, lanes[index]),
                              (approach, lanes[index]), (endForward, coordinate.perpendicular)]
                    .map { side.point(forward: $0.0, perpendicular: $0.1, from: trigger) }
                result.append(ConnectorRoute(spotID: target.id, points: deduplicated(points)))
            }
        }
        return result
    }

    /// Least-squares spacing: isotonic regression of y[i] - i*gap shifts a
    /// crowded cluster symmetrically instead of pushing every wire to one side.
    private static func spacedLanes(_ coordinates: [Double], gap: Double) -> [Double] {
        struct Pool { var total: Double; var count: Int; var mean: Double { total / Double(count) } }
        var pools: [Pool] = []
        for (index, coordinate) in coordinates.enumerated() {
            pools.append(Pool(total: coordinate - Double(index) * gap, count: 1))
            while pools.count >= 2 && pools[pools.count - 2].mean > pools[pools.count - 1].mean {
                let last = pools.removeLast()
                pools[pools.count - 1].total += last.total
                pools[pools.count - 1].count += last.count
            }
        }
        let fitted = pools.flatMap { Array(repeating: $0.mean, count: $0.count) }
        return fitted.enumerated().map { $0.element + Double($0.offset) * gap }
    }

    private static func deduplicated(_ points: [ScreenPoint]) -> [ScreenPoint] {
        points.reduce(into: []) { result, point in
            if result.last != point { result.append(point) }
        }
    }

    private enum Side: CaseIterable {
        case right, up, left, down
        static func toward(_ point: ScreenPoint, from origin: ScreenPoint) -> Side {
            let dx = point.x - origin.x, dy = point.y - origin.y
            return abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .up : .down)
        }
        func coordinates(_ point: ScreenPoint, from origin: ScreenPoint) -> (forward: Double, perpendicular: Double) {
            let dx = point.x - origin.x, dy = point.y - origin.y
            switch self {
            case .right: return (dx, dy)
            case .left: return (-dx, dy)
            case .up: return (dy, dx)
            case .down: return (-dy, dx)
            }
        }
        func point(forward: Double, perpendicular: Double, from origin: ScreenPoint) -> ScreenPoint {
            switch self {
            case .right: ScreenPoint(x: origin.x + forward, y: origin.y + perpendicular)
            case .left: ScreenPoint(x: origin.x - forward, y: origin.y + perpendicular)
            case .up: ScreenPoint(x: origin.x + perpendicular, y: origin.y + forward)
            case .down: ScreenPoint(x: origin.x + perpendicular, y: origin.y - forward)
            }
        }
    }
}
