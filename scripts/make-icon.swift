import AppKit

// Original geometric artwork. Regenerate with: swift scripts/make-icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon() {
    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200).fill()
    let colors = [NSColor(calibratedRed: 0.30, green: 0.82, blue: 0.79, alpha: 1),
                  NSColor(calibratedRed: 0.95, green: 0.58, blue: 0.41, alpha: 1)]
    for index in 0..<2 {
        let y = CGFloat(index == 0 ? 566 : 322)
        colors[index].setFill()
        NSBezierPath(roundedRect: NSRect(x: 194, y: y + 9, width: 92, height: 92), xRadius: 25, yRadius: 25).fill()
        NSColor.white.withAlphaComponent(0.12).setFill()
        let track = NSRect(x: 338, y: y + 26, width: 478, height: 58)
        NSBezierPath(roundedRect: track, xRadius: 29, yRadius: 29).fill()
        colors[index].setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: index == 0 ? 220 : 334, height: track.height), xRadius: 29, yRadius: 29).fill()
    }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
