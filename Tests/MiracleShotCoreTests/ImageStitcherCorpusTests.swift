import CoreGraphics
import XCTest
@testable import MiracleShotCore

/// Runs `ImageStitcher` against the real-world corpus in `Fixtures/scroll/<app>/`, if any is present. See
/// `Fixtures/scroll/README.md` for the corpus layout and how frames are collected.
final class ImageStitcherCorpusTests: XCTestCase {
    func testCorpus() throws {
        guard let scrollRoot = Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appendingPathComponent("scroll") else {
            XCTFail("Fixtures/scroll not found in the test resource bundle")
            return
        }
        let entries = (try? FileManager.default.contentsOfDirectory(at: scrollRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

        guard !folders.isEmpty else {
            print("ImageStitcherCorpusTests: no fixture folders under \(scrollRoot.path); skipping")
            return
        }

        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try runCorpusCase(folder)
        }
    }

    private func runCorpusCase(_ folder: URL) throws {
        let name = folder.lastPathComponent
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)

        let frameURLs = entries
            .filter { $0.lastPathComponent.hasPrefix("frame-") && $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !frameURLs.isEmpty else {
            XCTFail("\(name): no frame-*.png files found")
            return
        }
        let frames = try frameURLs.map { url -> CGImage in
            try XCTUnwrap(ImageCodec.image(at: url), "\(name): failed to decode \(url.lastPathComponent)")
        }

        let expectedURL = folder.appendingPathComponent("expected.png")
        let expected = try XCTUnwrap(ImageCodec.image(at: expectedURL), "\(name): failed to decode expected.png")

        let result = try XCTUnwrap(ImageStitcher.stitch(frames), "\(name): stitch returned nil")

        XCTAssertEqual(result.image.width, expected.width, "\(name): width mismatch")
        XCTAssertEqual(result.image.height, expected.height, "\(name): height mismatch")
        guard result.image.width == expected.width, result.image.height == expected.height else { return }

        // One draw per image; `TestImages.pixel` would redraw the whole stitch for every sample.
        let actualRed = TestImages.channel(result.image, 0)
        let expectedRed = TestImages.channel(expected, 0)
        let grid = 64
        var total = 0.0
        var samples = 0
        for gy in 0..<grid {
            let y = expected.height * gy / grid
            for gx in 0..<grid {
                let x = expected.width * gx / grid
                total += Double(abs(Int(actualRed[y][x]) - Int(expectedRed[y][x])))
                samples += 1
            }
        }
        let meanAbsoluteDifference = samples > 0 ? total / Double(samples) : 0
        XCTAssertLessThanOrEqual(meanAbsoluteDifference, 3, "\(name): mean absolute difference too high (\(meanAbsoluteDifference))")
    }
}
