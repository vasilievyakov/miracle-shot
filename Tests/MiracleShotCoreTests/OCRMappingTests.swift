import XCTest
@testable import MiracleShotCore

final class OCRMappingTests: XCTestCase {
    func testPixelRectFlipsYAxis() {
        let rect = OCRMapping.pixelRect(normalized: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1),
                                         imageSize: CGSize(width: 1000, height: 500))
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 500, height: 50))
    }

    func testBlockFactoryAppliesThePixelMapping() {
        let block = OCRMapping.block(text: "hi", normalized: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1),
                                      confidence: 0.9, imageSize: CGSize(width: 1000, height: 500))
        XCTAssertEqual(block.text, "hi")
        XCTAssertEqual(block.rect, CGRect(x: 100, y: 50, width: 500, height: 50))
        XCTAssertEqual(block.confidence, 0.9)
    }

    func testLineAssemblyOrdersScrambledBlocksAndJoinsAnOffsetBlockToItsLine() {
        // Two blocks on the first line ("Hello", "world"), one offset by 2pt, still overlapping enough to
        // share the line; one block far below starts a second, paragraph-separated line. Given out of order.
        let hello = TextBlock(text: "Hello", rect: CGRect(x: 0, y: 0, width: 50, height: 20), confidence: 1)
        let world = TextBlock(text: "world", rect: CGRect(x: 60, y: 2, width: 50, height: 20), confidence: 1)
        let bye = TextBlock(text: "Bye", rect: CGRect(x: 0, y: 100, width: 40, height: 20), confidence: 1)

        let result = OCRResult(blocks: [bye, hello, world])

        XCTAssertEqual(result.text, "Hello world\n\nBye")
    }

    func testLineAssemblyKeepsCloseLinesOnSeparateLinesWithoutABlankLine() {
        let foo = TextBlock(text: "Foo", rect: CGRect(x: 0, y: 0, width: 40, height: 20), confidence: 1)
        let bar = TextBlock(text: "Bar", rect: CGRect(x: 0, y: 25, width: 40, height: 20), confidence: 1)

        let result = OCRResult(blocks: [foo, bar])

        XCTAssertEqual(result.text, "Foo\nBar")
    }

    func testPreviewSkipsEmptyLinesFromParagraphBreaks() {
        let hello = TextBlock(text: "Hello", rect: CGRect(x: 0, y: 0, width: 50, height: 20), confidence: 1)
        let world = TextBlock(text: "world", rect: CGRect(x: 60, y: 2, width: 50, height: 20), confidence: 1)
        let bye = TextBlock(text: "Bye", rect: CGRect(x: 0, y: 100, width: 40, height: 20), confidence: 1)
        let result = OCRResult(blocks: [bye, hello, world])

        XCTAssertEqual(result.preview(lines: 2), "Hello world\nBye")
    }

    func testEmptyResultTextIsEmptyString() {
        XCTAssertEqual(OCRResult(blocks: []).text, "")
        XCTAssertEqual(OCRResult(blocks: []).preview(lines: 2), "")
    }

    func testIsEmpty() {
        XCTAssertTrue(OCRResult(blocks: []).isEmpty)
        let block = TextBlock(text: "x", rect: CGRect(x: 0, y: 0, width: 10, height: 10), confidence: 1)
        XCTAssertFalse(OCRResult(blocks: [block]).isEmpty)
    }

    /// The line's first block is the reference: C overlaps B by 12 but A by only 4, so C starts a new line.
    func testLineAssemblyComparesAgainstTheLinesFirstBlockNotTheLastAppended() {
        let a = TextBlock(text: "A", rect: CGRect(x: 0, y: 0, width: 20, height: 20), confidence: 1)
        let b = TextBlock(text: "B", rect: CGRect(x: 30, y: 8, width: 20, height: 20), confidence: 1)
        let c = TextBlock(text: "C", rect: CGRect(x: 60, y: 16, width: 20, height: 20), confidence: 1)
        XCTAssertEqual(OCRResult(blocks: [a, b, c]).text, "A B\nC")
    }
}
