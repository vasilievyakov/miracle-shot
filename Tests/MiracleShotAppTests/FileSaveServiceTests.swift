import XCTest
import MiracleShotCore
@testable import MiracleShotUI

@MainActor
final class FileSaveServiceTests: XCTestCase {
    func testSavesPNGAndAvoidsOverwriting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = FileSaveService()
        let first = try service.save(makeCapture(), named: "shot.png", in: dir)
        let second = try service.save(makeCapture(), named: "shot.png", in: dir)
        let third = try service.save(makeCapture(), named: "shot.png", in: dir)
        XCTAssertEqual(first.lastPathComponent, "shot.png")
        XCTAssertEqual(second.lastPathComponent, "shot 2.png")
        XCTAssertEqual(third.lastPathComponent, "shot 3.png")
        XCTAssertNotNil(ImageCodec.image(at: second))
    }

    func testThrowsWhenDirectoryCannotBeCreated() {
        let service = FileSaveService()
        XCTAssertThrowsError(try service.save(makeCapture(), named: "x.png", in: URL(fileURLWithPath: "/System/nope")))
    }
}
