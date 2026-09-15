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
    /// Row signatures are quick-rejected on this many evenly spaced samples within the overlap band.
    private static let quickRejectSamples = 4

    /// Stitches vertically scrolled frames of the same width. One frame returns itself.
    /// Steps: (1) static header/footer = leading/trailing rows identical (row difference <= `staticTolerance`)
    /// across all consecutive pairs, capped at 40 percent of the height each; (2) for each consecutive pair find
    /// the overlap `d` (rows) in `minOverlap...(dynamicHeight - 1)` such that the last `d` dynamic rows of A match
    /// the first `d` dynamic rows of B with mean absolute difference <= `matchTolerance` (row signatures narrow the
    /// candidates, full comparison confirms; prefer the largest matching `d`); (3) append B's dynamic rows after
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

        let signatures = buffers.map(rowSignatures)

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

            let overlap = findOverlap(keptBuffer, keptDynEnd, signatures[keptIndex],
                                      buffer, dynStart, signatures[i],
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
        let bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytesPerRow * height))
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

    private struct RowSignature { let hash: UInt64; let sum: UInt32 }

    /// Per-row signature: a 64-bit hash over every 8th pixel's RGB (cheap structural fingerprint) and the sum of
    /// every RGB byte in the row (used as a safe lower-bound proxy for the row's total absolute difference).
    private static func rowSignatures(_ buffer: FrameBuffer) -> [RowSignature] {
        (0..<buffer.height).map { row -> RowSignature in
            let base = row * buffer.bytesPerRow
            var hash: UInt64 = 14_695_981_039_346_656_37
            var sum: UInt32 = 0
            buffer.bytes.withUnsafeBufferPointer { bytes in
                var x = 0
                while x < buffer.width {
                    let i = base + x * 4
                    hash = (hash ^ UInt64(bytes[i])) &* 1_099_511_628_211
                    hash = (hash ^ UInt64(bytes[i + 1])) &* 1_099_511_628_211
                    hash = (hash ^ UInt64(bytes[i + 2])) &* 1_099_511_628_211
                    x += 8
                }
                for x in 0..<buffer.width {
                    let i = base + x * 4
                    sum &+= UInt32(bytes[i]) &+ UInt32(bytes[i + 1]) &+ UInt32(bytes[i + 2])
                }
            }
            return RowSignature(hash: hash, sum: sum)
        }
    }

    /// Finds the largest `d` in `minOverlap...maxOverlap` such that the last `d` rows of A's dynamic band
    /// (ending at `tailEnd`) match the first `d` rows of B's dynamic band (starting at `headStart`).
    private static func findOverlap(_ a: FrameBuffer, _ tailEnd: Int, _ sigsA: [RowSignature],
                                    _ b: FrameBuffer, _ headStart: Int, _ sigsB: [RowSignature],
                                    maxOverlap: Int, minOverlap: Int, width: Int, matchTolerance: Double) -> Int? {
        guard maxOverlap >= minOverlap else { return nil }
        // A safe lower bound: if a sampled row's summed-byte difference already exceeds this, that row alone
        // has a mean absolute difference above `matchTolerance` (|sum(a-b)| <= sum(|a-b|)), so the band cannot
        // possibly confirm; skip the expensive full comparison.
        let rowSumThreshold = matchTolerance * 255 * Double(width * 3)

        for d in stride(from: maxOverlap, through: minOverlap, by: -1) {
            let tailStart = tailEnd - d
            if quickReject(sigsA, tailStart, sigsB, headStart, d, threshold: rowSumThreshold) { continue }
            if confirms(a, tailStart, b, headStart, d, tolerance: matchTolerance) { return d }
        }
        return nil
    }

    private static func quickReject(_ sigsA: [RowSignature], _ tailStart: Int, _ sigsB: [RowSignature], _ headStart: Int,
                                    _ d: Int, threshold: Double) -> Bool {
        let sampleCount = min(quickRejectSamples, d)
        guard sampleCount > 0 else { return false }
        let step = max(1, d / sampleCount)
        var k = 0
        while k < d {
            let sigA = sigsA[tailStart + k]
            let sigB = sigsB[headStart + k]
            if Double(abs(Int64(sigA.sum) - Int64(sigB.sum))) > threshold { return true }
            k += step
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
