import AppKit
import ClickMoreCore

@MainActor
final class OverlayCoordinator {
    private unowned let controller: AppController
    private let trigger = OverlayPanel(levelOffset: 2)
    private var spotPanels: [UUID: OverlayPanel] = [:]
    private var connections: [OverlayPanel] = []

    init(controller: AppController) {
        self.controller = controller
        trigger.contentView = TriggerView(controller: controller)
        trigger.title = "ClickMore Trigger"
        trigger.hasShadow = true
        trigger.setAccessibilityRole(.window)
        trigger.setAccessibilitySubrole(.floatingWindow)
        trigger.setAccessibilityLabel("ClickMore trigger")
        if let view = trigger.contentView { trigger.setAccessibilityChildren([view]) }
        rebuildConnections()
    }

    func rebuildConnections() {
        connections.forEach { $0.close() }
        connections = NSScreen.screens.map { screen in
            let panel = OverlayPanel(levelOffset: 0)
            panel.ignoresMouseEvents = true
            panel.setAccessibilityElement(false)
            panel.setAccessibilityChildren([])
            panel.setFrame(screen.frame, display: false)
            panel.contentView = ConnectionView(controller: controller, screenOrigin: screen.frame.origin)
            return panel
        }
    }

    func refresh() {
        guard controller.preferences.enabled else {
            trigger.orderOut(nil)
            spotPanels.values.forEach { $0.orderOut(nil) }
            connections.forEach { $0.orderOut(nil) }
            return
        }
        let validIDs = Set(controller.layout.spots.map(\.id))
        for id in Array(spotPanels.keys) where !validIDs.contains(id) {
            spotPanels.removeValue(forKey: id)?.close()
        }
        for spot in controller.activeSpots {
            if spotPanels[spot.id] == nil {
                let panel = OverlayPanel(levelOffset: 1)
                panel.contentView = SpotView(controller: controller, id: spot.id)
                panel.title = "ClickMore Click Spot"
                panel.setAccessibilityRole(.window)
                panel.setAccessibilitySubrole(.floatingWindow)
                if let view = panel.contentView { panel.setAccessibilityChildren([view]) }
                spotPanels[spot.id] = panel
            }
        }
        for panel in connections {
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : controller.preferences.overlayOpacity
            panel.contentView?.needsDisplay = true
            if controller.preferences.showConnections || controller.editing { panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
        let activeIDs = Set(controller.activeSpots.map(\.id))
        for (id, panel) in spotPanels {
            guard activeIDs.contains(id), let spot = controller.layout.spots.first(where: { $0.id == id }) else {
                panel.orderOut(nil); continue
            }
            place(panel, center: spot.position, size: controller.editing ? 40 : 28)
            panel.ignoresMouseEvents = !controller.editing || controller.firing || controller.settingsHasFocus
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : controller.preferences.overlayOpacity
            (panel.contentView as? SpotView)?.updateAccessibility()
            panel.contentView?.needsDisplay = true
            panel.orderFrontRegardless()
        }
        place(trigger, center: controller.layout.trigger, size: controller.preferences.triggerSize)
        trigger.ignoresMouseEvents = controller.firing || controller.settingsHasFocus
        trigger.alphaValue = controller.preferences.overlayOpacity
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            trigger.alphaValue = 1
        }
        (trigger.contentView as? TriggerView)?.updateAccessibility()
        trigger.contentView?.needsDisplay = true
        trigger.orderFrontRegardless()
    }

    private func place(_ panel: NSPanel, center: ScreenPoint, size: Double) {
        panel.setFrame(CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size), display: true)
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    var diagnostics: [String: Any] {
        ["triggerVisible": trigger.isVisible,
         "triggerCanBecomeKey": trigger.canBecomeKey,
         "triggerPassThrough": trigger.ignoresMouseEvents,
         "triggerFrame": NSStringFromRect(trigger.frame),
         "triggerViewFrame": NSStringFromRect(trigger.contentView?.frame ?? .zero),
         "triggerAccessibilityLabel": trigger.contentView?.accessibilityLabel() ?? "",
         "triggerAccessibilityActions": trigger.contentView?.accessibilityCustomActions()?.map(\.name) ?? [],
         "spotAccessibilityLabels": spotPanels.values.compactMap { $0.contentView?.accessibilityLabel() }.sorted(),
         "visibleSpots": spotPanels.values.filter(\.isVisible).count,
         "spotsPassThrough": spotPanels.values.allSatisfy(\.ignoresMouseEvents),
         "connectionsPassThrough": connections.allSatisfy(\.ignoresMouseEvents)]
    }
}

@MainActor
final class OverlayPanel: NSPanel {
    init(levelOffset: Int) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        isMovable = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + levelOffset)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ConnectionView: NSView {
    private unowned let controller: AppController
    private let screenOrigin: CGPoint

    init(controller: AppController, screenOrigin: CGPoint) {
        self.controller = controller; self.screenOrigin = screenOrigin
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let routes = ConnectorRouter.routes(trigger: controller.layout.trigger, spots: controller.activeSpots,
                                            triggerRadius: controller.preferences.triggerSize / 2 - 3,
                                            spotRadius: controller.editing ? 11 : 6)
        for route in routes {
            let path = roundedPath(route.points.map(local))
            path.lineWidth = controller.editing ? 2.5 : 2
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            NSColor.black.withAlphaComponent(0.16).setStroke()
            path.lineWidth += 1.5
            path.stroke()
            path.lineWidth -= 1.5
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let color = controller.editing ? NSColor.controlAccentColor : NSColor.white
            color.withAlphaComponent(contrast ? 0.95 : (controller.editing ? 0.65 : 0.5)).setStroke()
            path.stroke()
        }
    }

    private func roundedPath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let corner = points[index]
            guard index + 1 < points.count else { path.line(to: corner); break }
            let before = points[index - 1], after = points[index + 1]
            let incoming = hypot(corner.x - before.x, corner.y - before.y)
            let outgoing = hypot(after.x - corner.x, after.y - corner.y)
            guard incoming > 0.01, outgoing > 0.01 else { path.line(to: corner); continue }
            let trim = min(5, incoming / 2, outgoing / 2)
            let a = CGPoint(x: corner.x + (before.x - corner.x) * trim / incoming,
                            y: corner.y + (before.y - corner.y) * trim / incoming)
            let b = CGPoint(x: corner.x + (after.x - corner.x) * trim / outgoing,
                            y: corner.y + (after.y - corner.y) * trim / outgoing)
            path.line(to: a)
            // Convert a quadratic corner into the cubic supported by AppKit.
            path.curve(to: b,
                       controlPoint1: CGPoint(x: a.x + (corner.x - a.x) * 2 / 3, y: a.y + (corner.y - a.y) * 2 / 3),
                       controlPoint2: CGPoint(x: b.x + (corner.x - b.x) * 2 / 3, y: b.y + (corner.y - b.y) * 2 / 3))
        }
        return path
    }

    private func local(_ point: ScreenPoint) -> CGPoint {
        CGPoint(x: point.x - screenOrigin.x, y: point.y - screenOrigin.y)
    }
}
