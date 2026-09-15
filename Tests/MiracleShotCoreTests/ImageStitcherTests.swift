import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class ImageStitcherTests: XCTestCase {

    // MARK: - Synthetic scrolling page

    /// Deterministic hash noise, so two calls with the same coordinates and salt always agree but no two rows
    /// of a rendered image repeat -- an overlap match is unambiguous.
    private enum Noise {
        static func byte(_ x: Int, _ y: Int, _ salt: Int) -> UInt8 {
            var h = UInt64(bitPattern: Int64(x)) &* 73_856_093
            h ^= UInt64(bitPattern: Int64(y)) &* 19_349_663
            h ^= UInt64(bitPattern: Int64(salt)) &* 83_492_791
            h = h &* 2_654_435_761
            h ^= h >> 15
            return UInt8(truncatingIfNeeded: h)
        }

        static func color(x: Int, y: Int, salt: Int) -> (UInt8, UInt8, UInt8) {
            (byte(x, y, salt), byte(x, y, salt + 1), byte(x, y, salt + 2))
        }
    }

    /// A tall synthetic "page": per-pixel hash noise plus horizontal bands of text-like rectangles, so it is
    /// not periodic and every row is unique -- the overlap search below has exactly one right answer.
    private enum Page {
        static let width = 300
        static let height = 1400
        static let headerHeight = 40
        static let footerHeight = 30
        /// Height of the scrolling (dynamic) window each frame captures, excluding header/footer.
        static let frameHeight = 400
        static let step = 300

        static func color(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            var (r, g, b) = Noise.color(x: x, y: y, salt: 0xA1)
            let lineRow = y % 24
            if lineRow < 10 {
                let block = ((x / 18) + (y / 24) * 7) % 5
                if block < 2 { r = 20; g = 20; b = 20 } // a "text" pixel
            }
            return (r, g, b)
        }

        /// Frame start offsets into the page: steps of `step`, with the last one snapped so the page's bottom
        /// row is covered exactly once (mirrors a real scroll capture settling at the end of content).
        static func frameStarts() -> [Int] {
            var starts: [Int] = []
            var start = 0
            while start + frameHeight < height {
                starts.append(start)
                start += step
            }
            starts.append(height - frameHeight)
            return starts
        }
    }

    private func render(width: Int, rows: Range<Int>, colorAt: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        let ctx = TestImages.context(width: width, height: rows.count)
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = ctx.bytesPerRow
        for (localRow, y) in rows.enumerated() {
            for x in 0..<width {
                let (r, g, b) = colorAt(x, y)
                let i = localRow * bytesPerRow + x * 4
                data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    /// Stacks images top to bottom (first argument on top) into one image of their combined height.
    private func stack(width: Int, pieces: [CGImage]) -> CGImage {
        let totalHeight = pieces.reduce(0) { $0 + $1.height }
        let ctx = TestImages.context(width: width, height: totalHeight)
        var consumedFromTop = 0
        for piece in pieces {
            // CG drawing coordinates are bottom-left origin; a piece meant for top-down rows
            // [consumedFromTop, consumedFromTop + piece.height) sits at this y from the bottom.
            let y = totalHeight - consumedFromTop - piece.height
            ctx.draw(piece, in: CGRect(x: 0, y: y, width: width, height: piece.height))
            consumedFromTop += piece.height
        }
        return ctx.makeImage()!
    }

    /// Cuts the page into overlapping frames, each `header + page window + footer`, the way a real scrolling
    /// capture would look: the header and footer are the exact same image drawn into every frame (byte-identical
    /// across frames), only the page window slides.
    private func makeScrollFrames() -> (frames: [CGImage], page: CGImage) {
        let page = render(width: Page.width, rows: 0..<Page.height, colorAt: Page.color)
        let header = render(width: Page.width, rows: 0..<Page.headerHeight) { Noise.color(x: $0, y: $1, salt: 0xD4) }
        let footer = render(width: Page.width, rows: 0..<Page.footerHeight) { Noise.color(x: $0, y: $1, salt: 0xE5) }
        let frames = Page.frameStarts().map { start -> CGImage in
            let window = page.cropping(to: CGRect(x: 0, y: start, width: Page.width, height: Page.frameHeight))!
            return stack(width: Page.width, pieces: [header, window, footer])
        }
        return (frames, page)
    }

    // MARK: - Tests

    func testStitchesFramesBackIntoThePage() throws {
        let (frames, page) = makeScrollFrames()
        let result = try XCTUnwrap(ImageStitcher.stitch(frames))

        XCTAssertEqual(result.image.width, Page.width)
        XCTAssertEqual(result.image.height, Page.headerHeight + Page.height + Page.footerHeight)
        XCTAssertFalse(result.usedFallback)

        for pageRow in stride(from: 0, to: Page.height, by: 50) {
            let outputRow = Page.headerHeight + pageRow
            TestImages.assertClose(TestImages.pixel(result.image, x: Page.width / 2, y: outputRow),
                                   TestImages.pixel(page, x: Page.width / 2, y: pageRow), tolerance: 2)
        }
    }

    func testKeepsHeaderAndFooterOnce() throws {
        let (frames, _) = makeScrollFrames()
        let result = try XCTUnwrap(ImageStitcher.stitch(frames))

        XCTAssertEqual(result.headerRows, Page.headerHeight)
        XCTAssertEqual(result.footerRows, Page.footerHeight)
    }

    func testSkipsRepeatedLastFrame() throws {
        let (frames, _) = makeScrollFrames()
        let plain = try XCTUnwrap(ImageStitcher.stitch(frames))
        let withDuplicate = try XCTUnwrap(ImageStitcher.stitch(frames + [frames.last!]))

        XCTAssertEqual(withDuplicate.image.width, plain.image.width)
        XCTAssertEqual(withDuplicate.image.height, plain.image.height)
        XCTAssertEqual(withDuplicate.headerRows, plain.headerRows)
        XCTAssertEqual(withDuplicate.footerRows, plain.footerRows)
        XCTAssertEqual(withDuplicate.usedFallback, plain.usedFallback)
        for y in stride(from: 0, to: plain.image.height, by: 37) {
            TestImages.assertClose(TestImages.pixel(withDuplicate.image, x: Page.width / 2, y: y),
                                   TestImages.pixel(plain.image, x: Page.width / 2, y: y))
        }
    }

    func testFallsBackToConcatenationWithoutOverlap() throws {
        let a = render(width: Page.width, rows: 0..<200) { Noise.color(x: $0, y: $1, salt: 0x11) }
        let b = render(width: Page.width, rows: 0..<150) { Noise.color(x: $0, y: $1, salt: 0x99) }
        let result = try XCTUnwrap(ImageStitcher.stitch([a, b]))

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.image.height, 200 + 150)
        XCTAssertEqual(result.headerRows, 0)
        XCTAssertEqual(result.footerRows, 0)
    }

    func testSingleFrameIsReturnedAsIs() throws {
        let frame = render(width: Page.width, rows: 0..<300) { Noise.color(x: $0, y: $1, salt: 0x42) }
        let result = try XCTUnwrap(ImageStitcher.stitch([frame]))

        XCTAssertEqual(result.image.width, frame.width)
        XCTAssertEqual(result.image.height, frame.height)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.headerRows, 0)
        XCTAssertEqual(result.footerRows, 0)
        for y in stride(from: 0, to: frame.height, by: 40) {
            TestImages.assertClose(TestImages.pixel(result.image, x: 10, y: y), TestImages.pixel(frame, x: 10, y: y))
        }
    }

    /// Frames that are otherwise a solid color, each with one distinct band. Most rows are pixel-identical
    /// between the two frames (gray == gray) no matter how they are aligned, so a matcher that only samples a
    /// few rows per candidate offset could report a match almost anywhere. Only the offset that truly lines up
    /// the two bands may confirm: the full-band mean difference must stay low across every row, not just the
    /// sampled ones, and it must be the *largest* such offset the search considers (see doc comment on
    /// `ImageStitcher.stitch`). This test documents and locks in that expectation.
    func testUniformFramesDoNotFalselyMatchEverywhere() throws {
        let width = 40
        let height = 100
        let gray: UInt8 = 220
        let black: UInt8 = 0
        func frame(band: Range<Int>) -> CGImage {
            render(width: width, rows: 0..<height) { _, y in
                let v = band.contains(y) ? black : gray
                return (v, v, v)
            }
        }
        // Frame A's band sits 20 rows below where frame B's band sits in B's own coordinates; the only
        // consistent scroll alignment is the one that maps both bands to the same absolute page position.
        let frameA = frame(band: 40..<50)
        let frameB = frame(band: 20..<30)

        let result = try XCTUnwrap(ImageStitcher.stitch([frameA, frameB]))
        XCTAssertFalse(result.usedFallback)

        var blackRows = 0
        for y in 0..<result.image.height where TestImages.pixel(result.image, x: 0, y: y).r < 128 {
            blackRows += 1
        }
        // The band must appear exactly once (its own height), never duplicated and never lost.
        XCTAssertEqual(blackRows, 10)
        XCTAssertEqual(result.image.height, 120)
        for y in [0, 10, 19, 50, 70, 90, 119] {
            XCTAssertGreaterThanOrEqual(TestImages.pixel(result.image, x: 0, y: y).r, 128, "row \(y) should be gray")
        }
        for y in 40..<50 {
            XCTAssertLessThan(TestImages.pixel(result.image, x: 0, y: y).r, 128, "row \(y) should be the band")
        }
    }
}
