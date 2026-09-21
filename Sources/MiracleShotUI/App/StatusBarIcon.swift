import AppKit
import MiracleShotCore

/// The app icon at menu bar size: the same plate, brackets and dot that
/// scripts/make-icon.swift draws for AppIcon.icns, so the repo keeps no bitmap.
/// Deliberately not a template image: the item is the logo, in brand color,
/// rather than a system glyph that the bar tints.
enum StatusBarIcon {
    static let size: CGFloat = 18

    @MainActor
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // Proportions follow the 1024 pt icon: box at 68 percent of the plate, legs at 30 percent of the box.
    // Strokes are thicker than a straight scale-down so the mark still reads at 18 pt.
    private static func draw(in rect: NSRect) {
        let plateRect = rect.insetBy(dx: 1, dy: 1)
        let plate = NSBezierPath(roundedRect: plateRect, xRadius: 3.5, yRadius: 3.5)
        color(BrandPalette.ink).setFill(); plate.fill()
        let edge = NSBezierPath(roundedRect: plateRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        edge.lineWidth = 1
        color(BrandPalette.line).setStroke(); edge.stroke()

        let box = plateRect.insetBy(dx: 3, dy: 3)
        let leg: CGFloat = 3
        let brackets = NSBezierPath()
        brackets.lineWidth = 1.5
        brackets.lineCapStyle = .round
        brackets.lineJoinStyle = .round
        for (corner, dx, dy) in [(NSPoint(x: box.minX, y: box.minY), 1.0, 1.0), (NSPoint(x: box.maxX, y: box.minY), -1.0, 1.0),
                                 (NSPoint(x: box.minX, y: box.maxY), 1.0, -1.0), (NSPoint(x: box.maxX, y: box.maxY), -1.0, -1.0)] {
            brackets.move(to: NSPoint(x: corner.x, y: corner.y + leg * dy))
            brackets.line(to: corner)
            brackets.line(to: NSPoint(x: corner.x + leg * dx, y: corner.y))
        }
        color(BrandPalette.lime).setStroke(); brackets.stroke()

        let dot = NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.25, y: rect.midY - 1.25, width: 2.5, height: 2.5))
        color(BrandPalette.bone).setFill(); dot.fill()
    }

    private static func color(_ c: BrandColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
}
