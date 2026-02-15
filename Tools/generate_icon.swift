import AppKit
import Foundation

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
}

func drawTemplateImage(_ image: NSImage, in rect: NSRect, tint: NSColor, alpha: CGFloat = 1.0) {
    NSGraphicsContext.saveGraphicsState()
    image.draw(in: rect, from: NSRect.zero, operation: NSCompositingOperation.sourceOver, fraction: alpha)
    tint.setFill()
    NSGraphicsContext.current?.compositingOperation = NSCompositingOperation.sourceAtop
    NSBezierPath(rect: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let outPath: String
if CommandLine.arguments.count >= 2 {
    outPath = CommandLine.arguments[1]
} else {
    die("Usage: swift generate_icon.swift /path/to/icon.png")
}

let size = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    die("Failed to create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: rounded square with subtle diagonal gradient.
let bgPath = NSBezierPath(roundedRect: rect, xRadius: 230, yRadius: 230)

let bgGradient = NSGradient(colors: [
    color(0x1C1D20),
    color(0x101114)
])!

bgGradient.draw(in: bgPath, angle: 135)

// Subtle highlight (top-left).
let highlight = NSBezierPath(ovalIn: NSRect(x: -120, y: 420, width: 720, height: 720))
color(0xFFFFFF, alpha: 0.06).setFill()
highlight.fill()

// Subtle vignette.
let vignette = NSBezierPath(roundedRect: rect, xRadius: 230, yRadius: 230)
let vignetteGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.0, alpha: 0.0),
    NSColor(calibratedWhite: 0.0, alpha: 0.22)
])!
vignetteGradient.draw(in: vignette, relativeCenterPosition: NSPoint(x: 0.5, y: 0.55))

// Thermometer symbol.
if let symbolBase = NSImage(systemSymbolName: "thermometer", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
    let symbol = symbolBase.withSymbolConfiguration(config) ?? symbolBase

    let symbolRect = NSRect(x: 232, y: 220, width: 560, height: 600)

    // Warm accent layer (slight offset).
    drawTemplateImage(symbol, in: symbolRect.offsetBy(dx: 0, dy: -18), tint: NSColor.systemOrange.withAlphaComponent(0.35))

    // Main layer.
    drawTemplateImage(symbol, in: symbolRect, tint: NSColor.white.withAlphaComponent(0.92))
} else {
    // Fallback: simple "°" mark.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 520, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        .paragraphStyle: paragraph
    ]

    let s = "°" as NSString
    let sRect = NSRect(x: 0, y: 280, width: size, height: 520)
    s.draw(in: sRect, withAttributes: attrs)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    die("Failed to encode PNG")
}

do {
    try png.write(to: URL(fileURLWithPath: outPath), options: .atomic)
} catch {
    die("Failed to write PNG: \(error)")
}
