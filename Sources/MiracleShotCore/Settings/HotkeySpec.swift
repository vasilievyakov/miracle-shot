/// A global hotkey such as `shift+cmd+4`. Parsed from and rendered to a canonical string.
public struct HotkeySpec: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public enum Modifier: String, Codable, Sendable, CaseIterable, Hashable {
        case control, option, shift, command

        /// Carbon `controlKey`, `optionKey`, `shiftKey`, `cmdKey` bit masks.
        var carbonFlag: UInt32 {
            switch self {
            case .command: return 1 << 8
            case .shift: return 1 << 9
            case .option: return 1 << 11
            case .control: return 1 << 12
            }
        }

        var shortName: String {
            switch self {
            case .control: return "ctrl"
            case .option: return "opt"
            case .shift: return "shift"
            case .command: return "cmd"
            }
        }

        static let aliases: [String: Modifier] = [
            "cmd": .command, "command": .command,
            "shift": .shift,
            "opt": .option, "option": .option, "alt": .option,
            "ctrl": .control, "control": .control,
        ]
    }

    public let key: String
    public let modifiers: Set<Modifier>

    public init?(key: String, modifiers: Set<Modifier>) {
        guard !modifiers.isEmpty, KeyCodeMap.code(for: key) != nil else { return nil }
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public init?(parsing text: String) {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard parts.count >= 2, let key = parts.last, !key.isEmpty else { return nil }
        var mods = Set<Modifier>()
        for part in parts.dropLast() {
            guard let m = Modifier.aliases[part] else { return nil }
            mods.insert(m)
        }
        self.init(key: key, modifiers: mods)
    }

    /// Canonical order: ctrl, opt, shift, cmd, then the key.
    public var description: String {
        (Modifier.allCases.filter { modifiers.contains($0) }.map(\.shortName) + [key]).joined(separator: "+")
    }

    public var carbonKeyCode: UInt32 { KeyCodeMap.code(for: key) ?? 0 }
    public var carbonModifiers: UInt32 { modifiers.reduce(0) { $0 | $1.carbonFlag } }
}
