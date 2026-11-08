import Foundation

@MainActor
public protocol ClickEventPosting: AnyObject {
    var isAuthorized: Bool { get }
    func begin()
    func mouseDown(at point: ScreenPoint) throws
    func mouseUp(at point: ScreenPoint) throws
    func finish()
}

public enum ClickError: LocalizedError {
    case permissionRequired, busy, eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .permissionRequired: "Allow ClickMore in System Settings → Privacy & Security → Accessibility."
        case .busy: "A click sequence is already running."
        case .eventCreationFailed: "macOS could not create a mouse event."
        }
    }
}

/// All state and posting stay on the main actor. Sleeps yield to AppKit so the
/// menu's Disable action can cancel even a long sequence.
@MainActor
public final class ClickSequencer {
    public private(set) var isRunning = false
    private let poster: any ClickEventPosting
    private let sleep: @MainActor (Duration) async throws -> Void
    private var pressed: ScreenPoint?

    public convenience init(poster: any ClickEventPosting) {
        self.init(poster: poster, sleep: { try await Task.sleep(for: $0) })
    }

    init(poster: any ClickEventPosting, sleep: @escaping @MainActor (Duration) async throws -> Void) {
        self.poster = poster
        self.sleep = sleep
    }

    public func run(points: [ScreenPoint], delayMilliseconds: Double) async throws {
        guard !isRunning else { throw ClickError.busy }
        guard poster.isAuthorized else { throw ClickError.permissionRequired }
        let delay = delayMilliseconds.isFinite ? min(max(delayMilliseconds, 1), 250) : 10
        isRunning = true
        poster.begin()
        defer {
            // Cancellation must never leave the target application holding a button.
            releaseHeldButton()
            poster.finish()
            isRunning = false
        }
        for (index, point) in points.enumerated() {
            try Task.checkCancellation()
            guard poster.isAuthorized else { throw ClickError.permissionRequired }
            try poster.mouseDown(at: point)
            pressed = point
            try await sleep(.milliseconds(2))
            // A completed sleep may resume successfully after cancellation.
            // Shutdown may already have released this press synchronously.
            try Task.checkCancellation()
            try poster.mouseUp(at: point)
            pressed = nil
            if index < points.count - 1 {
                try await sleep(.milliseconds(delay))
            }
        }
    }

    /// App termination cannot wait for a cancelled task to resume. Release now.
    public func releaseHeldButton() {
        if let pressed { try? poster.mouseUp(at: pressed) }
        pressed = nil
    }
}
