import AppKit
import MiracleShotCore

/// Builds the History submenu. Thumbnails are loaded lazily and cached by path.
@MainActor
public final class HistoryMenuBuilder {
    public var onReveal: ((HistoryEntry) -> Void)?
    public var onClear: (() -> Void)?
    private var thumbnails: [String: NSImage] = [:]

    public init() {}

    public func menu(for history: HistoryIndex) -> NSMenu {
        let menu = NSMenu(title: "History")
        if history.entries.isEmpty {
            let empty = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for entry in history.entries {
            let item = NSMenuItem(title: HistoryPresentation.title(for: entry), action: #selector(reveal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id.uuidString
            item.image = thumbnail(for: entry)
            item.attributedTitle = attributedTitle(for: entry)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clear(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        currentEntries = history.entries
        return menu
    }

    private var currentEntries: [HistoryEntry] = []

    private func attributedTitle(for entry: HistoryEntry) -> NSAttributedString {
        let title = NSMutableAttributedString(string: HistoryPresentation.title(for: entry) + "\n",
                                              attributes: [.font: NSFont.menuFont(ofSize: 13)])
        title.append(NSAttributedString(string: HistoryPresentation.subtitle(for: entry), attributes: [
            .font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    private func thumbnail(for entry: HistoryEntry) -> NSImage? {
        if let cached = thumbnails[entry.path] { return cached }
        // Downsampled decode: the cache holds real thumbnails, not full-resolution captures.
        guard let cg = ImageCodec.thumbnail(at: URL(fileURLWithPath: entry.path), maxPixelSize: 96) else { return nil }
        let fitted = ImageFit.size(CGSize(width: cg.width, height: cg.height),
                                    into: CGSize(width: 48, height: 32),
                                    minimum: CGSize(width: 24, height: 16))
        let image = NSImage(cgImage: cg, size: NSSize(width: fitted.width, height: fitted.height))
        thumbnails[entry.path] = image
        return image
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let entry = currentEntries.first(where: { $0.id.uuidString == raw }) else { return }
        onReveal?(entry)
    }

    @objc private func clear(_ sender: NSMenuItem) { onClear?() }
}
