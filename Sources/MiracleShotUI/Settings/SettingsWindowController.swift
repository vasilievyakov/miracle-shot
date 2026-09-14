import AppKit
import MiracleShotCore
import struct MiracleShotCore.Settings
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?
    private let onChange: (Settings) -> Void

    public init(onChange: @escaping (Settings) -> Void) {
        self.onChange = onChange
    }

    public func show(settings: Settings) {
        if let window {
            model?.settings = settings
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(settings: settings)
        model.onChange = { [weak self] in self?.onChange($0) }
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Miracle Shot Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
