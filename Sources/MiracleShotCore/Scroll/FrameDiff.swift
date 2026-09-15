import CoreGraphics
import Foundation

/// Normalized frame comparison for scrolling capture: `maxBandDifference` decides whether a scroll animation
/// has settled, `difference` whether two consecutive settled frames are the same page (end of content);
/// `rowDifferences` locates the static header/footer bands the stitcher must not duplicate.
public enum FrameDiff {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Below this (per band, see `maxBandDifference`) the content is considered still: scroll and reveal
    /// animations finished.
    public static let settledThreshold = 0.004
    /// Below this two consecutive settled frames are considered the same page (end of content).
    public static let samePageThreshold = 0.002

    /// Mean absolute difference over a `grid x grid` sample of pixels (RGB, ignoring alpha), normalized to
    /// 0...1. Images of different sizes return 1. Sampling makes a 5K frame comparison cost a few thousand reads.
    public static func difference(_ a: CGImage, _ b: CGImage, grid: Int = 48) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        guard grid > 0 else { return 0 }
        guard let contextA = drawn(a), let contextB = drawn(b),
              let dataA = contextA.data, let dataB = contextB.data else { return 1 }
        let pixelsA = dataA.assumingMemoryBound(to: UInt8.self)
        let pixelsB = dataB.assumingMemoryBound(to: UInt8.self)
        let rowBytesA = contextA.bytesPerRow
        let rowBytesB = contextB.bytesPerRow
        let width = a.width
        let height = a.height
        let denomX = max(grid - 1, 1)
        let denomY = max(grid - 1, 1)

        // The contexts own the buffers behind `pixelsA`/`pixelsB`; ARC may otherwise release them before the loop ends.
        return withExtendedLifetime((contextA, contextB)) {
            var total = 0.0
            var count = 0
            for gy in 0..<grid {
                let y = gy * (height - 1) / denomY
                for gx in 0..<grid {
                    let x = gx * (width - 1) / denomX
                    total += sampleDifference(pixelsA, rowBytesA, pixelsB, rowBytesB, x: x, y: y)
                    count += 1
                }
            }
            return count > 0 ? total / Double(count) : 0
        }
    }

    /// The largest per-band mean difference over `bands` horizontal strips of a `grid x grid` sample (RGB,
    /// ignoring alpha), normalized to 0...1. Unlike `difference`, a section that is still fading or sliding in
    /// after a scroll is not averaged away by the rest of a tall, unchanged frame. Different sizes return 1.
    public static func maxBandDifference(_ a: CGImage, _ b: CGImage, bands: Int, grid: Int = 96) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        guard grid > 0, bands > 0 else { return 0 }
        guard let contextA = drawn(a), let contextB = drawn(b),
              let dataA = contextA.data, let dataB = contextB.data else { return 1 }
        let pixelsA = dataA.assumingMemoryBound(to: UInt8.self)
        let pixelsB = dataB.assumingMemoryBound(to: UInt8.self)
        let rowBytesA = contextA.bytesPerRow
        let rowBytesB = contextB.bytesPerRow
        let width = a.width
        let height = a.height
        let denomX = max(grid - 1, 1)
        let denomY = max(grid - 1, 1)

        return withExtendedLifetime((contextA, contextB)) {
            var totals = Array(repeating: 0.0, count: bands)
            var counts = Array(repeating: 0, count: bands)
            for gy in 0..<grid {
                let y = gy * (height - 1) / denomY
                let band = min(gy * bands / grid, bands - 1)
                for gx in 0..<grid {
                    let x = gx * (width - 1) / denomX
                    totals[band] += sampleDifference(pixelsA, rowBytesA, pixelsB, rowBytesB, x: x, y: y)
                    counts[band] += 1
                }
            }
            var worst = 0.0
            for band in 0..<bands where counts[band] > 0 {
                worst = max(worst, totals[band] / Double(counts[band]))
            }
            return worst
        }
    }

    /// Row-wise difference: for `rowCount` evenly spaced rows, the mean absolute RGB difference across every
    /// `max(1, width / 64)`-th pixel of that row (subsampled for speed), normalized to 0...1. Different sizes
    /// return `rowCount` values of 1. Used by the stitcher's static-region detection.
    public static func rowDifferences(_ a: CGImage, _ b: CGImage, rowCount: Int) -> [Double] {
        guard rowCount > 0 else { return [] }
        guard a.width == b.width, a.height == b.height else { return Array(repeating: 1, count: rowCount) }
        guard let contextA = drawn(a), let contextB = drawn(b),
              let dataA = contextA.data, let dataB = contextB.data else { return Array(repeating: 1, count: rowCount) }
        let pixelsA = dataA.assumingMemoryBound(to: UInt8.self)
        let pixelsB = dataB.assumingMemoryBound(to: UInt8.self)
        let rowBytesA = contextA.bytesPerRow
        let rowBytesB = contextB.bytesPerRow
        let width = a.width
        let height = a.height
        let stride = max(1, width / 64)
        let denomRow = max(rowCount - 1, 1)

        return withExtendedLifetime((contextA, contextB)) {
            var result: [Double] = []
            result.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                let y = r * (height - 1) / denomRow
                var total = 0.0
                var count = 0
                var x = 0
                while x < width {
                    total += sampleDifference(pixelsA, rowBytesA, pixelsB, rowBytesB, x: x, y: y)
                    count += 1
                    x += stride
                }
                result.append(count > 0 ? total / Double(count) : 0)
            }
            return result
        }
    }

    /// Mean of |dR|, |dG|, |dB| at one pixel, normalized to 0...1. Alpha is ignored; both buffers are
    /// premultipliedLast, matching for opaque capture frames.
    private static func sampleDifference(_ pixelsA: UnsafePointer<UInt8>, _ rowBytesA: Int,
                                         _ pixelsB: UnsafePointer<UInt8>, _ rowBytesB: Int, x: Int, y: Int) -> Double {
        let offsetA = y * rowBytesA + x * 4
        let offsetB = y * rowBytesB + x * 4
        let dr = abs(Int(pixelsA[offsetA]) - Int(pixelsB[offsetB]))
        let dg = abs(Int(pixelsA[offsetA + 1]) - Int(pixelsB[offsetB + 1]))
        let db = abs(Int(pixelsA[offsetA + 2]) - Int(pixelsB[offsetB + 2]))
        return Double(dr + dg + db) / 3 / 255
    }

    /// Draws `image` once into an 8-bit sRGB premultipliedLast context of its own size; the context (and its
    /// backing buffer) is kept alive by the caller for as long as the returned data pointer is read.
    private static func drawn(_ image: CGImage) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx
    }
}
