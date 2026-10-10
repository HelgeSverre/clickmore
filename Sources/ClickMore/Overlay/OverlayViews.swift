import AppKit
import ClickMoreCore

extension DragModifier {
    var eventFlags: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .shift: .shift
        case .command: .command
        case .shiftOption: [.shift, .option]
        case .commandOption: [.command, .option]
        case .commandShift: [.command, .shift]
        }
    }
}

@MainActor
final class MenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
    @objc func invoke(_ sender: Any?) { perform() }
}

@MainActor
extension NSMenu {
    @discardableResult
    func action(_ title: String, checked: Bool? = nil, enabled: Bool = true, _ perform: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuAction(perform)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        item.isEnabled = enabled
        if let checked { item.state = checked ? .on : .off }
        addItem(item)
        return item
    }
}

@MainActor
class DraggableOverlayView: NSView {
    var dragStart: CGPoint?
    var originalPosition: ScreenPoint?
    var didDrag = false
    var hovering = false
    var pressedHighlight = false
    var position: ScreenPoint { ScreenPoint(x: 0, y: 0) }
    func move(to: ScreenPoint) {}
    func clicked() {}
    func visualChanged() { needsDisplay = true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; visualChanged() }
    override func mouseExited(with event: NSEvent) { hovering = false; visualChanged() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        // Ignore our tagged events even if a window-server update arrives late.
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != SystemClickPoster.eventMarker else { return }
        dragStart = NSEvent.mouseLocation
        originalPosition = position
        didDrag = false
        pressedHighlight = true
        visualChanged()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let originalPosition else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x, dy = now.y - dragStart.y
        guard didDrag || hypot(dx, dy) > 4 else { return }
        didDrag = true
        pressedHighlight = false
        visualChanged()
        move(to: ScreenPoint(x: originalPosition.x + dx, y: originalPosition.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        if !didDrag { clicked() }
        dragStart = nil; originalPosition = nil
        pressedHighlight = false
        visualChanged()
    }

    func movementActions() -> [NSAccessibilityCustomAction] {
        [("Move left", -10.0, 0.0), ("Move right", 10.0, 0.0),
         ("Move up", 0.0, 10.0), ("Move down", 0.0, -10.0)].map { name, dx, dy in
            NSAccessibilityCustomAction(name: name) { [weak self] in
                guard let self else { return false }
                self.move(to: ScreenPoint(x: self.position.x + dx, y: self.position.y + dy))
                return true
            }
        }
    }
}

/// Decorative layers never take pointer input or become separate VoiceOver items.
@MainActor
private final class MaterialSurface: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class GlyphSurface: NSView {
    var render: ((NSRect) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { render?(bounds) }
}

@MainActor
final class TriggerView: DraggableOverlayView {
    private unowned let controller: AppController
    private let material = MaterialSurface(frame: .zero)
    private let glyph = GlyphSurface(frame: .zero)
    private var creatingSpot = false
    private var draggedSpotID: UUID?
    private var wasEditing = false
    private var movingLayout = false
    private var originalLayout: Layout?
    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.masksToBounds = true
        material.setAccessibilityElement(false)
        glyph.setAccessibilityElement(false)
        glyph.autoresizingMask = [.width, .height]
        glyph.render = { [weak self] bounds in self?.drawGlyph(in: bounds) }
        addSubview(material)
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var position: ScreenPoint { controller.layout.trigger }
    override func move(to point: ScreenPoint) {
        if movingLayout, let originalLayout { controller.moveLayout(from: originalLayout, triggerTo: point) }
        else { controller.moveTrigger(to: point) }
    }
    override func clicked() { controller.fire() }
    override func accessibilityPerformPress() -> Bool { controller.fire(); return true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard dragStart != nil else { return }
        let flags = event.modifierFlags.intersection([.option, .command, .shift, .control])
        creatingSpot = flags == controller.preferences.spotCreationModifier.eventFlags
        movingLayout = flags == controller.preferences.groupMoveModifier.eventFlags
        originalLayout = movingLayout ? controller.layout : nil
        draggedSpotID = nil
        wasEditing = controller.editing
    }

    override func mouseDragged(with event: NSEvent) {
        guard creatingSpot, let dragStart else { super.mouseDragged(with: event); return }
        let now = NSEvent.mouseLocation
        guard didDrag || hypot(now.x - dragStart.x, now.y - dragStart.y) > 4 else { return }
        didDrag = true
        pressedHighlight = false
        let point = ScreenPoint(x: now.x, y: now.y)
        if let draggedSpotID { controller.moveSpot(draggedSpotID, to: point) }
        else { draggedSpotID = controller.addSpot(at: point) }
        NSCursor.dragCopy.set()
        visualChanged()
    }

    override func mouseUp(with event: NSEvent) {
        guard creatingSpot else {
            // Modifier-clicks reserve the gesture without firing a click batch.
            if movingLayout && !didDrag { didDrag = true }
            super.mouseUp(with: event)
            movingLayout = false; originalLayout = nil
            return
        }
        if let draggedSpotID {
            let now = NSEvent.mouseLocation
            controller.moveSpot(draggedSpotID, to: ScreenPoint(x: now.x, y: now.y))
            controller.setEditing(wasEditing)
        }
        creatingSpot = false; draggedSpotID = nil
        dragStart = nil; originalPosition = nil
        pressedHighlight = false
        NSCursor.arrow.set()
        visualChanged()
    }

    override func layout() {
        super.layout()
        material.frame = bounds.insetBy(dx: 3, dy: 3)
        material.layer?.cornerRadius = material.bounds.width / 2
        glyph.frame = bounds
    }

    override func visualChanged() { glyph.needsDisplay = true }

    func updateAccessibility() {
        let label = controller.editing ? "Finish arranging click spots" : "Click all connected spots"
        setAccessibilityLabel(label)
        setAccessibilityValue(controller.editing ? "Arranging" : "\(controller.activeSpots.count) spots, \(controller.permissionGranted ? "ready" : "mouse access required")")
        let modifier = controller.preferences.spotCreationModifier.spokenName
        let groupModifier = controller.preferences.groupMoveModifier.spokenName
        setAccessibilityHelp("Drag to move the trigger. \(groupModifier)-drag to move the trigger and all spots together. \(modifier)-drag to add a click spot. Right-click to arrange spots. Movement and placement are also available in Actions.")
        toolTip = "\(controller.editing ? "Finish arranging" : "Click all spots") · \(modifier)-drag to add · \(groupModifier)-drag to move all"
        var actions = movementActions()
        actions += [("Move layout left", -10.0, 0.0), ("Move layout right", 10.0, 0.0),
                    ("Move layout up", 0.0, 10.0), ("Move layout down", 0.0, -10.0)].map { name, dx, dy in
            NSAccessibilityCustomAction(name: name) { [weak controller] in
                guard let controller else { return false }
                let layout = controller.layout
                controller.moveLayout(from: layout, triggerTo: ScreenPoint(x: layout.trigger.x + dx, y: layout.trigger.y + dy))
                return true
            }
        }
        actions.append(NSAccessibilityCustomAction(name: "Add click spot") { [weak controller] in
            controller?.addSpot(); return controller != nil
        })
        actions.append(NSAccessibilityCustomAction(name: controller.editing ? "Finish arranging" : "Arrange click spots") { [weak controller] in
            guard let controller else { return false }; controller.setEditing(!controller.editing); return true
        })
        actions.append(NSAccessibilityCustomAction(name: "Open settings") { [weak controller] in
            controller?.showSettings?(); return controller != nil
        })
        if !controller.layout.spots.isEmpty {
            actions.append(NSAccessibilityCustomAction(name: "Remove all click spots") { [weak controller] in
                controller?.removeAllSpots(); return controller != nil
            })
        }
        setAccessibilityCustomActions(actions)
        visualChanged()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.action("Add Click Spot") { [weak controller] in controller?.addSpot() }
        menu.action(controller.editing ? "Finish Arranging" : "Arrange Click Spots") { [weak controller] in
            guard let controller else { return }; controller.setEditing(!controller.editing)
        }
        menu.action("Remove All Click Spots", enabled: !controller.layout.spots.isEmpty) { [weak controller] in controller?.removeAllSpots() }
        menu.addItem(.separator())
        menu.action("Show Connections", checked: controller.preferences.showConnections) { [weak controller] in
            controller?.updatePreferences { $0.showConnections.toggle() }
        }
        menu.action("Settings…") { [weak controller] in controller?.showSettings?() }
        menu.action("Disable ClickMore") { [weak controller] in controller?.updatePreferences { $0.enabled = false } }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func drawGlyph(in bounds: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3.5, dy: 3.5))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            NSColor.controlBackgroundColor.setFill(); circle.fill()
        }
        if hovering || pressedHighlight || controller.firing {
            NSColor.labelColor.withAlphaComponent(pressedHighlight || controller.firing ? 0.14 : 0.07).setFill()
            circle.fill()
        }
        let stroke = controller.editing ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(contrast ? 0.75 : 0.16)
        stroke.setStroke(); circle.lineWidth = controller.editing || contrast ? 1.5 : 0.75; circle.stroke()
        let symbol = controller.editing ? "checkmark" : "cursorarrow.click"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let size = bounds.width * 0.43
            let color = controller.permissionGranted || controller.editing ? NSColor.labelColor : NSColor.secondaryLabelColor
            image.withSymbolConfiguration(.init(pointSize: size, weight: .medium))?
                .withSymbolConfiguration(.init(paletteColors: [color]))?
                .draw(in: CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size))
        }
    }
}

@MainActor
final class SpotView: DraggableOverlayView {
    private unowned let controller: AppController
    private let id: UUID
    init(controller: AppController, id: UUID) {
        self.controller = controller; self.id = id
        super.init(frame: .zero)
        toolTip = "Drag to place · Right-click to remove or change order"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var position: ScreenPoint { controller.layout.spots.first(where: { $0.id == id })?.position ?? ScreenPoint(x: 0, y: 0) }
    override func move(to point: ScreenPoint) { controller.moveSpot(id, to: point) }

    func updateAccessibility() {
        let index = (controller.layout.spots.firstIndex(where: { $0.id == id }) ?? 0) + 1
        setAccessibilityLabel("Click spot \(index)")
        setAccessibilityValue("x \(position.x.formatted(.number.precision(.fractionLength(0)))), y \(position.y.formatted(.number.precision(.fractionLength(0))))")
        setAccessibilityHelp("Drag to place while arranging. Use Actions to move, reorder, or remove this spot.")
        toolTip = "Click spot \(index) · Drag to place · Right-click to edit"
        var actions = movementActions()
        actions.append(NSAccessibilityCustomAction(name: "Click earlier") { [weak controller, id] in controller?.reorderSpot(id, offset: -1); return controller != nil })
        actions.append(NSAccessibilityCustomAction(name: "Click later") { [weak controller, id] in controller?.reorderSpot(id, offset: 1); return controller != nil })
        actions.append(NSAccessibilityCustomAction(name: "Remove click spot") { [weak controller, id] in controller?.removeSpot(id); return controller != nil })
        setAccessibilityCustomActions(actions)
    }

    override func accessibilityPerformPress() -> Bool { controller.setEditing(true); return true }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = controller.layout.spots.firstIndex(where: { $0.id == id }) else { return }
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.action("Click Spot \(index + 1)", enabled: false) {}
        menu.action("Click Earlier", enabled: index > 0) { [weak controller, id] in controller?.reorderSpot(id, offset: -1) }
        menu.action("Click Later", enabled: index < controller.layout.spots.count - 1) { [weak controller, id] in controller?.reorderSpot(id, offset: 1) }
        menu.addItem(.separator())
        menu.action("Remove Click Spot") { [weak controller, id] in controller?.removeSpot(id) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = controller.editing ? 11 : 6
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        // A white ring with a thin dark halo remains legible on the game itself.
        NSColor.black.withAlphaComponent(0.35).setStroke(); ring.lineWidth = 3; ring.stroke()
        let accent = controller.editing && hovering ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.9)
        accent.setStroke(); ring.lineWidth = 1.5; ring.stroke()
        let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
        accent.setFill(); dot.fill()
        if controller.editing {
            let crosshair = NSBezierPath()
            for direction in [-1.0, 1.0] {
                crosshair.move(to: CGPoint(x: center.x + direction * 14, y: center.y))
                crosshair.line(to: CGPoint(x: center.x + direction * 18, y: center.y))
                crosshair.move(to: CGPoint(x: center.x, y: center.y + direction * 14))
                crosshair.line(to: CGPoint(x: center.x, y: center.y + direction * 18))
            }
            accent.setStroke(); crosshair.lineWidth = 1; crosshair.stroke()
        }
    }
}

@MainActor
func drawCentered(_ text: String, atY y: CGFloat, in rect: NSRect, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: y), withAttributes: attributes)
}
