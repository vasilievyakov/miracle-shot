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
    /// across all consecutive pairs, capped at 40 percent of the height each; (2) each new frame is matched
    /// against the page collected so far: an overlap `d` (rows) in `minOverlap...(dynamicHeight - 1)` where the
    /// last `d` dynamic rows of the page's bottom frame match the first `d` rows of the new frame with mean
    /// absolute difference <= `matchTolerance` (per-row byte sums reject candidates cheaply, full comparison
    /// confirms; prefer the largest matching `d`) appends the rows after `d`; the mirrored overlap against the
    /// page's top frame (the user scrolled up) prepends the rows before it; (3) the header goes back on top and
    /// the footer at the bottom. A frame that repeats the top or bottom frame, or overlaps them the "wrong" way
    /// round (scrolled back into collected content), is skipped; one that matches nothing is appended whole and
    /// `usedFallback` becomes true.
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

        var usedFallback = false
        let dynStart = headerRows
        func dynEnd(_ index: Int) -> Int { buffers[index].height - footerRows }
        func dynHeight(_ index: Int) -> Int { max(0, dynEnd(index) - dynStart) }

        // Dynamic rows of the page in order; `top` and `bottom` are the frames at its ends.
        var body: [Segment] = [Segment(bufferIndex: 0, rowStart: dynStart, rowCount: dynHeight(0))]
        var top = 0
        var bottom = 0

        func repeats(_ index: Int, _ kept: Int) -> Bool {
            dynHeight(index) == dynHeight(kept)
                && bandDifference(buffers[kept], dynStart, buffers[index], dynStart, count: dynHeight(index)) <= staticTolerance
        }
        // Rows of `kept`'s tail matching `index`'s head: `index` continues the page downwards after `kept`.
        func overlapBelow(_ kept: Int, _ index: Int) -> Int? {
            findOverlap(buffers[kept], dynEnd(kept), sums[kept], buffers[index], dynStart, sums[index],
                        maxOverlap: min(dynHeight(kept), dynHeight(index)) - 1,
                        minOverlap: minOverlap, width: width, matchTolerance: matchTolerance)
        }
        // Rows of `index`'s tail matching `kept`'s head: `index` continues the page upwards before `kept`.
        func overlapAbove(_ kept: Int, _ index: Int) -> Int? {
            findOverlap(buffers[index], dynEnd(index), sums[index], buffers[kept], dynStart, sums[kept],
                        maxOverlap: min(dynHeight(kept), dynHeight(index)) - 1,
                        minOverlap: minOverlap, width: width, matchTolerance: matchTolerance)
        }

        for i in 1..<buffers.count {
            if repeats(i, bottom) || repeats(i, top) { continue }

            if let d = overlapBelow(bottom, i) {
                let count = dynEnd(i) - (dynStart + d)
                if count > 0 { body.append(Segment(bufferIndex: i, rowStart: dynStart + d, rowCount: count)) }
                bottom = i
            } else if let d = overlapAbove(top, i) {
                let count = dynHeight(i) - d
                if count > 0 { body.insert(Segment(bufferIndex: i, rowStart: dynStart, rowCount: count), at: 0) }
                top = i
            } else if top != bottom, overlapAbove(bottom, i) != nil || overlapBelow(top, i) != nil {
                continue // scrolled back into content the page already has
            } else {
                usedFallback = true
                if dynHeight(i) > 0 { body.append(Segment(bufferIndex: i, rowStart: dynStart, rowCount: dynHeight(i))) }
                bottom = i
            }
        }

        var segments: [Segment] = []
        if headerRows > 0 { segments.append(Segment(bufferIndex: top, rowStart: 0, rowCount: headerRows)) }
        segments += body
        if footerRows > 0 {
            segments.append(Segment(bufferIndex: bottom, rowStart: buffers[bottom].height - footerRows, rowCount: footerRows))
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

    /// Mirrors `confirms` on the row-sum lower bound: rejects once the summed-byte differences seen so far
    /// already exceed what the whole band may total, which means the true mean is above the tolerance too. A
    /// few noisy rows anywhere in the band (a cursor, a hover highlight, a "jump to bottom" pill) never reject
    /// on their own.
    private static func quickReject(_ sumsA: [Int], _ tailStart: Int, _ sumsB: [Int], _ headStart: Int,
                                    _ d: Int, rowThreshold: Double) -> Bool {
        let budget = rowThreshold * Double(d)
        var runningTotal = 0
        for k in 0..<d {
            runningTotal += abs(sumsA[tailStart + k] - sumsB[headStart + k])
            if Double(runningTotal) > budget { return true }
        }
        return false
    }

    /// Full row-by-row mean absolute difference over the `d`-row band, with an early exit as soon as the rows
    /// seen so far already exceed the band's total budget (`tolerance * d`).
    private static func confirms(_ a: FrameBuffer, _ tailStart: Int, _ b: FrameBuffer, _ headStart: Int,
                                 _ d: Int, tolerance: Double) -> Bool {
        guard d > 0 else { return true }
        let budget = tolerance * Double(d)
        var runningTotal = 0.0
        for k in 0..<d {
            runningTotal += rowDifference(a, tailStart + k, b, headStart + k)
            if runningTotal > budget { return false }
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
