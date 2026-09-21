import AppKit
import XCTest
@testable import MiracleShotUI

final class StatusBarIconTests: XCTestCase {
    /// The menu bar item carries the app icon in brand color, not a tinted template glyph.
    @MainActor
    func testStatusBarIconIsTheColoredLogo() {
        let image = StatusBarIcon.make()
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertFalse(image.isTemplate)

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        // The dot in the middle is bone; the brackets around it are lime.
        let center = rep.colorAt(x: 18, y: 18)!.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(center.redComponent, 0.85)
        XCTAssertGreaterThan(center.greenComponent, 0.85)
        XCTAssertGreaterThan(center.blueComponent, 0.8)

        var lime = 0
        for x in 0..<36 {
            for y in 0..<36 {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if c.alphaComponent > 0.9, c.greenComponent > 0.85, c.blueComponent < 0.5 { lime += 1 }
            }
        }
        XCTAssertGreaterThan(lime, 20)
    }
}
