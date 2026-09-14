import XCTest
@testable import MiracleShotCore

final class ImageCodecTests: XCTestCase {
    func testPNGRoundTripKeepsPixels() throws {
        let image = TestImages.solid(width: 4, height: 3, r: 1, g: 0, b: 0)
        let data = try XCTUnwrap(ImageCodec.pngData(from: image))
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let decoded = try XCTUnwrap(ImageCodec.image(from: data))
        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 3)
        TestImages.assertClose(TestImages.pixel(decoded, x: 1, y: 1), .init(r: 255, g: 0, b: 0, a: 255))
    }

    func testWritePNGCreatesFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try ImageCodec.writePNG(TestImages.solid(width: 2, height: 2, r: 0, g: 1, b: 0), to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testGarbageDataDecodesToNil() {
        XCTAssertNil(ImageCodec.image(from: Data("nope".utf8)))
    }

    func testPixelHelperReadsTopRowFirst() {
        let red = TestImages.RGBA(r: 255, g: 0, b: 0, a: 255)
        let blue = TestImages.RGBA(r: 0, g: 0, b: 255, a: 255)
        let image = TestImages.splitHorizontally(width: 4, height: 4, top: red, bottom: blue)
        TestImages.assertClose(TestImages.pixel(image, x: 1, y: 0), red)
        TestImages.assertClose(TestImages.pixel(image, x: 1, y: 3), blue)
        let decoded = ImageCodec.image(from: ImageCodec.pngData(from: image)!)!
        TestImages.assertClose(TestImages.pixel(decoded, x: 2, y: 0), red)
        TestImages.assertClose(TestImages.pixel(decoded, x: 2, y: 3), blue)
    }

    func testPixelHelperReturnsStraightAlpha() {
        let image = TestImages.solid(width: 2, height: 2, r: 1, g: 0, b: 0, a: 0.5)
        TestImages.assertClose(TestImages.pixel(image, x: 0, y: 0), .init(r: 255, g: 0, b: 0, a: 128), tolerance: 3)
    }
}
