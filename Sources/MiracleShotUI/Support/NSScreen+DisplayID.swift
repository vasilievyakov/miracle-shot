import AppKit

extension NSScreen {
    public var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The screen containing the mouse cursor, falling back to the main screen.
    public static var underCursor: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// Height of the primary screen; needed to flip between AppKit and CG coordinates.
    public static var primaryHeight: CGFloat { screens.first?.frame.height ?? 0 }
}
