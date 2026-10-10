import Foundation
#if !ROUTING_MEDIA_EXPORT
import ClickMoreCore
#endif

struct RoutingFixture {
    let name: String
    let spots: [ClickSpot]

    init(_ name: String, _ points: [ScreenPoint]) {
        self.name = name
        spots = points.enumerated().map { index, point in
            ClickSpot(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, position: point)
        }
    }

    static let cases: [RoutingFixture] = [
        RoutingFixture("Screenshot regression", [.init(x: 143, y: 440), .init(x: 156, y: 151)]),
        RoutingFixture("Dense vertical row", (0..<16).map { .init(x: 320, y: Double($0 - 8) * 3) }),
        RoutingFixture("Mixed depths", (0..<16).map { .init(x: 75 + Double($0) * 26, y: Double($0 % 4) * 2) }),
        RoutingFixture("Across the 45° boundary", (0..<24).map {
            let angle = (.pi / 4) + Double($0 - 12) * 0.006
            let distance = 180 + Double($0 % 6) * 38
            return .init(x: cos(angle) * distance, y: sin(angle) * distance)
        }),
        RoutingFixture("Four dense clusters", (0..<64).map {
            let angle = Double($0 / 16) * .pi / 2 + Double($0 % 16 - 8) * 0.012
            let distance = 230 + Double($0 % 4) * 32
            return .init(x: cos(angle) * distance, y: sin(angle) * distance)
        }),
        RoutingFixture("64 around the trigger", (0..<64).map {
            let angle = Double($0) * .pi * 2 / 64
            return .init(x: cos(angle) * 260, y: sin(angle) * 260)
        }),
        RoutingFixture("Short and long connections", (0..<20).map {
            let angle = 0.4 + Double($0 % 10) * 0.018
            let distance = $0 < 10 ? 52.0 : 460.0
            return .init(x: cos(angle) * distance, y: sin(angle) * distance)
        }),
        RoutingFixture("Coincident targets", (0..<12).map { _ in .init(x: 250, y: 100) })
    ]

    static func random(seed: UInt64, count: Int = 64) -> RoutingFixture {
        var state = seed
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        let centres = (0..<4).map { _ in random() * .pi * 2 }
        let points = (0..<count).map { index in
            let angle = centres[index % 4] + (random() - 0.5) * 0.55
            let distance = 100 + random() * 480
            return ScreenPoint(x: cos(angle) * distance, y: sin(angle) * distance)
        }
        return RoutingFixture("Seed \(seed)", points)
    }
}

enum RoutingMetrics {
    // Sample the same quadratic corner geometry used by the AppKit renderer.
    static func rounded(_ route: ConnectorRoute) -> ConnectorRoute {
        var points = [route.points[0]]
        for index in 1..<route.points.count {
            let corner = route.points[index]
            guard index + 1 < route.points.count else { points.append(corner); continue }
            let before = route.points[index - 1], after = route.points[index + 1]
            let incoming = corner.distance(to: before), outgoing = corner.distance(to: after)
            guard min(incoming, outgoing) > 0.001 else { points.append(corner); continue }
            let trim = min(route.cornerRadius, incoming / 2, outgoing / 2)
            let a = ScreenPoint(x: corner.x + (before.x - corner.x) * trim / incoming,
                                y: corner.y + (before.y - corner.y) * trim / incoming)
            let b = ScreenPoint(x: corner.x + (after.x - corner.x) * trim / outgoing,
                                y: corner.y + (after.y - corner.y) * trim / outgoing)
            points.append(a)
            for step in 1...8 {
                let t = Double(step) / 8, u = 1 - t
                points.append(.init(x: u * u * a.x + 2 * u * t * corner.x + t * t * b.x,
                                    y: u * u * a.y + 2 * u * t * corner.y + t * t * b.y))
            }
        }
        return ConnectorRoute(spotID: route.spotID, points: points, cornerRadius: route.cornerRadius)
    }

    static func crossings(_ routes: [ConnectorRoute]) -> Int {
        var result = 0
        for first in routes.indices {
            for second in routes.indices where second > first {
                for a in zip(routes[first].points, routes[first].points.dropFirst()) {
                    for b in zip(routes[second].points, routes[second].points.dropFirst()) {
                        if intersects(a.0, a.1, b.0, b.1) { result += 1 }
                    }
                }
            }
        }
        return result
    }

    private static func intersects(_ a: ScreenPoint, _ b: ScreenPoint, _ c: ScreenPoint, _ d: ScreenPoint) -> Bool {
        if max(a.x, b.x) < min(c.x, d.x) || max(c.x, d.x) < min(a.x, b.x) ||
            max(a.y, b.y) < min(c.y, d.y) || max(c.y, d.y) < min(a.y, b.y) { return false }
        func orientation(_ a: ScreenPoint, _ b: ScreenPoint, _ c: ScreenPoint) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let p = orientation(a, b, c), q = orientation(a, b, d)
        let r = orientation(c, d, a), s = orientation(c, d, b)
        // Shared endpoints and parallel segments are not proper crossings.
        return ((p > 0.00001 && q < -0.00001) || (p < -0.00001 && q > 0.00001)) &&
            ((r > 0.00001 && s < -0.00001) || (r < -0.00001 && s > 0.00001))
    }
}
