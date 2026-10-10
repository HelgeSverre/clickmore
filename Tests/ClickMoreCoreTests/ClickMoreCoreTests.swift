import Foundation
import Testing
@testable import ClickMoreCore

@MainActor
private final class RecordingPoster: ClickEventPosting {
    var isAuthorized = true
    var events: [(String, ScreenPoint, TimeInterval)] = []
    var begins = 0
    var finishes = 0
    func begin() { begins += 1 }
    func mouseDown(at point: ScreenPoint) { events.append(("down", point, ProcessInfo.processInfo.systemUptime)) }
    func mouseUp(at point: ScreenPoint) { events.append(("up", point, ProcessInfo.processInfo.systemUptime)) }
    func finish() { finishes += 1 }
}

struct ClickMoreCoreTests {
    @Test @MainActor func sendsFourPairedClicksInOrderWithDelay() async throws {
        let poster = RecordingPoster()
        let sequencer = ClickSequencer(poster: poster)
        let points = (0..<4).map { ScreenPoint(x: Double($0 * 100), y: 400) }
        try await sequencer.run(points: points, delayMilliseconds: 10)
        #expect(poster.events.map { $0.0 } == ["down", "up", "down", "up", "down", "up", "down", "up"])
        #expect(poster.events.enumerated().allSatisfy { $0.element.1 == points[$0.offset / 2] })
        for index in [2, 4, 6] {
            #expect(poster.events[index].2 - poster.events[index - 1].2 >= 0.009)
        }
        #expect(poster.begins == 1 && poster.finishes == 1 && !sequencer.isRunning)
    }

    @Test @MainActor func cancellationReleasesPressedButton() async throws {
        let poster = RecordingPoster()
        let sequencer = ClickSequencer(poster: poster)
        let point = ScreenPoint(x: 40, y: 50)
        let task = Task { try await sequencer.run(points: [point, point], delayMilliseconds: 250) }
        while poster.events.isEmpty { await Task.yield() }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {} catch { throw error }
        #expect(poster.events.map { $0.0 } == ["down", "up"])
        #expect(poster.finishes == 1 && !sequencer.isRunning)
    }

    @Test @MainActor func refusesConcurrentBatch() async throws {
        let poster = RecordingPoster()
        let sequencer = ClickSequencer(poster: poster)
        let task = Task { try await sequencer.run(points: [ScreenPoint(x: 0, y: 0)], delayMilliseconds: 10) }
        while !sequencer.isRunning { await Task.yield() }
        do {
            try await sequencer.run(points: [ScreenPoint(x: 10, y: 20)], delayMilliseconds: 10)
            Issue.record("Concurrent sequence was accepted")
        } catch ClickError.busy {} catch { throw error }
        try await task.value
        #expect(poster.events.count == 2)
    }

    @Test @MainActor func terminationCanReleaseBeforeTaskResumes() async throws {
        let poster = RecordingPoster()
        let sequencer = ClickSequencer(poster: poster)
        let point = ScreenPoint(x: 40, y: 50)
        let task = Task { try await sequencer.run(points: [point], delayMilliseconds: 10) }
        while poster.events.isEmpty { await Task.yield() }
        task.cancel()
        sequencer.releaseHeldButton()
        #expect(poster.events.map { $0.0 } == ["down", "up"])
        do { try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {} catch { throw error }
        #expect(poster.events.count == 2)
    }

    @Test @MainActor func refusesEventsWithoutPermission() async throws {
        let poster = RecordingPoster(); poster.isAuthorized = false
        let sequencer = ClickSequencer(poster: poster)
        do {
            try await sequencer.run(points: [ScreenPoint(x: 2, y: 3)], delayMilliseconds: 10)
            Issue.record("Unauthorized sequence was accepted")
        } catch ClickError.permissionRequired {} catch { throw error }
        #expect(poster.events.isEmpty && poster.begins == 0 && !sequencer.isRunning)
    }

    @Test func quartzConversionUsesPrimaryScreenOrigin() {
        #expect(ScreenPoint(x: 200, y: 700).quartz(primaryDisplayHeight: 900) == ScreenPoint(x: 200, y: 200))
        #expect(ScreenPoint(x: -500, y: 1200).quartz(primaryDisplayHeight: 900) == ScreenPoint(x: -500, y: -300))
        #expect(ScreenPoint(x: 200, y: -300).quartz(primaryDisplayHeight: 900) == ScreenPoint(x: 200, y: 1200))
    }

    @Test func disconnectedTargetsAreSkippedWithoutMovingThem() {
        let main = ScreenBounds(x: 0, y: 0, width: 1400, height: 900)
        var layout = Layout(trigger: ScreenPoint(x: -400, y: 600), spots: [
            ClickSpot(position: ScreenPoint(x: -600, y: 500)),
            ClickSpot(position: ScreenPoint(x: 800, y: 400))
        ])
        layout.recoverTrigger(on: [main], radius: 28)
        #expect(layout.trigger == ScreenPoint(x: 28, y: 600))
        #expect(layout.activeSpots(on: [main]) == [layout.spots[1]])
        #expect(layout.spots[0].position == ScreenPoint(x: -600, y: 500))
    }

    @Test func persistsCompleteLayoutAndPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("layout.json"))
        #expect(try store.load() == nil)
        var state = SavedState(layout: Layout(trigger: ScreenPoint(x: 12, y: 24),
            spots: [ClickSpot(position: ScreenPoint(x: 50, y: 60))]))
        state.preferences.enabled = false
        state.preferences.delayMilliseconds = 25
        state.preferences.spotCreationModifier = .shiftOption
        state.preferences.groupMoveModifier = .commandShift
        try store.save(state)
        #expect(try store.load() == state)
    }

    @Test func existingPreferencesKeepTheirValuesWhenGestureSettingIsMissing() throws {
        let json = Data("""
        {"enabled":false,"delayMilliseconds":35,"triggerSize":64,"showConnections":false,"overlayOpacity":0.7,"restorePointer":false}
        """.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(preferences.spotCreationModifier == .option)
        #expect(preferences.groupMoveModifier == .command)
        #expect(!preferences.enabled && preferences.delayMilliseconds == 35)
        #expect(preferences.triggerSize == 64 && !preferences.showConnections)
        #expect(preferences.overlayOpacity == 0.7 && !preferences.restorePointer)
    }

    @Test func groupMovementPreservesOffsetsAtDisplayEdges() {
        let layout = Layout(trigger: ScreenPoint(x: 100, y: 100), spots: [
            ClickSpot(position: ScreenPoint(x: 50, y: 200)),
            ClickSpot(position: ScreenPoint(x: 300, y: 80))
        ])
        let moved = layout.movingTogether(to: ScreenPoint(x: -100, y: 140),
                                         on: [ScreenBounds(x: 0, y: 0, width: 1000, height: 800)], radius: 28)
        #expect(moved.trigger == ScreenPoint(x: 28, y: 140))
        #expect(moved.spots.map(\.id) == layout.spots.map(\.id))
        for (before, after) in zip(layout.spots, moved.spots) {
            #expect(after.position.x - moved.trigger.x == before.position.x - layout.trigger.x)
            #expect(after.position.y - moved.trigger.y == before.position.y - layout.trigger.y)
        }
        #expect(layout.trigger == ScreenPoint(x: 100, y: 100))
    }

    @Test func existingCommandCreationBindingGetsDistinctGroupModifier() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{\"spotCreationModifier\":\"command\"}".utf8))
        #expect(preferences.spotCreationModifier == .command && preferences.groupMoveModifier == .option)
    }

    @Test func crowdedConnectorsUseSeparatePortsAndLanesInEveryDirection() {
        for direction in 0..<4 {
            func point(_ forward: Double, _ perpendicular: Double) -> ScreenPoint {
                switch direction {
                case 0: ScreenPoint(x: forward, y: perpendicular)
                case 1: ScreenPoint(x: -forward, y: perpendicular)
                case 2: ScreenPoint(x: perpendicular, y: forward)
                default: ScreenPoint(x: perpendicular, y: -forward)
                }
            }
            let spots = [3.0, 1.0, 2.0].map { ClickSpot(position: point(300, $0)) }
            let routes = ConnectorRouter.routes(trigger: point(0, 0), spots: spots, triggerRadius: 25, spotRadius: 6)
            #expect(routes.count == 3)
            // The routing axis can rotate with the cluster; measure actual
            // perpendicular separation rather than just its x/y projection.
            let lanes = routes.map { $0.points[2] }
            #expect(lanes[0].distance(to: lanes[1]) >= 10 - 0.000001 && lanes[1].distance(to: lanes[2]) >= 10 - 0.000001)
            #expect(Set(routes.map { "\($0.points[0].x),\($0.points[0].y)" }).count == 3)
            #expect(routes.allSatisfy { route in
                let spot = spots.first { $0.id == route.spotID }!
                return abs(route.points.first!.distance(to: point(0, 0)) - 25) < 0.001 &&
                    abs(route.points.last!.distance(to: spot.position) - 6) < 0.001
            })
            #expect(ConnectorRouter.routes(trigger: point(0, 0), spots: spots.reversed(), triggerRadius: 25, spotRadius: 6) == routes)
            #expect(spots.map(\.position) == [point(300, 3), point(300, 1), point(300, 2)])
        }
    }

    @Test func routingHandlesCoincidentTargetsAndTinyDistances() {
        let trigger = ScreenPoint(x: 100, y: 200)
        let spots = [trigger, ScreenPoint(x: 150, y: 200), ScreenPoint(x: 150, y: 200), ScreenPoint(x: 400, y: 220)]
            .map { ClickSpot(position: $0) }
        let routes = ConnectorRouter.routes(trigger: trigger, spots: spots, triggerRadius: 25, spotRadius: 11)
        #expect(routes.count == 3)
        #expect(routes.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(ConnectorRouter.routes(trigger: trigger, spots: [], triggerRadius: 25, spotRadius: 11).isEmpty)
    }

    @Test func overlappingTriggerTargetsDoNotCollapseOtherRoutingLanes() {
        let trigger = ScreenPoint(x: 0, y: 0)
        let spots = [trigger, ScreenPoint(x: 300, y: 1), ScreenPoint(x: 300, y: 2)]
            .map { ClickSpot(position: $0) }
        let routes = ConnectorRouter.routes(trigger: trigger, spots: spots, triggerRadius: 25, spotRadius: 6)
        #expect(routes.count == 2)
        #expect(routes.allSatisfy { $0.points[2].x > $0.points[1].x })
        #expect(routes[0].points[2].distance(to: routes[1].points[2]) >= 10 - 0.000001)
    }

    @Test func rejectsCorruptAndFutureSavedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(url: directory.appendingPathComponent("layout.json"))
        var state = SavedState(layout: Layout()); state.version = 99
        try store.save(state)
        #expect(throws: CocoaError.self) { try store.load() }
        try Data("bad json".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
