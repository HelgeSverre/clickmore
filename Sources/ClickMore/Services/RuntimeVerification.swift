import AppKit
import ClickMoreCore

struct TestTargetReceipt: Codable {
    let trigger: ScreenPoint
    let spots: [ScreenPoint]
    let counts: [Int]
    let order: [Int]
    let pid: Int32
}

/// Exercises the real AppKit test board. Local mode needs no privacy permission;
/// integration mode posts through the same system backend used by the trigger.
@MainActor
enum RuntimeVerification {
    static func startExternal(controller: AppController, receiptURL: URL) {
        Task {
            do {
                guard CGPreflightPostEventAccess() else { throw ClickError.permissionRequired }
                let initial = try JSONDecoder().decode(TestTargetReceipt.self, from: Data(contentsOf: receiptURL))
                guard initial.pid != ProcessInfo.processInfo.processIdentifier, initial.spots.count == 4 else {
                    throw VerificationError("Test buttons must run in a separate process.")
                }
                controller.useTestLayout(trigger: initial.trigger, spots: initial.spots)
                try await Task.sleep(for: .milliseconds(100))
                let targetWasFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == initial.pid
                controller.fire()
                let first = try await waitForCounts([1, 1, 1, 1], receiptURL: receiptURL)
                guard first.order == [0, 1, 2, 3] else { throw VerificationError("Incorrect external click order.") }
                // The receipt is written by the target as soon as its last up
                // arrives. Wait for the sender and WindowServer to restore the
                // trigger's hit testing before starting another physical click.
                while controller.firing { try await Task.sleep(for: .milliseconds(5)) }
                try await Task.sleep(for: .milliseconds(80))
                let point = initial.trigger.quartz(primaryDisplayHeight: Double(NSScreen.screens.first?.frame.maxY ?? 0))
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: CGPoint(x: point.x, y: point.y), mouseButton: .left) else {
                        throw ClickError.eventCreationFailed
                    }
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                    event.post(tap: .cghidEventTap)
                    try await Task.sleep(for: .milliseconds(20))
                }
                let second = try await waitForCounts([2, 2, 2, 2], receiptURL: receiptURL)
                guard second.order == [0, 1, 2, 3, 0, 1, 2, 3] else {
                    throw VerificationError("Incorrect click order after clicking the trigger.")
                }
                try await Task.sleep(for: .milliseconds(50))
                let focusPreserved = NSWorkspace.shared.frontmostApplication?.processIdentifier == initial.pid
                guard targetWasFrontmost && focusPreserved else { throw VerificationError("The trigger changed the target app's focus.") }
                let quickCreation = try await verifyModifierDrag(controller: controller)
                let groupMovement = try await verifyGroupDrag(controller: controller)
                controller.setSettingsHasFocus(true)
                guard controller.overlays.diagnostics["triggerPassThrough"] as? Bool == true else {
                    throw VerificationError("Settings must receive clicks through an overlapping trigger.")
                }
                controller.setSettingsHasFocus(false)
                controller.removeAllSpots()
                guard controller.layout.spots.isEmpty,
                      controller.overlays.diagnostics["visibleSpots"] as? Int == 0 else {
                    throw VerificationError("Remove All left click spots visible.")
                }
                controller.useTestLayout(trigger: initial.trigger, spots: initial.spots)
                write(["passed": true, "mode": "cross-process-system-events-and-trigger",
                       "counts": second.counts, "order": second.order,
                       "targetPID": initial.pid, "clickMorePID": ProcessInfo.processInfo.processIdentifier,
                       "focusPreserved": focusPreserved, "postEventAccess": true,
                       "modifierDragAndRebinding": quickCreation,
                       "groupDragAndRebinding": groupMovement,
                       "plainDragKeepsSpotsFixed": true, "removeAllSpots": true, "settingsPassThrough": true,
                       "overlay": controller.overlays.diagnostics])
            } catch {
                write(["passed": false, "error": error.localizedDescription,
                       "postEventAccess": CGPreflightPostEventAccess(),
                       "overlay": controller.overlays.diagnostics])
            }
            if !CommandLine.arguments.contains("--keep-open") { NSApp.terminate(nil) }
        }
    }

    private static func verifyGroupDrag(controller: AppController) async throws -> Bool {
        let original = controller.layout
        let oldModifier = controller.preferences.groupMoveModifier
        defer { controller.updatePreferences { $0.groupMoveModifier = oldModifier } }
        for modifier in [DragModifier.command, .commandShift] {
            controller.updatePreferences { $0.groupMoveModifier = modifier }
            let flags: CGEventFlags = modifier == .command ? .maskCommand : [.maskCommand, .maskShift]
            try await drag(from: original.trigger, dx: 40, dy: 20, flags: flags)
            let expected = original.movingTogether(to: ScreenPoint(x: original.trigger.x + 40, y: original.trigger.y + 20),
                                                  on: AppController.visibleDisplays, radius: controller.preferences.triggerSize / 2)
            guard controller.layout.trigger.distance(to: expected.trigger) < 3,
                  zip(controller.layout.spots, expected.spots).allSatisfy({ $0.id == $1.id && $0.position.distance(to: $1.position) < 3 }),
                  controller.layout.spots.count == original.spots.count else {
                throw VerificationError("\(modifier.spokenName)-drag did not translate the complete layout.")
            }
            controller.moveLayout(from: original, triggerTo: original.trigger)
        }
        let beforePlainDrag = controller.layout
        try await drag(from: beforePlainDrag.trigger, dx: -40, dy: -20, flags: [])
        guard controller.layout.trigger.distance(to: ScreenPoint(x: beforePlainDrag.trigger.x - 40, y: beforePlainDrag.trigger.y - 20)) < 3,
              controller.layout.spots == beforePlainDrag.spots else {
            throw VerificationError("Plain dragging changed target positions or failed to move the trigger.")
        }
        controller.moveLayout(from: original, triggerTo: original.trigger)
        return true
    }

    private static func drag(from start: ScreenPoint, dx: Double, dy: Double, flags: CGEventFlags) async throws {
        try await Task.sleep(for: .milliseconds(80))
        try await sendMouse(.leftMouseDown, at: start, flags: flags)
        for step in 1...5 {
            try await sendMouse(.leftMouseDragged,
                                at: ScreenPoint(x: start.x + dx * Double(step) / 5, y: start.y + dy * Double(step) / 5), flags: flags)
        }
        try await sendMouse(.leftMouseUp, at: ScreenPoint(x: start.x + dx, y: start.y + dy), flags: flags)
        try await Task.sleep(for: .milliseconds(100))
    }

    private static func waitForCounts(_ counts: [Int], receiptURL: URL) async throws -> TestTargetReceipt {
        for _ in 0..<100 {
            let receipt = try JSONDecoder().decode(TestTargetReceipt.self, from: Data(contentsOf: receiptURL))
            if receipt.counts == counts { return receipt }
            try await Task.sleep(for: .milliseconds(20))
        }
        let receipt = try JSONDecoder().decode(TestTargetReceipt.self, from: Data(contentsOf: receiptURL))
        throw VerificationError("Expected external counts \(counts), received \(receipt.counts).")
    }

    private static func verifyModifierDrag(controller: AppController) async throws -> Bool {
        let trigger = controller.layout.trigger
        let oldModifier = controller.preferences.spotCreationModifier
        defer { controller.updatePreferences { $0.spotCreationModifier = oldModifier } }
        for modifier in [DragModifier.option, .shiftOption] {
            controller.updatePreferences { $0.spotCreationModifier = modifier }
            let count = controller.layout.spots.count
            let end = ScreenPoint(x: trigger.x + 70, y: trigger.y)
            let flags: CGEventFlags = modifier == .option ? .maskAlternate : [.maskAlternate, .maskShift]
            try await Task.sleep(for: .milliseconds(80))
            try await sendMouse(.leftMouseDown, at: trigger, flags: flags)
            for step in 1...5 {
                try await sendMouse(.leftMouseDragged,
                    at: ScreenPoint(x: trigger.x + Double(step) * 14, y: trigger.y), flags: flags)
            }
            try await sendMouse(.leftMouseUp, at: end, flags: flags)
            try await Task.sleep(for: .milliseconds(100))
            guard controller.layout.spots.count == count + 1,
                  controller.layout.trigger == trigger,
                  !controller.editing,
                  let spot = controller.layout.spots.last, spot.position.distance(to: end) < 3 else {
                throw VerificationError("\(modifier.spokenName)-drag did not create a spot at the drop location without moving the trigger.")
            }
            controller.removeSpot(spot.id)
        }
        return true
    }

    private static func sendMouse(_ type: CGEventType, at point: ScreenPoint, flags: CGEventFlags) async throws {
        let quartz = point.quartz(primaryDisplayHeight: Double(NSScreen.screens.first?.frame.maxY ?? 0))
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: CGPoint(x: quartz.x, y: quartz.y), mouseButton: .left) else {
            throw ClickError.eventCreationFailed
        }
        event.flags = flags
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(25))
    }

    static func start(controller: AppController, board: TestBoardView, systemEvents: Bool) {
        Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                board.useLayout()
                if systemEvents {
                    guard CGPreflightPostEventAccess() else { throw ClickError.permissionRequired }
                    controller.fire()
                    try await Task.sleep(for: .milliseconds(200))
                    guard board.counts == [1, 1, 1, 1], board.receivedOrder == [0, 1, 2, 3] else {
                        throw VerificationError("System click delivery failed: \(board.counts), order \(board.receivedOrder)")
                    }
                    // A second pass starts with a genuine event routed through the
                    // floating trigger, instead of calling its action directly.
                    board.resetCounts()
                    let point = controller.layout.trigger.quartz(primaryDisplayHeight: Double(NSScreen.screens.first?.frame.maxY ?? 0))
                    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                            mouseCursorPosition: CGPoint(x: point.x, y: point.y), mouseButton: .left)
                        event?.setIntegerValueField(.mouseEventClickState, value: 1)
                        event?.post(tap: .cghidEventTap)
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    try await Task.sleep(for: .milliseconds(300))
                } else {
                    let sequencer = ClickSequencer(poster: NativeTestPoster(board: board))
                    try await sequencer.run(points: board.spotPositions, delayMilliseconds: 10)
                }
                guard board.counts == [1, 1, 1, 1], board.receivedOrder == [0, 1, 2, 3] else {
                    throw VerificationError("Expected one click per card in order: \(board.counts), order \(board.receivedOrder)")
                }
                let report: [String: Any] = [
                    "passed": true, "mode": systemEvents ? "system-events-and-trigger" : "appkit-local-events",
                    "counts": board.counts, "order": board.receivedOrder,
                    "postEventAccess": CGPreflightPostEventAccess(),
                    "overlay": controller.overlays.diagnostics
                ]
                write(report)
            } catch {
                write(["passed": false, "error": error.localizedDescription,
                       "postEventAccess": CGPreflightPostEventAccess(), "counts": board.counts])
            }
            if !CommandLine.arguments.contains("--keep-open") { NSApp.terminate(nil) }
        }
    }

    private static func write(_ report: [String: Any]) {
        guard let index = CommandLine.arguments.firstIndex(of: "--report"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        } catch { NSLog("Could not write runtime verification: %@", error.localizedDescription) }
    }
}

private struct VerificationError: LocalizedError {
    let details: String
    init(_ details: String) { self.details = details }
    var errorDescription: String? { details }
}

@MainActor
private final class NativeTestPoster: ClickEventPosting {
    let board: TestBoardView
    var isAuthorized: Bool { true }
    init(board: TestBoardView) { self.board = board }
    func begin() {}
    func finish() {}
    func mouseDown(at point: ScreenPoint) throws { try send(.leftMouseDown, point: point) }
    func mouseUp(at point: ScreenPoint) throws { try send(.leftMouseUp, point: point) }

    private func send(_ type: NSEvent.EventType, point: ScreenPoint) throws {
        guard let window = board.window,
              let event = NSEvent.mouseEvent(with: type,
                  location: window.convertPoint(fromScreen: CGPoint(x: point.x, y: point.y)),
                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            throw ClickError.eventCreationFailed
        }
        window.sendEvent(event)
    }
}
