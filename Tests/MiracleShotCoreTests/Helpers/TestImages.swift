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

    /// Reads one pixel as straight (un-premultiplied) RGBA. `y` counts from the top, like screen coordinates.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = y   // CGBitmapContext buffers are top-down: row 0 is the top scanline
        let i = row * ctx.bytesPerRow + x * 4
        let a = data[i + 3]
        func straight(_ v: UInt8) -> UInt8 {
            a == 0 || a == 255 ? v : UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a)))
        }
        return RGBA(r: straight(data[i]), g: straight(data[i + 1]), b: straight(data[i + 2]), a: a)
    }

    /// One channel of every pixel as a top-down 2D array; far cheaper than calling `pixel` in a loop.
    /// `channel` 0...3 = R, G, B, A (premultiplied, fine for opaque images).
    static func channel(_ image: CGImage, _ channel: Int) -> [[UInt8]] {
        let ctx = context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<image.height).map { y in
            (0..<image.width).map { x in data[y * ctx.bytesPerRow + x * 4 + channel] }
        }
    }

    /// Top half `top`, bottom half `bottom`; used to prove orientation handling.
    static func splitHorizontally(width: Int, height: Int, top: RGBA, bottom: RGBA) -> CGImage {
        let ctx = context(width: width, height: height)
        func fill(_ c: RGBA, _ rect: CGRect) {
            ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, CGFloat(c.a) / 255])!)
            ctx.fill(rect)
        }
        // CG drawing coordinates have the origin at the bottom-left, so the top half is the upper rect.
        fill(bottom, CGRect(x: 0, y: 0, width: width, height: height / 2))
        fill(top, CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return ctx.makeImage()!
    }

    static func assertClose(_ p: RGBA, _ q: RGBA, tolerance: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        let ok = abs(Int(p.r) - Int(q.r)) <= tolerance && abs(Int(p.g) - Int(q.g)) <= tolerance
            && abs(Int(p.b) - Int(q.b)) <= tolerance && abs(Int(p.a) - Int(q.a)) <= tolerance
        if !ok { XCTFail("\(p) is not within \(tolerance) of \(q)", file: file, line: line) }
    }
}
