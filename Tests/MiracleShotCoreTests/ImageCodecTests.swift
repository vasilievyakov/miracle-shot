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
}
