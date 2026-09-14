import XCTest
@testable import MiracleShotCore

final class WindowInfoParsingTests: XCTestCase {
    private func dict(id: Int = 12, bounds: CGRect = CGRect(x: 10, y: 20, width: 300, height: 200),
                      layer: Int = 0, pid: Int = 500, owner: String? = "Safari", name: String? = "Apple") -> [String: Any] {
        var d: [String: Any] = [
            "kCGWindowNumber": id,
            "kCGWindowBounds": bounds.dictionaryRepresentation,
            "kCGWindowLayer": layer,
            "kCGWindowOwnerPID": pid,
        ]
        if let owner { d["kCGWindowOwnerName"] = owner }
        if let name { d["kCGWindowName"] = name }
        return d
    }

    func testParsesFullDictionary() throws {
        let w = try XCTUnwrap(WindowInfo(windowServerDictionary: dict()))
        XCTAssertEqual(w.id, 12)
        XCTAssertEqual(w.frame, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(w.layer, 0)
        XCTAssertEqual(w.ownerPID, 500)
        XCTAssertEqual(w.ownerName, "Safari")
        XCTAssertEqual(w.title, "Apple")
    }

    func testMissingOptionalFieldsAreTolerated() throws {
        let w = try XCTUnwrap(WindowInfo(windowServerDictionary: dict(owner: nil, name: nil)))
        XCTAssertEqual(w.ownerName, "")
        XCTAssertNil(w.title)
    }

    func testMissingRequiredFieldReturnsNil() {
        var d = dict()
        d.removeValue(forKey: "kCGWindowBounds")
        XCTAssertNil(WindowInfo(windowServerDictionary: d))
    }

    func testDegenerateWindowsAreRejected() {
        XCTAssertNil(WindowInfo(windowServerDictionary: dict(bounds: CGRect(x: 0, y: 0, width: 1, height: 1))))
    }
}
