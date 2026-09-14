// Draws the Miracle Shot icon into an .iconset folder. Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit
import Foundation

// Mirrors BrandPalette in MiracleShotCore.
let ink = NSColor(srgbRed: 0x0b / 255, green: 0x0b / 255, blue: 0x0c / 255, alpha: 1)
let line = NSColor(srgbRed: 0x2a / 255, green: 0x2a / 255, blue: 0x2d / 255, alpha: 1)
let lime = NSColor(srgbRed: 0xd4 / 255, green: 0xff / 255, blue: 0x3f / 255, alpha: 1)
let bone = NSColor(srgbRed: 0xf3 / 255, green: 0xf0 / 255, blue: 0xe8 / 255, alpha: 1)

func draw(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                             xRadius: 185 * s, yRadius: 185 * s)
    ink.setFill(); plate.fill()
    line.setStroke(); plate.lineWidth = 6 * s; plate.stroke()

    let box = NSRect(x: 232 * s, y: 232 * s, width: 560 * s, height: 560 * s)
    let leg = 170 * s
    let brackets = NSBezierPath()
    brackets.lineWidth = 56 * s
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    for (corner, dx, dy) in [(NSPoint(x: box.minX, y: box.minY), 1.0, 1.0), (NSPoint(x: box.maxX, y: box.minY), -1.0, 1.0),
                             (NSPoint(x: box.minX, y: box.maxY), 1.0, -1.0), (NSPoint(x: box.maxX, y: box.maxY), -1.0, -1.0)] {
        brackets.move(to: NSPoint(x: corner.x, y: corner.y + leg * dy))
        brackets.line(to: corner)
        brackets.line(to: NSPoint(x: corner.x + leg * dx, y: corner.y))
    }
    lime.setStroke(); brackets.stroke()

    let dot = NSBezierPath(ovalIn: NSRect(x: 512 * s - 54 * s, y: 512 * s - 54 * s, width: 108 * s, height: 108 * s))
    bone.setFill(); dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try draw(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(out.path)")
