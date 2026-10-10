import Foundation

/// Global AppKit coordinates: points, with the primary display's bottom-left at (0, 0).
public struct ScreenPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public func quartz(primaryDisplayHeight: Double) -> ScreenPoint {
        ScreenPoint(x: x, y: primaryDisplayHeight - y)
    }

    public func distance(to other: ScreenPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

public struct ScreenBounds: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func clamped(_ point: ScreenPoint, inset: Double) -> ScreenPoint {
        let ix = min(inset, width / 2), iy = min(inset, height / 2)
        return ScreenPoint(
            x: min(max(point.x, x + ix), x + width - ix),
            y: min(max(point.y, y + iy), y + height - iy)
        )
    }
}

public struct ClickSpot: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var position: ScreenPoint

    public init(id: UUID = UUID(), position: ScreenPoint) {
        self.id = id; self.position = position
    }
}

public struct Layout: Codable, Equatable, Sendable {
    public var trigger: ScreenPoint
    public var spots: [ClickSpot]

    public init(trigger: ScreenPoint = ScreenPoint(x: 500, y: 400), spots: [ClickSpot] = []) {
        self.trigger = trigger; self.spots = spots
    }

    /// Recover an off-screen trigger after unplugging a display. Targets stay where
    /// the user placed them; disconnected targets are skipped instead of retargeted.
    public mutating func recoverTrigger(on displays: [ScreenBounds], radius: Double) {
        guard let nearest = displays.map({ $0.clamped(trigger, inset: radius) })
            .min(by: { $0.distance(to: trigger) < $1.distance(to: trigger) }) else { return }
        trigger = nearest
    }

    public func activeSpots(on displays: [ScreenBounds]) -> [ClickSpot] {
        spots.filter { spot in
            displays.contains { bounds in
                spot.position.x >= bounds.x && spot.position.x < bounds.x + bounds.width &&
                spot.position.y >= bounds.y && spot.position.y < bounds.y + bounds.height
            }
        }
    }

    /// Translate from the original drag snapshot so clamping at a display edge
    /// never changes the distances between the trigger and its targets.
    public func movingTogether(to position: ScreenPoint, on displays: [ScreenBounds], radius: Double) -> Layout {
        var result = self
        result.trigger = position
        result.recoverTrigger(on: displays, radius: radius)
        let dx = result.trigger.x - trigger.x, dy = result.trigger.y - trigger.y
        result.spots = spots.map { spot in
            var translated = spot
            translated.position = ScreenPoint(x: spot.position.x + dx, y: spot.position.y + dy)
            return translated
        }
        return result
    }
}

public enum DragModifier: String, Codable, CaseIterable, Sendable {
    case option, shift, command, shiftOption, commandOption, commandShift

    public var displayName: String {
        switch self {
        case .option: "⌥ Option"
        case .shift: "⇧ Shift"
        case .command: "⌘ Command"
        case .shiftOption: "⇧⌥ Shift–Option"
        case .commandOption: "⌥⌘ Option–Command"
        case .commandShift: "⇧⌘ Shift–Command"
        }
    }

    public var spokenName: String {
        switch self {
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        case .shiftOption: "Shift–Option"
        case .commandOption: "Option–Command"
        case .commandShift: "Shift–Command"
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var delayMilliseconds: Double = 10
    public var triggerSize: Double = 56
    public var showConnections = true
    public var overlayOpacity: Double = 0.85
    public var restorePointer = true
    public var spotCreationModifier: DragModifier = .option
    public var groupMoveModifier: DragModifier = .command

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, delayMilliseconds, triggerSize, showConnections, overlayOpacity, restorePointer, spotCreationModifier, groupMoveModifier
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        delayMilliseconds = try values.decodeIfPresent(Double.self, forKey: .delayMilliseconds) ?? delayMilliseconds
        triggerSize = try values.decodeIfPresent(Double.self, forKey: .triggerSize) ?? triggerSize
        showConnections = try values.decodeIfPresent(Bool.self, forKey: .showConnections) ?? showConnections
        overlayOpacity = try values.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? overlayOpacity
        restorePointer = try values.decodeIfPresent(Bool.self, forKey: .restorePointer) ?? restorePointer
        spotCreationModifier = try values.decodeIfPresent(DragModifier.self, forKey: .spotCreationModifier) ?? .option
        groupMoveModifier = try values.decodeIfPresent(DragModifier.self, forKey: .groupMoveModifier) ?? .command
        validate()
    }

    public mutating func validate() {
        delayMilliseconds = delayMilliseconds.isFinite ? min(max(delayMilliseconds, 1), 250) : 10
        triggerSize = triggerSize.isFinite ? min(max(triggerSize, 44), 80) : 56
        overlayOpacity = overlayOpacity.isFinite ? min(max(overlayOpacity, 0.3), 1) : 0.85
        if groupMoveModifier == spotCreationModifier {
            groupMoveModifier = spotCreationModifier == .command ? .option : .command
        }
    }
}

public struct SavedState: Codable, Equatable, Sendable {
    public var version = 1
    public var layout: Layout
    public var preferences: Preferences

    public init(layout: Layout, preferences: Preferences = Preferences()) {
        self.layout = layout; self.preferences = preferences
    }
}

public struct StateStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> SavedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        guard state.version == 1,
              state.layout.trigger.x.isFinite, state.layout.trigger.y.isFinite,
              state.layout.spots.count <= 64,
              Set(state.layout.spots.map(\.id)).count == state.layout.spots.count,
              state.layout.spots.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        state.preferences.validate()
        return state
    }

    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
