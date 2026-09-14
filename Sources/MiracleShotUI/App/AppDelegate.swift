import AppKit
import MiracleShotCore
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeys: HotkeyManager!
    private(set) var coordinator: CaptureCoordinator!
    private let toast = ToastPresenter()
    private let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "app")

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settings = Settings.load()
        coordinator = CaptureCoordinator(
            settings: settings,
            historyURL: Settings.historyURL,
            capture: ScreenCaptureService(),
            selection: SelectionOverlayController(),
            clipboard: ClipboardService(),
            files: FileSaveService(),
            notifications: toast,
            preview: ImmediateDismissPreview()
        )
        hotkeys = HotkeyManager { [weak self] action in
            self?.trigger(action)
        }
        let failed = hotkeys.register(settings.hotkeys)
        log.info("Hotkeys registered: \(settings.hotkeys.map { "\($0.key.rawValue)=\($0.value.description)" }.joined(separator: ", "), privacy: .public); failed: \(failed.map(\.rawValue), privacy: .public)")
        if !failed.isEmpty {
            toast.post(title: "Some hotkeys are taken",
                       body: failed.map(\.title).joined(separator: ", ") + ". Change them in Settings.", isError: true)
        }
        buildStatusItem(settings: settings)
        let hasPermission = CGPreflightScreenCaptureAccess()
        log.info("Launched; screen recording permission: \(hasPermission)")
        if !hasPermission {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func trigger(_ action: CaptureAction) {
        log.info("Trigger \(action.rawValue, privacy: .public); screen recording permission: \(CGPreflightScreenCaptureAccess())")
        Task { await coordinator.perform(action) }
    }

    private func buildStatusItem(settings: Settings) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MS"
        statusItem.menu = buildMenu(settings: settings)
    }

    func buildMenu(settings: Settings) -> NSMenu {
        let menu = NSMenu()
        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            if let spec = settings.hotkeys[action] { item.toolTip = spec.description }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Miracle Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func menuCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        // Let the menu close before the overlay appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.trigger(action) }
    }
}
