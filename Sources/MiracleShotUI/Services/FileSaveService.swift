import Foundation
import MiracleShotCore

@MainActor
public final class FileSaveService: FileSaving {
    public init() {}

    public func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = Self.uniqueURL(for: fileName, in: directory)
        try ImageCodec.writePNG(capture.image, to: url)
        return url
    }

    /// "shot.png" -> "shot 2.png" -> "shot 3.png" while the name is taken.
    static func uniqueURL(for fileName: String, in directory: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
