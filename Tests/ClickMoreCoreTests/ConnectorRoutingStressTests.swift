import Foundation
import Testing
import ClickMoreCore

struct ConnectorRoutingStressTests {
    @Test func fixedAndSeededClustersPreserveTargetsWithoutCrossing() {
        let fixtures = RoutingFixture.cases + (1...50).map { RoutingFixture.random(seed: UInt64($0)) }
        for fixture in fixtures {
            let original = fixture.spots
            for targetRadius in [6.0, 11.0] {
                let routes = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots,
                                                    triggerRadius: 25, spotRadius: targetRadius)
                #expect(routes.count == fixture.spots.count, "\(fixture.name)")
                #expect(RoutingMetrics.crossings(routes) == 0, "\(fixture.name), radius \(targetRadius)")
                for route in routes {
                    let target = fixture.spots.first { $0.id == route.spotID }!
                    #expect(route.points.count >= 2)
                    #expect(route.cornerRadius.isFinite && route.cornerRadius >= 0 && route.cornerRadius <= 5)
                    #expect(route.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    #expect(abs(route.points[0].distance(to: .init(x: 0, y: 0)) - 25) < 0.000001)
                    #expect(abs(route.points.last!.distance(to: target.position) - targetRadius) < 0.000001)
                    #expect(zip(route.points, route.points.dropFirst()).allSatisfy { $0.distance(to: $1) > 0.000001 })
                }
                #expect(fixture.spots == original)
                #expect(ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots.reversed(),
                                               triggerRadius: 25, spotRadius: targetRadius) == routes)
            }
        }
    }

    @Test func roundedCornersKeepCrowdedRoutesFromCrossing() {
        for fixture in RoutingFixture.cases {
            for targetRadius in [6.0, 11.0] {
                let routes = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots,
                                                    triggerRadius: 25, spotRadius: targetRadius)
                #expect(RoutingMetrics.crossings(routes.map(RoutingMetrics.rounded)) == 0,
                        "Rounded \(fixture.name), radius \(targetRadius)")
            }
        }
    }

    @Test func clusteredRoutesTranslateWithTheLayout() {
        let origin = ScreenPoint(x: -400, y: 1250)
        for fixture in RoutingFixture.cases {
            let translated = fixture.spots.map { spot in
                ClickSpot(id: spot.id, position: .init(x: spot.position.x + origin.x, y: spot.position.y + origin.y))
            }
            let original = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots, triggerRadius: 25, spotRadius: 6)
            let moved = ConnectorRouter.routes(trigger: origin, spots: translated, triggerRadius: 25, spotRadius: 6)
            for route in original {
                let other = moved.first { $0.spotID == route.spotID }!
                #expect(route.points.count == other.points.count)
                for (a, b) in zip(route.points, other.points) {
                    #expect(ScreenPoint(x: a.x + origin.x, y: a.y + origin.y).distance(to: b) < 0.000001)
                }
            }
        }
    }

    @Test func crowdedRoutesAvoidExaggeratedSidewaysDetours() {
        for fixture in [RoutingFixture.cases[2], RoutingFixture.cases[3], RoutingFixture.cases[4]] {
            let routes = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: fixture.spots, triggerRadius: 25, spotRadius: 11)
            for route in routes {
                let end = fixture.spots.first { $0.id == route.spotID }!.position
                let distance = hypot(end.x, end.y)
                let deviation = route.points.map { abs($0.x * end.y - $0.y * end.x) / distance }.max()!
                #expect(deviation < 60, "\(fixture.name): \(deviation) point detour")
            }
        }
    }

    @Test func draggingAcrossCardinalBoundaryDoesNotFlipPorts() {
        let far = ClickSpot(position: .init(x: 143, y: 440))
        let near = ClickSpot(position: .init(x: 190, y: 189))
        let before = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: [far, near], triggerRadius: 25, spotRadius: 6)
        let moved = ClickSpot(id: near.id, position: .init(x: 189, y: 190))
        let after = ConnectorRouter.routes(trigger: .init(x: 0, y: 0), spots: [far, moved], triggerRadius: 25, spotRadius: 6)
        for route in before {
            let other = after.first { $0.spotID == route.spotID }!
            #expect(route.points[0].distance(to: other.points[0]) < 1)
        }
    }
}
