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

    /// A blinking cursor or a spinner changes a few pixels of one row between two frames. That row alone may
    /// differ by more than the tolerance, but the band's mean stays far below it, so the true overlap must still
    /// be found instead of falling back to concatenation.
    func testNoisyRowInsideTheOverlapStillMatches() throws {
        let width = Page.width
        let overlap = 40
        func page(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { Noise.color(x: x, y: y, salt: 0x77) }
        let a = render(width: width, rows: 0..<200, colorAt: page)
        let noisyRow = 200 - overlap + 20
        let b = render(width: width, rows: (200 - overlap)..<360) { x, y in
            y == noisyRow && x < 24 ? (255, 255, 255) : page(x, y)
        }

        let result = try XCTUnwrap(ImageStitcher.stitch([a, b]))
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, 360)
    }

    func testFramesOfDifferentHeightsStitch() throws {
        let width = Page.width
        func page(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { Noise.color(x: x, y: y, salt: 0x88) }
        let a = render(width: width, rows: 0..<200, colorAt: page)
        let b = render(width: width, rows: 160..<310, colorAt: page)

        let result = try XCTUnwrap(ImageStitcher.stitch([a, b]))
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, 310)
    }

    /// A user scrolling by hand may go up instead of down: every frame then overlaps the previous one at its
    /// top, and the new rows belong above the page collected so far.
    func testStitchesFramesScrolledUpwards() throws {
        let (frames, page) = makeScrollFrames()
        let result = try XCTUnwrap(ImageStitcher.stitch(frames.reversed()))

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, Page.headerHeight + Page.height + Page.footerHeight)
        for pageRow in stride(from: 0, to: Page.height, by: 50) {
            TestImages.assertClose(TestImages.pixel(result.image, x: Page.width / 2, y: Page.headerHeight + pageRow),
                                   TestImages.pixel(page, x: Page.width / 2, y: pageRow), tolerance: 2)
        }
    }

    /// Scrolling back into content that is already on the page adds nothing: such frames are skipped, not
    /// appended as a fallback.
    func testFramesWithinCollectedContentAreSkipped() throws {
        let (frames, _) = makeScrollFrames()
        let plain = try XCTUnwrap(ImageStitcher.stitch(frames))
        let backAndForth = try XCTUnwrap(ImageStitcher.stitch([frames[0], frames[1], frames[2], frames[1], frames[3], frames[4]]))

        XCTAssertFalse(backAndForth.usedFallback)
        XCTAssertEqual(backAndForth.image.height, plain.image.height)
    }

    /// A "jump to bottom" pill or a hover highlight at the very start of the overlap band must not reject the
    /// band: the mean over the whole band is what counts, not the mean of its first rows.
    func testDynamicElementAtTheStartOfTheBandStillMatches() throws {
        let width = Page.width
        let overlap = 200
        func page(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { Noise.color(x: x, y: y, salt: 0x99) }
        let a = render(width: width, rows: 0..<400, colorAt: page)
        let pillRows = (400 - overlap)..<(400 - overlap + 15)
        let b = render(width: width, rows: (400 - overlap)..<600) { x, y in
            pillRows.contains(y) && x < width * 4 / 10 ? (255, 255, 255) : page(x, y)
        }

        let result = try XCTUnwrap(ImageStitcher.stitch([a, b]))
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, 600)
    }

    /// Translucent window chrome picks up whatever is behind the window, so one frame's header and footer can
    /// differ from the others by a few levels everywhere. Such a frame must not erase the static header and
    /// footer for the whole capture.
    func testHeaderAndFooterSurviveABackdropShiftInOneFrame() throws {
        let (frames, _) = makeScrollFrames()
        var shifted = frames
        let victim = 2
        let frame = frames[victim]
        let ctx = TestImages.context(width: frame.width, height: frame.height)
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in Array(0..<Page.headerHeight) + Array((frame.height - Page.footerHeight)..<frame.height) {
            for x in 0..<frame.width {
                for c in 0..<3 {
                    let i = y * ctx.bytesPerRow + x * 4 + c
                    data[i] = UInt8(min(255, Int(data[i]) + 4))
                }
            }
        }
        shifted[victim] = withExtendedLifetime(ctx) { ctx.makeImage()! }

        let result = try XCTUnwrap(ImageStitcher.stitch(shifted))
        XCTAssertEqual(result.headerRows, Page.headerHeight)
        XCTAssertEqual(result.footerRows, Page.footerHeight)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, Page.headerHeight + Page.height + Page.footerHeight)
    }

    // MARK: - Sticky UI inside the scrolled area

    /// Frames of the page with a band drawn over the top (`stickyTop`) or bottom (`stickyBottom`) rows of every
    /// window, the way a pinned section header or a "jump to bottom" pill sits over scrolled content. The band's
    /// pattern changes with the frame index (`stickySalt`), so it is not a static header or footer of the capture.
    private func makeStickyFrames(stickyTop: Int, stickyBottom: Int) -> [CGImage] {
        let (frames, _) = makeScrollFrames()
        return frames.enumerated().map { index, frame in
            let ctx = TestImages.context(width: frame.width, height: frame.height)
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
            func paint(rows: Range<Int>, salt: Int) {
                for y in rows {
                    for x in 0..<frame.width {
                        let (r, g, b) = Noise.color(x: x, y: y - rows.lowerBound, salt: salt)
                        let i = y * ctx.bytesPerRow + x * 4
                        data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255
                    }
                }
            }
            paint(rows: Page.headerHeight..<(Page.headerHeight + stickyTop), salt: Self.stickySalt(index))
            paint(rows: (Page.headerHeight + Page.frameHeight - stickyBottom)..<(Page.headerHeight + Page.frameHeight),
                  salt: Self.stickySalt(index))
            return withExtendedLifetime(ctx) { ctx.makeImage()! }
        }
    }

    private static func stickySalt(_ frameIndex: Int) -> Int { 0x500 + frameIndex }

    /// A pinned header sits over scrolled content in every frame: scrolling up must not copy it into the page at
    /// every seam. The upward stitch equals the forward one, where the header is never copied.
    func testStickyHeaderIsNotRepeatedWhenScrollingUp() throws {
        let frames = makeStickyFrames(stickyTop: 20, stickyBottom: 0)
        let forward = try XCTUnwrap(ImageStitcher.stitch(frames))
        let upward = try XCTUnwrap(ImageStitcher.stitch(frames.reversed()))

        XCTAssertFalse(forward.usedFallback)
        XCTAssertFalse(upward.usedFallback)
        XCTAssertEqual(forward.image.height, Page.headerHeight + Page.height + Page.footerHeight)
        XCTAssertEqual(upward.image.height, forward.image.height)
        let forwardRed = TestImages.channel(forward.image, 0)
        let upwardRed = TestImages.channel(upward.image, 0)
        for y in stride(from: 0, to: forward.image.height, by: 7) {
            XCTAssertEqual(Int(upwardRed[y][7]), Int(forwardRed[y][7]), accuracy: 2, "row \(y)")
        }
    }

    /// A pinned element at the bottom of every frame must appear once, at the very bottom, not at every seam.
    func testStickyFooterIsNotRepeatedWhenScrollingDown() throws {
        let frames = makeStickyFrames(stickyTop: 0, stickyBottom: 20)
        let result = try XCTUnwrap(ImageStitcher.stitch(frames))
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.image.height, Page.headerHeight + Page.height + Page.footerHeight)

        let red = TestImages.channel(result.image, 0)
        func isPillRow(_ y: Int, _ index: Int) -> Bool {
            (0..<8).allSatisfy { x in abs(Int(red[y][x * 13]) - Int(Noise.color(x: x * 13, y: 0, salt: Self.stickySalt(index)).0)) <= 2 }
        }
        var pillRows: [Int] = []
        for y in 0..<result.image.height where frames.indices.contains(where: { isPillRow(y, $0) }) {
            pillRows.append(y)
        }
        // Only the last frame's pill survives, 20 rows above the footer.
        XCTAssertEqual(pillRows, [Page.headerHeight + Page.height - 20])
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
