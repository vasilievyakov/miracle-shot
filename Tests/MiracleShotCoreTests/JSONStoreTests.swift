import XCTest
@testable import MiracleShotCore

final class JSONStoreTests: XCTestCase {
    private struct Doc: Codable, Equatable { var name: String; var when: Date }
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(JSONStore.load(Doc.self, from: dir.appendingPathComponent("x.json")))
    }

    func testRoundTripCreatesDirectories() throws {
        let url = dir.appendingPathComponent("nested/doc.json")
        let doc = Doc(name: "a", when: Date(timeIntervalSince1970: 1_000_000))
        try JSONStore.save(doc, to: url)
        XCTAssertEqual(JSONStore.load(Doc.self, from: url), doc)
    }

    func testCorruptFileIsRenamedToBrokenAndLoadsNil() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        XCTAssertNil(JSONStore.load(Doc.self, from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("doc.json.broken").path))
    }

    func testSecondCorruptFileReplacesOldBroken() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("bad1".utf8).write(to: url)
        _ = JSONStore.load(Doc.self, from: url)
        try Data("bad2".utf8).write(to: url)
        _ = JSONStore.load(Doc.self, from: url)
        let broken = try String(contentsOf: dir.appendingPathComponent("doc.json.broken"), encoding: .utf8)
        XCTAssertEqual(broken, "bad2")
    }

    func testFractionalSecondsSurviveRoundTrip() throws {
        let url = dir.appendingPathComponent("doc.json")
        let doc = Doc(name: "a", when: Date(timeIntervalSince1970: 1_726_300_000.789))
        try JSONStore.save(doc, to: url)
        let loaded = try XCTUnwrap(JSONStore.load(Doc.self, from: url))
        XCTAssertEqual(loaded.when.timeIntervalSince1970, 1_726_300_000.789, accuracy: 0.001)
    }

    func testWholeSecondDatesFromOlderFilesStillDecode() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"name":"a","when":"2026-09-14T14:05:09Z"}"#.utf8).write(to: url)
        XCTAssertEqual(JSONStore.load(Doc.self, from: url)?.when, Date(timeIntervalSince1970: 1_789_394_709))
    }

    func testUnreadableFileIsNotQuarantined() throws {
        let url = dir.appendingPathComponent("doc.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertNil(JSONStore.load(Doc.self, from: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("doc.json.broken").path))
    }
}
