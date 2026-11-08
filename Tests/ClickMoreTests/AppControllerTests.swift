import AppKit
import Testing
@testable import ClickMore
@testable import ClickMoreCore

@MainActor
private final class PausedPoster: ClickEventPosting {
    var isAuthorized = true
    var events: [String] = []
    var points: [ScreenPoint] = []
    private var suspension: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var didPause = false

    func begin() { events.append("begin") }
    func mouseDown(at point: ScreenPoint) { events.append("down"); points.append(point) }
    func mouseUp(at point: ScreenPoint) { events.append("up") }
    func finish() { events.append("finish") }

    func sleep(_ duration: Duration) async throws {
        if !didPause {
            didPause = true
            await withCheckedContinuation { continuation in
                suspension = continuation
                observer?.resume()
                observer = nil
            }
        }
        try Task.checkCancellation()
    }

    func waitForPress() async {
        if suspension != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() {
        suspension?.resume()
        suspension = nil
    }
}

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor
struct AppControllerTests {
    enum Removal { case single, all, missing }

    @Test(arguments: [Removal.single, .all, .missing])
    func removingTargetsCancelsPendingClicks(removal: Removal) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let poster = PausedPoster()
        let sequencer = ClickSequencer(poster: poster, sleep: poster.sleep)
        let controller = AppController(store: StateStore(url: directory.appendingPathComponent("layout.json")),
                                       sequencer: sequencer, checkPermission: { true })
        defer {
            controller.updatePreferences { $0.enabled = false }
            controller.shutdown()
        }
        let display = try #require(AppController.displays.first)
        let first = ScreenPoint(x: display.x + 100, y: display.y + 100)
        let second = ScreenPoint(x: display.x + 200, y: display.y + 200)
        controller.useTestLayout(trigger: first, spots: [first, second])
        let removedID = controller.layout.spots[1].id
        controller.fire()
        await poster.waitForPress()
        #expect(controller.firing && sequencer.isRunning)
        switch removal {
        case .single: controller.removeSpot(removedID)
        case .all: controller.removeAllSpots()
        case .missing: controller.removeSpot(UUID())
        }
        // A replacement is rejected until the cancelled owner has cleaned up.
        controller.fire()
        poster.resume()
        while controller.firing { await Task.yield() }
        if removal == .missing {
            #expect(poster.events == ["begin", "down", "up", "down", "up", "finish"])
            #expect(poster.points == [first, second])
            #expect(!sequencer.isRunning)
            #expect(controller.layout.spots.map(\.position) == [first, second])
            return
        }
        #expect(poster.events == ["begin", "down", "up", "finish"])
        #expect(poster.points == [first])
        #expect(!sequencer.isRunning)
        #expect(!controller.layout.spots.contains { $0.id == removedID })
        if removal == .single {
            controller.fire()
            while controller.firing { await Task.yield() }
            #expect(poster.events == ["begin", "down", "up", "finish", "begin", "down", "up", "finish"])
            #expect(poster.points == [first, first])
        }
    }
}
