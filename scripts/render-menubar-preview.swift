import AppKit
import MeterletCore

/// A documentation sample using the app's actual status-item drawing, at its actual 48 pt width.
/// Compile with Sources/Meterlet/StatusLabelView.swift and MeterletCore after a normal build.
@MainActor
final class MenuBarSample: NSView {
    private let label = StatusLabelView(frame: NSRect(x: 105, y: 5, width: 48, height: 22))
    private let dark: Bool
    override var isFlipped: Bool { true }

    init(dark: Bool) {
        self.dark = dark
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 74))
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        label.rows = [(.codex, "28%"), (.claude, "55%")]
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: dark ? 0.13 : 0.89, green: dark ? 0.19 : 0.93,
                blue: dark ? 0.23 : 0.96, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: dark ? 0.16 : 0.97, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 32).fill()
        NSColor(calibratedWhite: dark ? 1 : 0, alpha: 0.09).setFill()
        NSRect(x: 0, y: 31.5, width: bounds.width, height: 0.5).fill()
        let ink = NSColor(calibratedWhite: dark ? 0.96 : 0.10, alpha: 1)
        for (name, x, width) in [("wifi", 173.0, 18.0), ("battery.100percent", 207.0, 25.0)] {
            let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))?
                .withSymbolConfiguration(.init(paletteColors: [ink]))
            icon?.draw(in: NSRect(x: x, y: 9, width: width, height: 14), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        ("Sun 9:41" as NSString).draw(at: NSPoint(x: 257, y: 9), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: ink,
        ])
    }
}

@main
struct RenderMenuBarPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let view = MenuBarSample(dark: dark)
            let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = view.appearance
            view.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 148,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CocoaError(.fileWriteUnknown) }
            bitmap.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            let destination = directory.appendingPathComponent("menubar-\(dark ? "dark" : "light").png")
            try data.write(to: destination)
            print(destination.path)
        }
    }
}
