import Foundation

/// Persisted user settings. Missing fields fall back to defaults so older files keep loading when fields are added;
/// a field with the wrong type fails the whole decode, and `JSONStore` then quarantines the file and returns `.default`.
public struct Settings: Codable, Sendable, Equatable {
    public var hotkeys: [CaptureAction: HotkeySpec]
    public var saveDirectoryPath: String
    public var namingTemplate: NamingTemplate
    public var previewTimeout: TimeInterval
    public var historyLimit: Int

    public static let `default` = Settings(
        hotkeys: [
            .captureArea: HotkeySpec(parsing: "shift+cmd+1")!,
            .captureWindow: HotkeySpec(parsing: "shift+cmd+2")!,
            .captureFullScreen: HotkeySpec(parsing: "shift+cmd+0")!,
            .captureScrolling: HotkeySpec(parsing: "shift+cmd+3")!,
        ],
        saveDirectoryPath: "~/Pictures/Miracle Shot",
        namingTemplate: .default,
        previewTimeout: 6,
        historyLimit: 50
    )

    public init(hotkeys: [CaptureAction: HotkeySpec], saveDirectoryPath: String, namingTemplate: NamingTemplate,
                previewTimeout: TimeInterval, historyLimit: Int) {
        self.hotkeys = hotkeys
        self.saveDirectoryPath = saveDirectoryPath
        self.namingTemplate = namingTemplate
        self.previewTimeout = previewTimeout
        self.historyLimit = historyLimit
    }

    private enum CodingKeys: String, CodingKey {
        case hotkeys, saveDirectoryPath, namingTemplate, previewTimeout, historyLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        if let decoded = try c.decodeIfPresent([CaptureAction: HotkeySpec].self, forKey: .hotkeys) {
            // An older file predates a newer action and simply has no entry for it. Fill it in from the default,
            // unless the user already bound that default combination to a different action of theirs.
            var merged = decoded
            let usedSpecs = Set(decoded.values)
            for (action, spec) in d.hotkeys where merged[action] == nil && !usedSpecs.contains(spec) {
                merged[action] = spec
            }
            hotkeys = merged
        } else {
            hotkeys = d.hotkeys
        }
        saveDirectoryPath = try c.decodeIfPresent(String.self, forKey: .saveDirectoryPath) ?? d.saveDirectoryPath
        namingTemplate = try c.decodeIfPresent(NamingTemplate.self, forKey: .namingTemplate) ?? d.namingTemplate
        previewTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .previewTimeout) ?? d.previewTimeout
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? d.historyLimit
    }

    // MARK: Locations

    public static let supportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Miracle Shot", isDirectory: true)
    public static let settingsURL = supportDirectory.appendingPathComponent("settings.json")
    public static let historyURL = supportDirectory.appendingPathComponent("history.json")
    public static let fallbackSaveDirectory: URL = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Miracle Shot", isDirectory: true)

    /// Absolute folder to save into. A relative or empty path would resolve against the process working directory,
    /// so it falls back to `fallbackSaveDirectory` instead.
    public var saveDirectoryURL: URL {
        let expanded = (saveDirectoryPath as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return Self.fallbackSaveDirectory }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    // MARK: Persistence

    public static func load(from url: URL = settingsURL) -> Settings {
        JSONStore.load(Settings.self, from: url) ?? .default
    }

    public func save(to url: URL = Settings.settingsURL) throws {
        try JSONStore.save(self, to: url)
    }
}
