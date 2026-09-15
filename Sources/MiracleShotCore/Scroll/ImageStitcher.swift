import CoreGraphics
import Foundation

/// Result of stitching a sequence of vertically scrolled window frames into one long image.
public struct StitchResult: Sendable {
    public let image: CGImage
    /// True when some pair had no detectable overlap and was concatenated instead.
    public let usedFallback: Bool
    /// Rows of static header and footer that were kept once.
    public let headerRows: Int
    public let footerRows: Int
}

/// Stitches vertically scrolled window frames (RGBA8, premultipliedLast, sRGB) into one tall image, keeping a
/// static header/footer once. Pure CoreGraphics/Foundation, no dependency on any other Phase 3 utility: it reads
/// its own RGBA buffers from the frames it is given.
public enum ImageStitcher {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Static header/footer are each capped at this fraction of the (smaller) frame height in a pair.
    private static let maxStaticFraction = 0.4

    /// Stitches vertically scrolled frames of the same width. One frame returns itself.
    /// Steps: (1) static header/footer = leading/trailing rows identical (row difference <= `staticTolerance`)
    /// across all consecutive pairs, capped at 40 percent of the height each; (2) for each consecutive pair find
    /// the overlap `d` (rows) in `minOverlap...(dynamicHeight - 1)` such that the last `d` dynamic rows of A match
    /// the first `d` dynamic rows of B with mean absolute difference <= `matchTolerance` (per-row byte sums reject
    /// candidates cheaply, full comparison confirms; prefer the largest matching `d`); (3) append B's dynamic rows after
    /// `d`; (4) reattach the header at the top and the footer at the bottom. A pair without a match is appended
    /// whole and `usedFallback` becomes true. Frames whose dynamic part fully repeats the previous one are skipped.
    public static func stitch(_ frames: [CGImage], minOverlap: Int = 8, matchTolerance: Double = 6.0 / 255,
                              staticTolerance: Double = 2.0 / 255) -> StitchResult? {
        guard let first = frames.first, first.width > 0 else { return nil }
        let width = first.width
        guard frames.allSatisfy({ $0.width == width && $0.height > 0 }) else { return nil }

        if frames.count == 1 {
            return StitchResult(image: first, usedFallback: false, headerRows: 0, footerRows: 0)
        }

        var buffers: [FrameBuffer] = []
        buffers.reserveCapacity(frames.count)
        for frame in frames {
            guard let buffer = makeBuffer(frame) else { return nil }
            buffers.append(buffer)
        }

        let sums = buffers.map(rowSums)

        let (headerRows, footerRows) = staticEdges(buffers, tolerance: staticTolerance)

        var segments: [Segment] = []
        var usedFallback = false

        if headerRows > 0 { segments.append(Segment(bufferIndex: 0, rowStart: 0, rowCount: headerRows)) }

        var keptIndex = 0
        var keptDynStart = headerRows
        var keptDynEnd = buffers[0].height - footerRows
        segments.append(Segment(bufferIndex: 0, rowStart: keptDynStart, rowCount: max(0, keptDynEnd - keptDynStart)))

        for i in 1..<buffers.count {
            let buffer = buffers[i]
            let dynStart = headerRows
            let dynEnd = buffer.height - footerRows
            let dynHeight = max(0, dynEnd - dynStart)
            let keptBuffer = buffers[keptIndex]
            let keptDynHeight = max(0, keptDynEnd - keptDynStart)

            if dynHeight == keptDynHeight,
               bandDifference(keptBuffer, keptDynStart, buffer, dynStart, count: dynHeight) <= staticTolerance {
                continue // this frame's dynamic content fully repeats the last kept frame; skip it
            }

            let overlap = findOverlap(keptBuffer, keptDynEnd, sums[keptIndex],
                                      buffer, dynStart, sums[i],
                                      maxOverlap: min(keptDynHeight, dynHeight) - 1,
                                      minOverlap: minOverlap, width: width, matchTolerance: matchTolerance)

            if let d = overlap {
                let appendStart = dynStart + d
                let appendCount = dynEnd - appendStart
                if appendCount > 0 { segments.append(Segment(bufferIndex: i, rowStart: appendStart, rowCount: appendCount)) }
            } else {
                usedFallback = true
                if dynHeight > 0 { segments.append(Segment(bufferIndex: i, rowStart: dynStart, rowCount: dynHeight)) }
            }

            keptIndex = i
            keptDynStart = dynStart
            keptDynEnd = dynEnd
        }

        let lastBuffer = buffers[buffers.count - 1]
        if footerRows > 0 {
            segments.append(Segment(bufferIndex: buffers.count - 1, rowStart: lastBuffer.height - footerRows, rowCount: footerRows))
        }

        guard let image = buildOutput(width: width, segments: segments, buffers: buffers) else { return nil }
        return StitchResult(image: image, usedFallback: usedFallback, headerRows: headerRows, footerRows: footerRows)
    }

    // MARK: - Buffers

    private struct FrameBuffer {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bytes: [UInt8]
    }

    /// Draws `image` into an RGBA8 premultipliedLast sRGB context and copies its raw bytes. The context's raw
    /// buffer is top-down (row 0 is the top scanline), the same idiom `BackgroundRenderer` and the test helper
    /// `TestImages` rely on.
    private static func makeBuffer(_ image: CGImage) -> FrameBuffer? {
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = ctx.bytesPerRow
        // `data` is only valid while the context lives; keep it alive through the copy.
        let bytes = withExtendedLifetime(ctx) {
            [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
        }
        return FrameBuffer(width: width, height: height, bytesPerRow: bytesPerRow, bytes: bytes)
    }

    // MARK: - Row comparison

    /// Mean |delta| over RGB bytes (alpha ignored), normalized to 0...1.
    private static func rowDifference(_ a: FrameBuffer, _ rowA: Int, _ b: FrameBuffer, _ rowB: Int) -> Double {
        let width = min(a.width, b.width)
        guard width > 0 else { return 0 }
        var total = 0
        let baseA = rowA * a.bytesPerRow
        let baseB = rowB * b.bytesPerRow
        a.bytes.withUnsafeBufferPointer { pa in
            b.bytes.withUnsafeBufferPointer { pb in
                for x in 0..<width {
                    let ia = baseA + x * 4
                    let ib = baseB + x * 4
                    total += abs(Int(pa[ia]) - Int(pb[ib])) + abs(Int(pa[ia + 1]) - Int(pb[ib + 1])) + abs(Int(pa[ia + 2]) - Int(pb[ib + 2]))
                }
            }
        }
        return Double(total) / Double(width * 3) / 255
    }

    /// Mean row difference over `count` consecutive rows starting at `rowA0`/`rowB0`.
    private static func bandDifference(_ a: FrameBuffer, _ rowA0: Int, _ b: FrameBuffer, _ rowB0: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        var total = 0.0
        for k in 0..<count { total += rowDifference(a, rowA0 + k, b, rowB0 + k) }
        return total / Double(count)
    }

    // MARK: - Static header/footer

    /// Largest `h` (<= 40 percent of the smaller frame's height) such that, for every consecutive pair, rows
    /// `0..<h` match within `tolerance`; footer likewise counted from the bottom. Computed per pair, then the
    /// minimum across all pairs is kept.
    private static func staticEdges(_ buffers: [FrameBuffer], tolerance: Double) -> (header: Int, footer: Int) {
        var header = Int.max
        var footer = Int.max
        for i in 0..<(buffers.count - 1) {
            let a = buffers[i], b = buffers[i + 1]
            let cap = Int(Double(min(a.height, b.height)) * maxStaticFraction)

            var h = 0
            while h < cap, rowDifference(a, h, b, h) <= tolerance { h += 1 }
            header = min(header, h)

            var f = 0
            while f < cap, rowDifference(a, a.height - 1 - f, b, b.height - 1 - f) <= tolerance { f += 1 }
            footer = min(footer, f)
        }
        return (max(0, header), max(0, footer))
    }

    // MARK: - Overlap search

    /// Sum of every RGB byte in each row. |sum(a) - sum(b)| <= sum(|a - b|), so the difference of two row sums
    /// is a lower bound on the row's total absolute difference and can reject a candidate without touching pixels.
    private static func rowSums(_ buffer: FrameBuffer) -> [Int] {
        (0..<buffer.height).map { row -> Int in
            let base = row * buffer.bytesPerRow
            var sum = 0
            buffer.bytes.withUnsafeBufferPointer { bytes in
                for x in 0..<buffer.width {
                    let i = base + x * 4
                    sum += Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])
                }
            }
            return sum
        }
    }

    /// Finds the largest `d` in `minOverlap...maxOverlap` such that the last `d` rows of A's dynamic band
    /// (ending at `tailEnd`) match the first `d` rows of B's dynamic band (starting at `headStart`).
    private static func findOverlap(_ a: FrameBuffer, _ tailEnd: Int, _ sumsA: [Int],
                                    _ b: FrameBuffer, _ headStart: Int, _ sumsB: [Int],
                                    maxOverlap: Int, minOverlap: Int, width: Int, matchTolerance: Double) -> Int? {
        guard maxOverlap >= minOverlap else { return nil }
        // `rowDifference` of a row, scaled back to summed bytes.
        let rowSumThreshold = matchTolerance * 255 * Double(width * 3)

        for d in stride(from: maxOverlap, through: minOverlap, by: -1) {
            let tailStart = tailEnd - d
            if quickReject(sumsA, tailStart, sumsB, headStart, d, rowThreshold: rowSumThreshold) { continue }
            if confirms(a, tailStart, b, headStart, d, tolerance: matchTolerance) { return d }
        }
        return nil
    }

    /// Mirrors `confirms` on the row-sum lower bound: rejects only when some prefix of the band already has a
    /// mean summed-byte difference above the threshold, which means its true mean difference is above the
    /// tolerance too and `confirms` would exit at the same row. A single noisy row (a cursor, a spinner) inside
    /// an otherwise matching band therefore never rejects on its own.
    private static func quickReject(_ sumsA: [Int], _ tailStart: Int, _ sumsB: [Int], _ headStart: Int,
                                    _ d: Int, rowThreshold: Double) -> Bool {
        var runningTotal = 0
        for k in 0..<d {
            runningTotal += abs(sumsA[tailStart + k] - sumsB[headStart + k])
            if Double(runningTotal) > rowThreshold * Double(k + 1) { return true }
        }
        return false
    }

    /// Full row-by-row mean absolute difference over the `d`-row band, with an early exit as soon as the
    /// running mean exceeds `tolerance`.
    private static func confirms(_ a: FrameBuffer, _ tailStart: Int, _ b: FrameBuffer, _ headStart: Int,
                                 _ d: Int, tolerance: Double) -> Bool {
        guard d > 0 else { return true }
        var runningTotal = 0.0
        for k in 0..<d {
            runningTotal += rowDifference(a, tailStart + k, b, headStart + k)
            if runningTotal / Double(k + 1) > tolerance { return false }
        }
        return true
    }

    // MARK: - Output assembly

    private struct Segment { let bufferIndex: Int; let rowStart: Int; let rowCount: Int }

    private static func buildOutput(width: Int, segments: [Segment], buffers: [FrameBuffer]) -> CGImage? {
        let totalHeight = segments.reduce(0) { $0 + $1.rowCount }
        guard totalHeight > 0,
              let ctx = CGContext(data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dest = ctx.data else { return nil }
        let destBytesPerRow = ctx.bytesPerRow
        let copyWidth = min(destBytesPerRow, width * 4)
        var destRow = 0
        for segment in segments {
            guard segment.rowCount > 0 else { continue }
            let buffer = buffers[segment.bufferIndex]
            buffer.bytes.withUnsafeBufferPointer { src in
                for r in 0..<segment.rowCount {
                    let srcBase = (segment.rowStart + r) * buffer.bytesPerRow
                    let dstBase = destRow * destBytesPerRow
                    memcpy(dest + dstBase, src.baseAddress! + srcBase, copyWidth)
                    destRow += 1
                }
            }
        }
        return ctx.makeImage()
    }
}
