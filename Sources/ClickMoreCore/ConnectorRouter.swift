import Foundation

public struct ConnectorRoute: Equatable, Sendable {
    public let spotID: UUID
    public let points: [ScreenPoint]
    public let cornerRadius: Double

    public init(spotID: UUID, points: [ScreenPoint], cornerRadius: Double = 5) {
        self.spotID = spotID; self.points = points; self.cornerRadius = cornerRadius
    }
}

/// Routes a fixed-position star without moving targets. Angular groups avoid
/// discontinuities at cardinal boundaries. Within each group, ordered routing
/// stations keep wires apart and anchor each ending at its actual target.
public enum ConnectorRouter {
    public static func routes(trigger: ScreenPoint, spots: [ClickSpot], triggerRadius: Double,
                              spotRadius: Double, spacing: Double = 10) -> [ConnectorRoute] {
        let radius = max(1, triggerRadius), targetRadius = max(0, spotRadius)
        let gap = max(1, spacing, targetRadius + 4)
        let groups = angularGroups(spots.filter { trigger.distance(to: $0.position) > radius + targetRadius + 2 }, from: trigger)
        var result: [ConnectorRoute] = []
        for (groupIndex, group) in groups.enumerated() {
            let angle = (group.first!.angle + group.last!.angle) / 2
            let previous = groupIndex == 0 ? groups.last!.last!.angle - 2 * .pi : groups[groupIndex - 1].last!.angle
            let next = groupIndex + 1 == groups.count ? groups[0].first!.angle + 2 * .pi : groups[groupIndex + 1].first!.angle
            // Each group gets a disjoint angular sector. Compress lane spacing
            // when a dense cluster physically cannot fit near the trigger.
            let lowerAngle = max(-1.35, (previous + group.first!.angle) / 2 - angle)
            let upperAngle = min(1.35, (group.last!.angle + next) / 2 - angle)
            let axis = Axis(origin: trigger, angle: angle)
            var targets: [Target] = []
            for item in group {
                let distance = trigger.distance(to: item.spot.position)
                let scale = 1 - targetRadius / distance
                let centre = axis.coordinates(item.spot.position)
                let end = Coordinate(forward: centre.forward * scale, perpendicular: centre.perpendicular * scale)
                if end.forward <= radius + 3 {
                    result.append(ConnectorRoute(spotID: item.spot.id, points: [
                        ScreenPoint(x: trigger.x + (item.spot.position.x - trigger.x) * radius / distance,
                                    y: trigger.y + (item.spot.position.y - trigger.y) * radius / distance), axis.point(end)
                    ]))
                } else { targets.append(Target(id: item.spot.id, end: end)) }
            }
            targets.sort {
                let first = ($0.slope * 1_000_000_000).rounded()
                let second = ($1.slope * 1_000_000_000).rounded()
                return first == second ? $0.id.uuidString < $1.id.uuidString : first < second
            }
            guard !targets.isEmpty else { continue }
            let firstEnd = targets.map(\.end.forward).min()!
            let escape = radius + min(8, (firstEnd - radius) * 0.15)
            let portExtent = min(radius * 0.65, -radius * sin(max(-0.7, lowerAngle)), radius * sin(min(0.7, upperAngle)))
            let portGap = targets.count > 1 ? min(gap, 2 * portExtent / Double(targets.count - 1)) : 0
            let midpoint = Double(targets.count - 1) / 2
            var cornerRadius = targets.count > 1 ? min(5, portGap / 4) : 5
            var paths = targets.indices.map { index -> [ScreenPoint] in
                let port = (Double(index) - midpoint) * portGap
                return [axis.point(.init(forward: sqrt(max(0, radius * radius - port * port)), perpendicular: port)),
                        axis.point(.init(forward: escape, perpendicular: port))]
            }
            let fanEnd = min(escape + 28, firstEnd - 0.5)
            let padding = min(40, firstEnd * 0.4)
            let lowestSlope = targets.map(\.slope).min()!
            let highestSlope = targets.map(\.slope).max()!
            var stations = targets.map(\.end.forward)
            if fanEnd > escape + 0.5 { stations.append(fanEnd) }
            stations.sort()
            var lastStation = -Double.infinity
            for forward in stations where forward - lastStation > 0.000001 {
                lastStation = forward
                let active = targets.indices.filter { targets[$0].end.forward >= forward - 0.000001 }
                let desired = active.map { target in
                    let previous = axis.coordinates(paths[target].last!)
                    let remaining = targets[target].end.forward - previous.forward
                    let progress = remaining > 0.000001 ? min(1, (forward - previous.forward) / remaining) : 1
                    return previous.perpendicular + (targets[target].end.perpendicular - previous.perpendicular) * progress
                }
                let anchors = Dictionary(uniqueKeysWithValues: active.enumerated().compactMap { index, target -> (Int, Double)? in
                    abs(targets[target].end.forward - forward) <= 0.000001 ? (index, targets[target].end.perpendicular) : nil
                })
                let spread = min(1, max(0, (forward - escape) / max(24, firstEnd - escape)))
                let stationGap = portGap + (gap - portGap) * spread
                // Keep dense routes near the target cone instead of forcing
                // full spacing into a large zigzag around each short ending.
                let lower = max(forward * tan(lowerAngle), forward * lowestSlope - padding)
                let upper = min(forward * tan(upperAngle), forward * highestSlope + padding)
                let lanes = spacedPositions(desired, anchors: anchors, lower: lower, upper: upper, gap: stationGap)
                for (a, b) in zip(lanes, lanes.dropFirst()) {
                    cornerRadius = min(cornerRadius, max(0, (b - a) / 4))
                }
                for (index, target) in active.enumerated() {
                    paths[target].append(axis.point(.init(forward: forward, perpendicular: lanes[index])))
                }
            }
            result += targets.indices.map { ConnectorRoute(spotID: targets[$0].id, points: deduplicated(paths[$0]), cornerRadius: cornerRadius) }
        }
        return result
    }

    /// Fit ordered lanes between fixed endings. Spacing is reduced only where
    /// the available sector or overlapping endpoints make it impossible.
    private static func spacedPositions(_ desired: [Double], anchors: [Int: Double], lower: Double,
                                        upper: Double, gap: Double) -> [Double] {
        let fixed = [(-1, lower)] + anchors.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } + [(desired.count, upper)]
        var result = desired
        for (index, value) in anchors { result[index] = value }
        for (left, right) in zip(fixed, fixed.dropFirst()) {
            let count = right.0 - left.0 - 1
            guard count > 0 else { continue }
            let intervalGap = max(0, min(gap, (right.1 - left.1) / Double(count + 1)))
            let adjusted = (1...count).map { desired[left.0 + $0] - Double($0) * intervalGap }
            let fitted = isotonic(adjusted)
            let ceiling = max(left.1, right.1 - Double(count + 1) * intervalGap)
            for index in 1...count {
                result[left.0 + index] = min(max(fitted[index - 1], left.1), ceiling) + Double(index) * intervalGap
            }
        }
        return result
    }

    private static func isotonic(_ values: [Double]) -> [Double] {
        struct Pool { var total: Double; var count: Int; var mean: Double { total / Double(count) } }
        var pools: [Pool] = []
        for value in values {
            pools.append(Pool(total: value, count: 1))
            while pools.count >= 2 && pools[pools.count - 2].mean > pools[pools.count - 1].mean {
                let last = pools.removeLast()
                pools[pools.count - 1].total += last.total
                pools[pools.count - 1].count += last.count
            }
        }
        return pools.flatMap { Array(repeating: $0.mean, count: $0.count) }
    }

    private static func angularGroups(_ spots: [ClickSpot], from origin: ScreenPoint) -> [[AngularSpot]] {
        var sorted: [AngularSpot] = spots.map { spot in
            let angle = atan2(spot.position.y - origin.y, spot.position.x - origin.x)
            let normalized = angle < 0 ? angle + Double.pi * 2 : angle
            // Subpixel rounding prevents equal rays and circular gap ties from
            // reordering when the entire layout is translated across displays.
            let rounded = (normalized * 1_000_000_000).rounded() / 1_000_000_000
            return AngularSpot(spot: spot, angle: rounded >= Double.pi * 2 - 0.000000001 ? 0 : rounded)
        }
        sorted.sort { first, second in
            first.angle == second.angle ? first.spot.id.uuidString < second.spot.id.uuidString : first.angle < second.angle
        }
        guard !sorted.isEmpty else { return [] }
        var cut = 0, largest = -Double.infinity
        for index in sorted.indices {
            let next = index + 1 == sorted.count ? sorted[0].angle + .pi * 2 : sorted[index + 1].angle
            if next - sorted[index].angle > largest + 0.000000001 {
                largest = next - sorted[index].angle; cut = (index + 1) % sorted.count
            }
        }
        sorted = Array(sorted[cut...]) + sorted[..<cut].map { AngularSpot(spot: $0.spot, angle: $0.angle + .pi * 2) }
        var groups: [[AngularSpot]] = []
        for item in sorted {
            if let last = groups.last, item.angle - last.first!.angle <= .pi / 3 + 0.000001,
               item.angle - last.last!.angle <= .pi / 6 + 0.000001 {
                groups[groups.count - 1].append(item)
            } else { groups.append([item]) }
        }
        return groups
    }

    private static func deduplicated(_ points: [ScreenPoint]) -> [ScreenPoint] {
        points.reduce(into: []) { result, point in
            if let last = result.last, last.distance(to: point) < 0.000001 { return }
            result.append(point)
        }
    }
    private struct AngularSpot { let spot: ClickSpot; let angle: Double }
    private struct Coordinate { let forward: Double; let perpendicular: Double }
    private struct Target {
        let id: UUID
        let end: Coordinate
        var slope: Double { end.perpendicular / end.forward }
    }
    private struct Axis {
        let origin: ScreenPoint
        let angle: Double
        func coordinates(_ point: ScreenPoint) -> Coordinate {
            let dx = point.x - origin.x, dy = point.y - origin.y
            return Coordinate(forward: dx * cos(angle) + dy * sin(angle), perpendicular: -dx * sin(angle) + dy * cos(angle))
        }
        func point(_ coordinate: Coordinate) -> ScreenPoint {
            ScreenPoint(x: origin.x + coordinate.forward * cos(angle) - coordinate.perpendicular * sin(angle),
                        y: origin.y + coordinate.forward * sin(angle) + coordinate.perpendicular * cos(angle))
        }
    }
}
