import AppKit
import MiracleShotCore

@MainActor
public final class ClipboardService: ClipboardServicing {
    public init() {}

    public func copy(_ capture: Capture) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = ImageCodec.pngData(from: capture.image) {
            pasteboard.setData(png, forType: .png)
        }
        let image = NSImage(cgImage: capture.image, size: capture.bounds.size)
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
