import AppKit
import MiracleShotCore
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeys: HotkeyManager!
    private(set) var coordinator: CaptureCoordinator!
    private let toast = ToastPresenter()
    private let preview = QuickPreviewPanel()
    private let historyMenu = HistoryMenuBuilder()
    private let editor = EditorWindowController()
    private var settingsWindow: SettingsWindowController!
    private var settings = Settings.default
    private let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "app")

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = Settings.load()
        preview.timeout = settings.previewTimeout
        preview.handlers[.reveal] = { _, url in
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        preview.backgroundPresets = BackgroundPresetLibrary.load(
            userDirectory: Settings.supportDirectory.appendingPathComponent("presets", isDirectory: true))
        preview.onApplyBackground = { [weak self] capture, _, preset in
            self?.coordinator.applyBackground(preset, to: capture)
        }
        preview.handlers[.edit] = { [weak self] capture, _ in
            guard let self else { return }
            editor.open(capture: capture, presets: preview.backgroundPresets) { [weak self] image in
                self?.coordinator.publish(image, derivedFrom: capture)
            }
        }
        log.info("Background presets: \(self.preview.backgroundPresets.map(\.id).joined(separator: ", "), privacy: .public)")

        let captureService = ScreenCaptureService()
        coordinator = CaptureCoordinator(
            settings: settings,
            historyURL: Settings.historyURL,
            capture: captureService,
            selection: SelectionOverlayController(capture: captureService, windowList: CGWindowListProvider()),
            clipboard: ClipboardService(),
            files: FileSaveService(),
            notifications: toast,
            preview: preview
        )
        coordinator.onHistoryChange = { [weak self] _ in self?.rebuildMenu() }

        historyMenu.onReveal = { entry in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
        }
        historyMenu.onClear = { [weak self] in
            guard let self else { return }
            coordinator.clearHistory()
        }

        settingsWindow = SettingsWindowController { [weak self] updated in self?.apply(updated) }

        hotkeys = HotkeyManager { [weak self] action in self?.trigger(action) }
        registerHotkeys()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MS"
        rebuildMenu()

        let hasPermission = CGPreflightScreenCaptureAccess()
        log.info("Launched; screen recording permission: \(hasPermission)")
        if !hasPermission {
            _ = CGRequestScreenCaptureAccess()
            toast.post(title: "Screen Recording permission needed",
                       body: "Allow Miracle Shot in System Settings > Privacy & Security > Screen Recording, then relaunch.",
                       isError: true)
        }
    }

    // MARK: - Actions

    private func trigger(_ action: CaptureAction) {
        log.info("Trigger \(action.rawValue, privacy: .public); screen recording permission: \(CGPreflightScreenCaptureAccess())")
        Task { await coordinator.perform(action) }
    }

    private func apply(_ updated: Settings) {
        let hotkeysChanged = updated.hotkeys != settings.hotkeys
        settings = updated
        coordinator.settings = updated
        preview.timeout = updated.previewTimeout
        do {
            try updated.save()
        } catch {
            log.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
        if hotkeysChanged { registerHotkeys() }
        rebuildMenu()
    }

    private func registerHotkeys() {
        let failed = hotkeys.register(settings.hotkeys)
        log.info("Hotkeys registered: \(self.settings.hotkeys.map { "\($0.key.rawValue)=\($0.value.description)" }.joined(separator: ", "), privacy: .public); failed: \(failed.map(\.rawValue), privacy: .public)")
        if !failed.isEmpty {
            toast.post(title: "Some hotkeys are taken",
                       body: failed.map(\.title).joined(separator: ", ") + ". Change them in Settings.", isError: true)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = settings.hotkeys[action] { item.toolTip = spec.description }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let history = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        history.submenu = historyMenu.menu(for: coordinator.history)
        menu.addItem(history)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func menuCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        // Let the menu close before the overlay appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.trigger(action) }
    }

    @objc private func openSettings() {
        settingsWindow.show(settings: settings)
    }
}
