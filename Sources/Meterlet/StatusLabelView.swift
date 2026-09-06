import AppKit
import MeterletCore

@MainActor
final class StatusLabelView: NSView {
    var rows: [(ProviderID, String)] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 48, height: 22) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let visible = rows.isEmpty ? [(ProviderID.codex, "—")] : rows
        for (index, row) in visible.prefix(2).enumerated() {
            let y: CGFloat = visible.count == 1 ? 5.5 : CGFloat(index) * 11
            let symbol = row.0 == .codex ? "terminal.fill" : "sun.max.fill"
            let color = row.0 == .codex ? NSColor(calibratedRed: 0.08, green: 0.49, blue: 0.53, alpha: 1)
                : NSColor(calibratedRed: 0.80, green: 0.39, blue: 0.27, alpha: 1)
            if row.0 == .codex {
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: 2, y: y + 1, width: 10, height: 9), xRadius: 2, yRadius: 2).fill()
                NSColor.white.setStroke()
                let mark = NSBezierPath()
                mark.lineWidth = 0.8
                mark.move(to: NSPoint(x: 4, y: y + 3))
                mark.line(to: NSPoint(x: 6, y: y + 5))
                mark.line(to: NSPoint(x: 4, y: y + 7))
                mark.move(to: NSPoint(x: 7, y: y + 7))
                mark.line(to: NSPoint(x: 10, y: y + 7))
                mark.stroke()
            } else if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .medium))?
                .withSymbolConfiguration(.init(paletteColors: [color])) {
                image.draw(in: NSRect(x: 2, y: y + 1, width: 9, height: 9), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let text = row.1 as NSString
            let width = text.size(withAttributes: attributes).width
            text.draw(at: NSPoint(x: 45 - width, y: y - 0.2), withAttributes: attributes)
        }
    }
}
