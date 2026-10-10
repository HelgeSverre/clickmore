import AppKit
import ClickMoreCore

@MainActor
final class TestBoardController: NSWindowController, NSWindowDelegate {
    let board: TestBoardView
    private unowned let controller: AppController
    init(controller: AppController) {
        self.controller = controller
        board = TestBoardView(controller: controller)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ClickMore · Test Board"
        window.contentView = board
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { controller.restoreFromTestLayout() }
    func windowDidMove(_ notification: Notification) {
        if controller.hasTestLayout { board.useLayout() }
        board.publishSnapshot()
    }
}

@MainActor
final class TestBoardView: NSView {
    private unowned let controller: AppController
    private(set) var counts = [0, 0, 0, 0]
    private(set) var receivedOrder: [Int] = []
    private var pressed: Int?
    private let names = ["ICE", "SUGAR", "GLASS", "LEMON"]
    private let colors: [NSColor] = [.systemCyan, .systemPink, .systemPurple, .systemYellow]

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: 520, height: 540))
        let use = NSButton(title: "Place Trigger & Four Spots", target: self, action: #selector(useLayout))
        use.bezelStyle = .rounded
        use.frame = CGRect(x: 120, y: 32, width: 280, height: 32)
        addSubview(use)
        let reset = NSButton(title: "Reset Counters", target: self, action: #selector(resetCounts))
        reset.bezelStyle = .rounded
        reset.frame = CGRect(x: 180, y: 0, width: 160, height: 30)
        addSubview(reset)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var cardFrames: [NSRect] {
        [CGRect(x: 70, y: 300, width: 150, height: 130),
         CGRect(x: 300, y: 300, width: 150, height: 130),
         CGRect(x: 70, y: 90, width: 150, height: 130),
         CGRect(x: 300, y: 90, width: 150, height: 130)]
    }

    var spotPositions: [ScreenPoint] {
        guard let window else { return [] }
        return cardFrames.map { frame in
            let point = window.convertPoint(toScreen: convert(CGPoint(x: frame.midX, y: frame.midY), to: nil))
            return ScreenPoint(x: point.x, y: point.y)
        }
    }

    @objc func useLayout() {
        guard let window else { return }
        let center = window.convertPoint(toScreen: convert(CGPoint(x: 260, y: 260), to: nil))
        controller.useTestLayout(trigger: ScreenPoint(x: center.x, y: center.y), spots: spotPositions)
    }

    @objc func resetCounts() {
        counts = [0, 0, 0, 0]; receivedOrder = []; pressed = nil; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = cardFrames.firstIndex(where: { $0.contains(point) })
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let pressed, cardFrames[pressed].contains(point) {
            counts[pressed] += 1
            receivedOrder.append(pressed)
        }
        pressed = nil
        needsDisplay = true
        publishSnapshot()
    }

    func publishSnapshot() {
        guard CommandLine.arguments.contains("--test-target"),
              let index = CommandLine.arguments.firstIndex(of: "--target-report"),
              CommandLine.arguments.indices.contains(index + 1), let window else { return }
        let center = window.convertPoint(toScreen: convert(CGPoint(x: 260, y: 260), to: nil))
        let receipt = TestTargetReceipt(trigger: ScreenPoint(x: center.x, y: center.y),
                                        spots: spotPositions, counts: counts, order: receivedOrder,
                                        pid: ProcessInfo.processInfo.processIdentifier)
        do {
            try JSONEncoder().encode(receipt).write(
                to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        } catch { NSLog("Could not write test-target receipt: %@", error.localizedDescription) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        drawCentered("One click → four buttons", atY: 492, in: bounds, font: .systemFont(ofSize: 23, weight: .bold), color: .labelColor)
        drawCentered("Place the spots, then click the floating trigger in the middle.", atY: 464, in: bounds,
                     font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        for (index, frame) in cardFrames.enumerated() {
            let path = NSBezierPath(roundedRect: frame, xRadius: 16, yRadius: 16)
            colors[index].withAlphaComponent(pressed == index ? 0.4 : 0.16).setFill(); path.fill()
            colors[index].withAlphaComponent(0.65).setStroke(); path.lineWidth = 1.5; path.stroke()
            drawCentered(names[index], atY: frame.maxY - 31, in: frame,
                         font: .systemFont(ofSize: 12, weight: .bold), color: .labelColor)
            drawCentered("\(counts[index])", atY: frame.minY + 36, in: frame,
                         font: .monospacedDigitSystemFont(ofSize: 38, weight: .medium), color: .labelColor)
            drawCentered("clicks", atY: frame.minY + 17, in: frame,
                         font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        }
    }
}
