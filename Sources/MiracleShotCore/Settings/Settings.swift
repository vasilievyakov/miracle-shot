import Foundation

/// Persisted user settings. Every field has a default so older files keep loading when fields are added.
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
        hotkeys = try c.decodeIfPresent([CaptureAction: HotkeySpec].self, forKey: .hotkeys) ?? d.hotkeys
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

    public var saveDirectoryURL: URL {
        URL(fileURLWithPath: (saveDirectoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    // MARK: Persistence

    public static func load(from url: URL = settingsURL) -> Settings {
        JSONStore.load(Settings.self, from: url) ?? .default
    }

    public func save(to url: URL = Settings.settingsURL) throws {
        try JSONStore.save(self, to: url)
    }
}
