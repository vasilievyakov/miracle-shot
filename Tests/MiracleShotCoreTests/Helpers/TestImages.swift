import CoreGraphics
import Foundation
import XCTest

enum TestImages {
    struct RGBA: Equatable { var r: UInt8; var g: UInt8; var b: UInt8; var a: UInt8 }

    /// Solid-color image, premultiplied RGBA8, sRGB.
    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Reads one pixel. `y` counts from the top, like screen coordinates.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = image.height - 1 - y   // CGContext bitmaps are bottom-up
        let i = row * ctx.bytesPerRow + x * 4
        return RGBA(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
    }

    static func assertClose(_ p: RGBA, _ q: RGBA, tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        let ok = abs(Int(p.r) - Int(q.r)) <= tolerance && abs(Int(p.g) - Int(q.g)) <= tolerance
            && abs(Int(p.b) - Int(q.b)) <= tolerance && abs(Int(p.a) - Int(q.a)) <= tolerance
        if !ok { XCTFail("\(p) is not within \(tolerance) of \(q)", file: file, line: line) }
    }
}
