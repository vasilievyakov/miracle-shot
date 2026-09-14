import Foundation
import os

public enum BackgroundPresetLibrary {
    private static let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "presets")

    /// Built-in presets from the Core resource bundle, in file-name order (`01-…`, `02-…`).
    public static func builtIn() -> [BackgroundPreset] {
        guard let dir = CoreResources.bundle.url(forResource: "presets", withExtension: nil) else {
            log.error("Built-in presets folder is missing from the resource bundle")
            return []
        }
        return presets(in: dir)
    }

    /// Built-in presets followed by the user's own `*.json` files. A missing folder is normal; a file that does not
    /// decode is skipped and logged so one typo cannot hide the built-ins.
    public static func load(userDirectory: URL) -> [BackgroundPreset] {
        builtIn() + presets(in: userDirectory)
    }

    private static func presets(in directory: URL) -> [BackgroundPreset] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    return try decoder.decode(BackgroundPreset.self, from: Data(contentsOf: url))
                } catch {
                    log.error("Skipping preset \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
    }
}
