import Foundation
#if !ROUTING_MEDIA_EXPORT
import ClickMoreCore
#endif

@main
enum ExportRoutingStress {
    static func main() throws {
        let fixtures = RoutingFixture.cases + (1...50).map { RoutingFixture.random(seed: UInt64($0)) }
        let cases: [[String: Any]] = fixtures.map { fixture in
            let start = ProcessInfo.processInfo.systemUptime
            let routes = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots, triggerRadius: 25, spotRadius: 6)
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            return ["name": fixture.name, "crossings": RoutingMetrics.crossings(routes),
                    "routingMilliseconds": elapsed,
                    "spots": fixture.spots.map { ["id": $0.id.uuidString, "position": [$0.position.x, $0.position.y]] },
                    "routes": routes.map { ["id": $0.spotID.uuidString, "cornerRadius": $0.cornerRadius, "points": $0.points.map { [$0.x, $0.y] }] }]
        }
        let output = try JSONSerialization.data(withJSONObject: cases, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("\(cases.count) fixtures; \(cases.reduce(0) { $0 + ($1["crossings"] as! Int) }) proper crossings")
        if CommandLine.arguments.count > 2 { try exportDemo(to: CommandLine.arguments[2]) }
    }

    private static func exportDemo(to path: String) throws {
        let destinations = [ScreenPoint(x: -175, y: 110), .init(x: 175, y: 110), .init(x: -175, y: -110), .init(x: 175, y: -110)]
        var frames: [[String: Any]] = []
        func append(_ title: String, _ subtitle: String, trigger: ScreenPoint, spots: [ScreenPoint], cursor: ScreenPoint?, counts: [Int]) {
            let targets = RoutingFixture("demo", spots).spots
            let routes = ConnectorRouter.routes(trigger: trigger, spots: targets, triggerRadius: 25, spotRadius: 6)
            var frame: [String: Any] = ["title": title, "subtitle": subtitle, "trigger": [trigger.x, trigger.y],
                                     "spots": spots.map { [$0.x, $0.y] }, "counts": counts,
                                     "routes": routes.map { ["points": $0.points.map { [$0.x, $0.y] }, "cornerRadius": $0.cornerRadius] }]
            if let cursor { frame["cursor"] = [cursor.x, cursor.y] }
            frames.append(frame)
        }
        let zero = ScreenPoint(x: 0, y: 0)
        for index in 0..<4 {
            for step in 0..<20 {
                let progress = min(1, Double(step) / 14)
                let eased = progress * progress * (3 - 2 * progress)
                let point = ScreenPoint(x: destinations[index].x * eased, y: destinations[index].y * eased)
                append("Drag out your click spots", "Hold Option and drag from the trigger to a button.", trigger: zero,
                       spots: Array(destinations.prefix(index)) + [point], cursor: point, counts: [0, 0, 0, 0])
            }
        }
        for step in 0..<28 {
            let count = max(0, min(4, (step - 5) / 4))
            append("One click. All four buttons.", "Clicks play in order. Timing is slowed here for clarity.", trigger: zero,
                   spots: destinations, cursor: zero, counts: (0..<4).map { $0 < count ? 1 : 0 })
        }
        for step in 0..<28 {
            let progress = min(1, Double(step) / 20)
            let point = ScreenPoint(x: -55 * progress, y: 30 * progress)
            append("Move just the trigger", "Plain dragging keeps every click spot fixed.", trigger: point,
                   spots: destinations, cursor: point, counts: [1, 1, 1, 1])
        }
        for step in 0..<34 {
            let progress = min(1, Double(step) / 22)
            let point = ScreenPoint(x: -55 + 85 * progress, y: 30 - 50 * progress)
            let points = destinations.map { ScreenPoint(x: $0.x + 85 * progress, y: $0.y - 50 * progress) }
            append("Move the whole layout", "Hold Command to move the trigger and all its spots together.", trigger: point,
                   spots: points, cursor: point, counts: [1, 1, 1, 1])
        }
        let data = try JSONSerialization.data(withJSONObject: frames)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
