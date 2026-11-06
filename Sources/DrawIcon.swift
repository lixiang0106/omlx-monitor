import AppKit
import Foundation

// A native, vector-drawn icon: a model processor inside a live monitor.
// All coordinates are relative to a 1024 pt canvas.
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

func strokeLine(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    guard let first = points.first else { return }
    let line = NSBezierPath()
    line.move(to: first)
    for point in points.dropFirst() { line.line(to: point) }
    line.lineWidth = width
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    color.setStroke()
    line.stroke()
}

func drawIcon() {
    let tile = rounded(76, 76, 872, 872, 205)
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x071630, alpha: 0.30)
    tileShadow.shadowBlurRadius = 24
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    tileShadow.set()
    color(0x143857).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x0A2340), color(0x14687C), color(0x2EBDAC)])!
        .draw(in: tile, angle: 52)
    let shine = rounded(90, 90, 844, 844, 192)
    color(0xFFFFFF, alpha: 0.20).setStroke()
    shine.lineWidth = 4
    shine.stroke()

    let bezelShadow = NSShadow()
    bezelShadow.shadowColor = color(0x021226, alpha: 0.28)
    bezelShadow.shadowBlurRadius = 32
    bezelShadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    bezelShadow.set()
    let screen = rounded(183, 264, 658, 520, 82)
    NSGradient(colors: [color(0xF4FFFE), color(0xD6F4F0)])!.draw(in: screen, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let screenBody = rounded(209, 290, 606, 434, 58)
    NSGradient(colors: [color(0x092741), color(0x123E55)])!.draw(in: screenBody, angle: 90)
    color(0xC8FFF7, alpha: 0.17).setStroke()
    screenBody.lineWidth = 3
    screenBody.stroke()

    let chip = rounded(394, 470, 236, 204, 36)
    color(0x66E5D0).setFill()
    chip.fill()
    let chipInner = rounded(417, 493, 190, 158, 23)
    color(0x0C3D51).setFill()
    chipInner.fill()
    for x in [CGFloat(442), 489, 536, 583] {
        strokeLine([NSPoint(x: x, y: 456), NSPoint(x: x, y: 470)], color: color(0x66E5D0), width: 13)
        strokeLine([NSPoint(x: x, y: 674), NSPoint(x: x, y: 688)], color: color(0x66E5D0), width: 13)
    }
    for y in [CGFloat(513), 552, 591, 630] {
        strokeLine([NSPoint(x: 380, y: y), NSPoint(x: 394, y: y)], color: color(0x66E5D0), width: 13)
        strokeLine([NSPoint(x: 630, y: y), NSPoint(x: 644, y: y)], color: color(0x66E5D0), width: 13)
    }
    let core = rounded(464, 527, 96, 90, 20)
    NSGradient(colors: [color(0xA2F6E8), color(0x52D4C4)])!.draw(in: core, angle: 90)
    strokeLine([NSPoint(x: 481, y: 572), NSPoint(x: 497, y: 572),
                NSPoint(x: 507, y: 593), NSPoint(x: 519, y: 550),
                NSPoint(x: 530, y: 572), NSPoint(x: 545, y: 572)],
               color: color(0x16485B), width: 8)

    // An unmistakable signal trace at small icon sizes.
    strokeLine([NSPoint(x: 253, y: 374), NSPoint(x: 315, y: 374),
                NSPoint(x: 345, y: 414), NSPoint(x: 385, y: 342),
                NSPoint(x: 428, y: 389), NSPoint(x: 479, y: 360),
                NSPoint(x: 531, y: 397), NSPoint(x: 578, y: 375),
                NSPoint(x: 637, y: 375)], color: color(0x77F2DC), width: 18)
    let live = NSBezierPath(ovalIn: NSRect(x: 705, y: 349, width: 48, height: 48))
    color(0x8CF9DE).setFill()
    live.fill()
}

func writePNG(pixels: Int, path: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4,
                                        hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.imageInterpolation = .high
    context.shouldAntialias = true
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2)
    }
    try data.write(to: path, options: .atomic)
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: DrawIcon <iconset-directory>\n", stderr)
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let files: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
do {
    for (name, size) in files { try writePNG(pixels: size, path: directory.appendingPathComponent(name)) }
    print("Rendered \(files.count) icon assets from 16 to 1024 pixels")
} catch {
    fputs("Could not draw icon: \(error)\n", stderr)
    exit(1)
}
