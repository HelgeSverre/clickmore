import AppKit

// Keep the app icon reproducible without an asset pipeline or dependencies.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 220, yRadius: 220)
        NSColor(calibratedRed: 0.055, green: 0.14, blue: 0.18, alpha: 1).setFill(); background.fill()
        let nodes: [CGPoint] = [CGPoint(x: 260, y: 260), CGPoint(x: 764, y: 260),
                                CGPoint(x: 260, y: 764), CGPoint(x: 764, y: 764)]
        let accent = NSColor(calibratedRed: 0.2, green: 0.87, blue: 0.8, alpha: 1)
        for point in nodes {
            let line = NSBezierPath(); line.move(to: CGPoint(x: 512, y: 512)); line.line(to: point)
            line.lineWidth = 24; accent.withAlphaComponent(0.65).setStroke(); line.stroke()
            let circle = NSBezierPath(ovalIn: CGRect(x: point.x - 56, y: point.y - 56, width: 112, height: 112))
            NSColor(calibratedRed: 0.055, green: 0.14, blue: 0.18, alpha: 1).setFill(); circle.fill()
            accent.setStroke(); circle.lineWidth = 20; circle.stroke()
        }
        let center = NSBezierPath(ovalIn: CGRect(x: 350, y: 350, width: 324, height: 324))
        accent.setFill(); center.fill()
        let cursor = NSBezierPath()
        cursor.move(to: CGPoint(x: 444, y: 610)); cursor.line(to: CGPoint(x: 444, y: 424))
        cursor.line(to: CGPoint(x: 491, y: 460)); cursor.line(to: CGPoint(x: 526, y: 396))
        cursor.line(to: CGPoint(x: 558, y: 414)); cursor.line(to: CGPoint(x: 523, y: 478))
        cursor.line(to: CGPoint(x: 582, y: 480)); cursor.close()
        NSColor(calibratedRed: 0.055, green: 0.14, blue: 0.18, alpha: 1).setFill(); cursor.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
