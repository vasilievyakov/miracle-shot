import AppKit
import MiracleShotCore
import struct MiracleShotCore.Settings
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: Settings {
        didSet { onChange?(settings) }
    }
    @Published var hotkeyText: [CaptureAction: String]
    var onChange: ((Settings) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        self.hotkeyText = Dictionary(uniqueKeysWithValues: CaptureAction.allCases.map { ($0, settings.hotkeys[$0]?.description ?? "") })
    }

    /// Errors are shown only after a failed commit (Return), not while typing.
    @Published private(set) var hotkeyErrors: [CaptureAction: String] = [:]

    func hotkeyError(for action: CaptureAction) -> String? {
        hotkeyErrors[action]
    }

    func commitHotkey(for action: CaptureAction) {
        let text = hotkeyText[action] ?? ""
        if text.isEmpty {
            settings.hotkeys.removeValue(forKey: action)
            hotkeyErrors[action] = nil
        } else if let spec = HotkeySpec(parsing: text) {
            settings.hotkeys[action] = spec
            hotkeyText[action] = spec.description
            hotkeyErrors[action] = nil
        } else {
            hotkeyErrors[action] = "Use modifiers plus a key, e.g. shift+cmd+4"
        }
    }

    /// Applies every pending hotkey field, for example when the window closes without Return.
    func commitAllHotkeys() {
        CaptureAction.allCases.forEach { commitHotkey(for: $0) }
    }

    var namingExample: String {
        settings.namingTemplate.fileName(date: Date(), appName: "Safari", sequence: 1)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Hotkeys") {
                ForEach(CaptureAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(action.title, text: Binding(
                            get: { model.hotkeyText[action] ?? "" },
                            set: { model.hotkeyText[action] = $0 }
                        ))
                        .onSubmit { model.commitHotkey(for: action) }
                        if let error = model.hotkeyError(for: action) {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Text("Modifiers: ctrl, opt, shift, cmd. Keys: letters, digits, f1-f12, space, arrows. Press Return to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                HStack {
                    TextField("Save folder", text: $model.settings.saveDirectoryPath)
                    Button("Choose…") { chooseFolder() }
                }
                TextField("File name template", text: $model.settings.namingTemplate.pattern)
                Text("Example: \(model.namingExample)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Slider(value: $model.settings.previewTimeout, in: 2...15, step: 1) {
                    Text("Preview stays \(Int(model.settings.previewTimeout)) s")
                }
                Stepper("Keep \(model.settings.historyLimit) captures in history", value: $model.settings.historyLimit, in: 5...200, step: 5)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.saveDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.saveDirectoryPath = url.path
        }
    }
}
