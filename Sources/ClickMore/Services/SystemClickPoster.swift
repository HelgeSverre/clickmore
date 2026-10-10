import AppKit
import ClickMoreCore

@MainActor
final class SystemClickPoster: ClickEventPosting {
    var restorePointer = true
    var isAuthorized: Bool { CGPreflightPostEventAccess() }
    private var originalPointer: CGPoint?
    private var lastPoint: CGPoint?
    private let source = CGEventSource(stateID: .hidSystemState)
    static let eventMarker: Int64 = 0x434C49434B4D

    func begin() {
        originalPointer = CGEvent(source: nil)?.location
        lastPoint = nil
    }

    func mouseDown(at point: ScreenPoint) throws { try post(.leftMouseDown, at: point) }
    func mouseUp(at point: ScreenPoint) throws { try post(.leftMouseUp, at: point) }

    private func post(_ type: CGEventType, at point: ScreenPoint) throws {
        // NSScreen.main is the focused screen, NOT necessarily the coordinate origin.
        let quartz = point.quartz(primaryDisplayHeight: Double(NSScreen.screens.first?.frame.maxY ?? 0))
        let location = CGPoint(x: quartz.x, y: quartz.y)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: .left) else {
            throw ClickError.eventCreationFailed
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        event.flags = []
        event.post(tap: .cghidEventTap)
        lastPoint = location
    }

    func finish() {
        defer { originalPointer = nil; lastPoint = nil }
        guard restorePointer, let originalPointer, let lastPoint,
              let current = CGEvent(source: nil)?.location,
              hypot(current.x - lastPoint.x, current.y - lastPoint.y) <= 3 else { return }
        // Don't fight someone who moves the pointer during a sequence.
        CGWarpMouseCursorPosition(originalPointer)
    }
}
